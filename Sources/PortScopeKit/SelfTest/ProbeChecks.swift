import Darwin
import Foundation

/// Checks for how often the HTTP prober touches a service. A probe is a real
/// request in someone's dev-server log, so "how many" is part of the contract.
enum ProbeChecks {
    static var all: [(String, () async throws -> Void)] {
        [
            ("one process is probed once, not once a minute", {
                let server = try CountingHTTPServer()
                defer { server.close() }
                let prober = HTTPProber()
                for _ in 0..<3 {
                    _ = await prober.probe(port: server.port, owner: "100:1")
                }
                try expectEqual(server.requests, 1, "requests for one owner")
            }),
            ("a new process on the same port is probed again", {
                let server = try CountingHTTPServer()
                defer { server.close() }
                let prober = HTTPProber()
                _ = await prober.probe(port: server.port, owner: "100:1")
                _ = await prober.probe(port: server.port, owner: "200:2")
                try expectEqual(server.requests, 2, "requests across a restart")
            }),
        ]
    }
}

/// A loopback HTTP server that answers every request with 200 and counts them.
private final class CountingHTTPServer: @unchecked Sendable {
    let port: Int
    private let listener: LoopbackListener
    private let lock = NSLock()
    private var count = 0

    var requests: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    init() throws {
        listener = try LoopbackListener()
        port = listener.port
        let fd = listener.descriptor
        Thread.detachNewThread { [self] in
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }  // closed: the check is over
                var buffer = [UInt8](repeating: 0, count: 1024)
                _ = read(client, &buffer, buffer.count)
                let response = "HTTP/1.0 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
                _ = response.withCString { write(client, $0, strlen($0)) }
                Darwin.close(client)
                lock.lock()
                count += 1
                lock.unlock()
            }
        }
    }

    /// `shutdown` first: on Darwin, closing a socket does not wake a thread
    /// already blocked in `accept` on it, and that thread would outlive the check.
    func close() {
        shutdown(listener.descriptor, SHUT_RDWR)
        listener.close()
    }
}
