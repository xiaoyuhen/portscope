import Darwin
import Foundation

/// Checks for container attribution. No Docker is needed: a fake engine on a
/// Unix socket serves what `GET /containers/json` returns, and records what
/// PortScope asks it to do.
enum DockerChecks {
    /// The shape of a real engine response, trimmed to the fields that matter
    /// plus a few that must be ignored.
    static let sample = """
    [
      {"Id": "4f1c2a9b8e7d", "Names": ["/acme-web-1"], "Image": "nginx:1.27",
       "State": "running",
       "Ports": [
         {"IP": "0.0.0.0", "PrivatePort": 80, "PublicPort": 8080, "Type": "tcp"},
         {"IP": "::", "PrivatePort": 80, "PublicPort": 8080, "Type": "tcp"},
         {"IP": "0.0.0.0", "PrivatePort": 53, "PublicPort": 5353, "Type": "udp"},
         {"PrivatePort": 9000, "Type": "tcp"}
       ],
       "Labels": {"com.docker.compose.project": "acme", "com.docker.compose.service": "web"}},
      {"Id": "a0b1c2d3e4f5", "Names": ["/pg"], "Image": "postgres:16",
       "Ports": [{"IP": "127.0.0.1", "PrivatePort": 5432, "PublicPort": 15432, "Type": "tcp"}],
       "Labels": {}}
    ]
    """

    static var all: [(String, () async throws -> Void)] {
        [
            ("published container ports are attributed by name", {
                let map = DockerEngine.parseContainers(Data(sample.utf8), socket: "/x")
                try expectEqual(map[8080]?.name, "acme-web-1", "8080")
                try expectEqual(map[8080]?.composeProject, "acme", "compose project")
                try expectEqual(map[8080]?.composeService, "web", "compose service")
                try expectEqual(map[15432]?.image, "postgres:16", "15432")
                try expect(map[5353] == nil, "a UDP port was attributed")
                try expect(map[9000] == nil, "an unpublished port was attributed")
            }),
            ("a container port is a container, and never folded", {
                let map = DockerEngine.parseContainers(Data(sample.utf8), socket: "/x")
                let service = PortScanner.containerService(map[8080]!, http: nil)
                try expectEqual(service.kind, .container, "kind")
                try expectEqual(service.title, "acme-web-1", "title")
                try expectEqual(service.projectName, "acme", "project")
            }),
            ("containers are read from the engine socket", {
                let engine = try FakeEngine(response: http(200, body: sample))
                defer { engine.close() }
                let map = DockerEngine.publishedPorts(sockets: [engine.path])
                try expectEqual(map[8080]?.name, "acme-web-1", "8080")
                try expectEqual(engine.requests.first, "GET /containers/json HTTP/1.0", "request")
            }),
            ("a chunked engine response is decoded", {
                let chunked = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
                    + chunk(String(sample.prefix(100))) + chunk(String(sample.dropFirst(100))) + "0\r\n\r\n"
                let engine = try FakeEngine(response: chunked)
                defer { engine.close() }
                let map = DockerEngine.publishedPorts(sockets: [engine.path])
                try expectEqual(map[15432]?.name, "pg", "15432")
            }),
            ("stopping a container asks the engine, not a signal", {
                let engine = try FakeEngine(response: http(204, body: ""))
                defer { engine.close() }
                var container = DockerEngine.parseContainers(Data(sample.utf8), socket: engine.path)[8080]!
                container.engineSocket = engine.path
                try expect(DockerEngine.stop(container), "stop reported failure")
                try expectEqual(engine.requests.first,
                                "POST /containers/4f1c2a9b8e7d/stop?t=10 HTTP/1.0", "request")
            }),
            ("a container id that is not hex is never sent", {
                let engine = try FakeEngine(response: http(204, body: ""))
                defer { engine.close() }
                let hostile = ContainerInfo(
                    id: "x/../../v1/kill", name: "x", image: "", composeProject: nil,
                    composeService: nil, engineSocket: engine.path
                )
                try expect(!DockerEngine.restart(hostile), "a hostile id was accepted")
                try expectEqual(engine.requests.count, 0, "requests sent")
            }),
            ("no engine means no containers, quickly", {
                let start = Date()
                let map = DockerEngine.publishedPorts(sockets: ["/nonexistent/docker.sock"])
                try expect(map.isEmpty, "containers from nowhere")
                try expect(Date().timeIntervalSince(start) < 0.5, "a missing engine was slow")
            }),
        ]
    }

    private static func http(_ status: Int, body: String) -> String {
        "HTTP/1.1 \(status) X\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
    }

    private static func chunk(_ text: String) -> String {
        String(text.utf8.count, radix: 16) + "\r\n" + text + "\r\n"
    }
}

/// A one-response-per-connection server on a Unix socket in the temp folder.
private final class FakeEngine: @unchecked Sendable {
    let path: String
    private let fd: Int32
    private let lock = NSLock()
    private var lines: [String] = []

    var requests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    init(response: String) throws {
        // Short: sun_path holds 104 bytes, and the temp folder is long.
        path = "/tmp/ps-\(getpid())-\(UInt32.random(in: 0...UInt32.max)).sock"
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CheckFailure(description: "socket() failed") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = self.path
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: path.utf8)
            raw[path.utf8.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 4) == 0 else {
            Darwin.close(fd)
            throw CheckFailure(description: "bind/listen on \(path) failed")
        }
        let listening = fd
        Thread.detachNewThread { [self] in
            while true {
                let client = accept(listening, nil, nil)
                guard client >= 0 else { return }
                var request = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while request.range(of: Data("\r\n\r\n".utf8)) == nil {
                    let count = read(client, &buffer, buffer.count)
                    if count <= 0 { break }
                    request.append(buffer, count: count)
                }
                let line = String(decoding: request, as: UTF8.self)
                    .components(separatedBy: "\r\n").first ?? ""
                lock.lock()
                lines.append(line)
                lock.unlock()
                _ = response.withCString { write(client, $0, strlen($0)) }
                Darwin.close(client)
            }
        }
    }

    func close() {
        shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
        unlink(path)
    }
}
