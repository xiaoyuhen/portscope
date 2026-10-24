import Darwin
import Foundation

/// A running container that publishes a port on this Mac.
public struct ContainerInfo: Codable, Sendable, Hashable {
    /// The full container id, as the engine API takes it.
    public var id: String
    /// `acme-web-1`, without Docker's leading slash.
    public var name: String
    public var image: String
    /// The Compose project and service, when the container came from Compose.
    public var composeProject: String?
    public var composeService: String?
    /// Which engine answered: the socket path, so stop and restart go back to
    /// the same one.
    public var engineSocket: String
}

/// Reads published ports from the local Docker engine.
///
/// On a Mac every published container port is held by the engine's forwarder
/// — `com.docker.backend`, OrbStack, a Lima ssh — so the process alone says
/// "Docker" for every one of them, and stopping that process stops the engine
/// and every container with it. The engine API is what knows which container
/// owns the port.
///
/// The API is spoken directly over the engine's Unix socket: Docker Desktop,
/// OrbStack, Colima and Rancher Desktop all serve the same API, and the CLI is
/// not needed (nor is `DOCKER_HOST`, which an app launched from Finder never
/// sees). Nothing here touches the network.
public enum DockerEngine {
    /// Where engines put their socket, most common first.
    public static var candidateSockets: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.docker/run/docker.sock",          // Docker Desktop 4.13+
            "\(home)/.orbstack/run/docker.sock",        // OrbStack
            "\(home)/.colima/default/docker.sock",      // Colima
            "\(home)/.colima/docker.sock",              // Colima, older
            "\(home)/.rd/docker.sock",                  // Rancher Desktop
            "/var/run/docker.sock",                     // anything that links here
        ]
    }

    /// Published TCP host ports and the container behind each, from every
    /// engine that answers. Empty, quickly, when no engine is running.
    public static func publishedPorts(sockets: [String] = candidateSockets) -> [Int: ContainerInfo] {
        var result: [Int: ContainerInfo] = [:]
        var seen = Set<String>()
        for socket in sockets {
            // /var/run/docker.sock is usually a link to one of the others.
            let resolved = (socket as NSString).resolvingSymlinksInPath
            guard FileManager.default.fileExists(atPath: resolved),
                  seen.insert(resolved).inserted,
                  let response = request("GET", "/containers/json", socket: resolved),
                  response.status == 200 else { continue }
            for (port, container) in parseContainers(response.body, socket: resolved)
            where result[port] == nil {
                result[port] = container
            }
        }
        return result
    }

    /// Stops a container the way `docker stop` does: SIGTERM, then SIGKILL
    /// after the engine's grace period.
    public static func stop(_ container: ContainerInfo) -> Bool {
        action("stop", container)
    }

    public static func restart(_ container: ContainerInfo) -> Bool {
        action("restart", container)
    }

    private static func action(_ verb: String, _ container: ContainerInfo) -> Bool {
        // The id comes from the engine itself, but it goes into a request
        // line, so anything other than hex is refused outright.
        guard !container.id.isEmpty,
              container.id.allSatisfy({ $0.isHexDigit }) else { return false }
        // The engine waits up to t seconds before killing; the socket must
        // wait a little longer than that.
        guard let response = request(
            "POST", "/containers/\(container.id)/\(verb)?t=10",
            socket: container.engineSocket, timeout: 20
        ) else { return false }
        // 204: done. 304: it was already in that state.
        return response.status == 204 || response.status == 304
    }

    // MARK: - Parsing

    /// The fields of `GET /containers/json` that matter here.
    private struct ContainerSummary: Decodable {
        struct Port: Decodable {
            var PrivatePort: Int?
            var PublicPort: Int?
            var `Type`: String?
        }
        var Id: String
        var Names: [String]?
        var Image: String?
        var Ports: [Port]?
        var Labels: [String: String]?
    }

    static func parseContainers(_ body: Data, socket: String) -> [Int: ContainerInfo] {
        guard let summaries = try? JSONDecoder().decode([ContainerSummary].self, from: body) else {
            return [:]
        }
        var result: [Int: ContainerInfo] = [:]
        for summary in summaries {
            let name = (summary.Names?.first ?? String(summary.Id.prefix(12)))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let container = ContainerInfo(
                id: summary.Id,
                name: name,
                image: summary.Image ?? "",
                composeProject: summary.Labels?["com.docker.compose.project"],
                composeService: summary.Labels?["com.docker.compose.service"],
                engineSocket: socket
            )
            for port in summary.Ports ?? [] where port.Type == "tcp" {
                if let published = port.PublicPort, published > 0 {
                    result[published] = container
                }
            }
        }
        return result
    }

    // MARK: - HTTP over a Unix socket

    struct Response {
        var status: Int
        var body: Data
    }

    /// One HTTP/1.0 request. 1.0 so the engine closes the connection when it
    /// is done and the body is simply everything that follows the headers;
    /// chunked bodies are decoded anyway in case an engine sends one.
    static func request(
        _ method: String, _ path: String, socket path_: String, timeout: TimeInterval = 1
    ) -> Response? {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        var interval = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path_.utf8.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: path_.utf8)
            raw[path_.utf8.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        let requestText = "\(method) \(path) HTTP/1.0\r\nHost: docker\r\nContent-Length: 0\r\n\r\n"
        let sent = requestText.withCString { write(fd, $0, strlen($0)) }
        guard sent > 0 else { return nil }

        var raw = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while raw.count < 8 * 1024 * 1024 {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            raw.append(buffer, count: count)
        }
        return parseResponse(raw)
    }

    static func parseResponse(_ raw: Data) -> Response? {
        guard let split = raw.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: raw[..<split.lowerBound], as: UTF8.self)
        let statusLine = head.split(separator: "\r\n").first ?? ""
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2, let status = Int(parts[1]) else { return nil }
        var body = Data(raw[split.upperBound...])
        if head.lowercased().contains("transfer-encoding: chunked") {
            body = dechunk(body)
        }
        return Response(status: status, body: body)
    }

    private static func dechunk(_ data: Data) -> Data {
        var output = Data()
        var index = data.startIndex
        let crlf = Data("\r\n".utf8)
        while index < data.endIndex,
              let lineEnd = data.range(of: crlf, in: index..<data.endIndex) {
            let sizeText = String(decoding: data[index..<lineEnd.lowerBound], as: UTF8.self)
                .split(separator: ";").first.map(String.init) ?? ""
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16),
                  size > 0 else { break }
            let start = lineEnd.upperBound
            let end = data.index(start, offsetBy: size, limitedBy: data.endIndex) ?? data.endIndex
            output.append(data[start..<end])
            index = data.index(end, offsetBy: 2, limitedBy: data.endIndex) ?? data.endIndex
        }
        return output
    }
}
