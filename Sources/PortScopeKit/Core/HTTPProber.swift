import Foundation

/// What a single HTTP request to a local port told us.
public struct HTTPProbeResult: Sendable, Hashable {
    public var status: Int
    public var headers: [String: String]
    /// First few hundred bytes of the body, used only for weak hints like a
    /// `<title>` tag. Never displayed raw.
    public var bodyPrefix: String
    /// True when the port accepted a TCP connection but spoke something other
    /// than HTTP. That is itself useful: it means a database or another
    /// protocol lives here, not a web server.
    public var spokeHTTP: Bool
}

/// Probes local ports over HTTP to learn what is behind them.
///
/// The probe is deliberately minimal and local-only:
///
/// * It only ever connects to a loopback address, never to a LAN interface
///   address, even when the service is bound to one — and it never follows a
///   redirect, which would let a local service send it to any host at all.
/// * It sends a plain `GET /` with a fixed User-Agent and reads at most a few
///   kilobytes, so it cannot be used to make a local service do real work.
/// * Timeouts are short. A port that does not answer in 1s is simply not
///   probed again until the next refresh.
///
/// Some services (SSH, Redis, Postgres) will accept the connection and then
/// either hang or close it. Those are reported as `spokeHTTP == false`, which
/// the identifier treats as evidence of a non-HTTP service.
public actor HTTPProber {
    private let session: URLSession
    private let timeout: TimeInterval
    private var cache: [Int: (result: HTTPProbeResult, owner: String, at: Date)] = [:]
    /// An answer is kept for as long as the same process owns the port.
    ///
    /// Probes used to be re-taken every minute, and a probe is a real `GET /`:
    /// Django, Flask and Rails print every request, so a PortScope left
    /// running wrote a line into the developer's terminal once a minute, and
    /// a service with auth logged a failed request just as often. What a
    /// process serves does not change while it runs — a restart is a new
    /// process — so one answer per process is enough.
    ///
    /// A failed probe is retried after this long instead: a dev server that
    /// was still compiling its first page when it was asked (Next.js can take
    /// longer than the timeout) should not be labelled non-HTTP for its whole
    /// life. Retrying a non-HTTP port costs nobody a log line.
    private let failureRetry: TimeInterval = 60

    public init(timeout: TimeInterval = 1.0) {
        self.timeout = timeout
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.httpMaximumConnectionsPerHost = 1
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Loopback only: never route a probe through a configured proxy.
        config.connectionProxyDictionary = [:]
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }

    /// The loopback address to probe a service bound to `addresses` on.
    ///
    /// IPv4 when the service has any IPv4 socket, otherwise `::1`. Probing
    /// 127.0.0.1 unconditionally missed every service bound to `::1` alone —
    /// which is what Node 18+ does for `localhost`, so Vite and friends lost
    /// their HTTP evidence.
    public static func loopbackHost(for addresses: [String]) -> String {
        let hasIPv4 = addresses.contains { !$0.contains(":") }
        return hasIPv4 ? "127.0.0.1" : "[::1]"
    }

    /// Probe `port` on loopback, unless the port is a database or otherwise
    /// known not to speak HTTP.
    ///
    /// - Parameter owner: identifies the process that owns the port (its pid
    ///   and start time). A cached answer is reused only for the same owner.
    public func probe(
        port: Int,
        host: String = "127.0.0.1",
        owner: String = "",
        force: Bool = false
    ) async -> HTTPProbeResult? {
        if !force, let cached = cache[port], cached.owner == owner,
           cached.result.spokeHTTP || Date().timeIntervalSince(cached.at) < failureRetry {
            return cached.result
        }

        guard host == "127.0.0.1" || host == "[::1]",
              let url = URL(string: "http://\(host):\(port)/") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("PortScope (local port scanner)", forHTTPHeaderField: "User-Agent")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                headers[String(describing: key).lowercased()] = String(describing: value)
            }
            let result = HTTPProbeResult(
                status: http.statusCode,
                headers: headers,
                bodyPrefix: String(decoding: data.prefix(2048), as: UTF8.self),
                spokeHTTP: true
            )
            cache[port] = (result, owner, Date())
            return result
        } catch let error as URLError where error.code == .cannotConnectToHost {
            // Nothing is listening any more; drop any stale entry.
            cache[port] = nil
            return nil
        } catch {
            // The connection was accepted but the exchange failed: not HTTP,
            // or HTTP we could not finish reading. Report it as non-HTTP.
            let result = HTTPProbeResult(status: 0, headers: [:], bodyPrefix: "", spokeHTTP: false)
            cache[port] = (result, owner, Date())
            return result
        }
    }

    public func invalidate(port: Int) {
        cache[port] = nil
    }

    /// Forgets ports that are no longer listening, so the cache stays the size
    /// of the machine's port list over a long session.
    public func retain(ports: Set<Int>) {
        cache = cache.filter { ports.contains($0.key) }
    }
}

/// Declines every redirect. The 3xx response itself is returned to the
/// caller, which is what identification wants anyway: a `Location` header is
/// evidence, following it is a request to a host nobody chose.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
