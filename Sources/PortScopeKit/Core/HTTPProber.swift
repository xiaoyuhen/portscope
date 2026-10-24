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
///   address, even when the service is bound to one.
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
    private var cache: [Int: (result: HTTPProbeResult, at: Date)] = [:]
    /// Services that speak HTTP rarely change their headers, but dev servers do
    /// restart with new frameworks, so results are re-taken after a minute.
    private let cacheLifetime: TimeInterval = 60

    public init(timeout: TimeInterval = 1.0) {
        self.timeout = timeout
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.httpMaximumConnectionsPerHost = 1
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Loopback only: never route a probe through a configured proxy.
        config.connectionProxyDictionary = [:]
        session = URLSession(configuration: config)
    }

    /// Probe `port` on 127.0.0.1, unless the port is a database or otherwise
    /// known not to speak HTTP.
    public func probe(port: Int, force: Bool = false) async -> HTTPProbeResult? {
        if !force, let cached = cache[port], Date().timeIntervalSince(cached.at) < cacheLifetime {
            return cached.result
        }

        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("PortScope/0.1 (local port scanner)", forHTTPHeaderField: "User-Agent")
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
            cache[port] = (result, Date())
            return result
        } catch let error as URLError where error.code == .cannotConnectToHost {
            // Nothing is listening any more; drop any stale entry.
            cache[port] = nil
            return nil
        } catch {
            // The connection was accepted but the exchange failed: not HTTP,
            // or HTTP we could not finish reading. Report it as non-HTTP.
            let result = HTTPProbeResult(status: 0, headers: [:], bodyPrefix: "", spokeHTTP: false)
            cache[port] = (result, Date())
            return result
        }
    }

    public func invalidate(port: Int) {
        cache[port] = nil
    }
}
