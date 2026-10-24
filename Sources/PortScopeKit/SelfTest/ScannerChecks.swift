import Darwin
import Foundation

enum ScannerChecks {
    static var all: [(String, () throws -> Void)] {
        [
            ("a socket we open ourselves shows up in the scan", {
                let listener = try LoopbackListener()
                defer { listener.close() }
                let found = LibprocScanner.scan().filter {
                    $0.port == listener.port && $0.pid == getpid()
                }
                try expect(!found.isEmpty,
                           "port \(listener.port) owned by pid \(getpid()) was not reported")
            }),
            ("IPv4 loopback binds are reported as 127.0.0.1", {
                let listener = try LoopbackListener()
                defer { listener.close() }
                let addresses = LibprocScanner.scan()
                    .filter { $0.port == listener.port }
                    .map(\.address)
                try expect(addresses.contains("127.0.0.1"),
                           "expected 127.0.0.1 among \(addresses)")
            }),
            ("a service bound to ::1 alone is probed on ::1", {
                // Node 18+ binds `localhost` to ::1 only; probing 127.0.0.1
                // there found nothing and the HTTP evidence was lost.
                try expectEqual(HTTPProber.loopbackHost(for: ["::1"]), "[::1]", "::1")
                try expectEqual(HTTPProber.loopbackHost(for: ["::"]), "[::1]", "::")
                try expectEqual(HTTPProber.loopbackHost(for: ["127.0.0.1", "::1"]), "127.0.0.1", "dual")
                try expectEqual(HTTPProber.loopbackHost(for: ["0.0.0.0"]), "127.0.0.1", "wildcard")
            }),
            ("aggregation keeps one row per port", {
                let listeners = [
                    RawListener(pid: 10, port: 8080, address: "127.0.0.1", family: AF_INET),
                    RawListener(pid: 10, port: 8080, address: "::1", family: AF_INET6),
                ]
                let rows = PortAggregator().aggregate(
                    listeners: listeners, inspector: ProcessInspector()
                )
                try expectEqual(rows.count, 1, "row count")
                try expectEqual(rows[0].addresses, ["127.0.0.1", "::1"], "addresses")
            }),
            ("a wildcard bind makes the port network-reachable", {
                try expectEqual(
                    PortAggregator.exposure(for: ["127.0.0.1", "0.0.0.0"]),
                    .allInterfaces, "exposure"
                )
                try expectEqual(
                    PortAggregator.exposure(for: ["127.0.0.1", "::1"]),
                    .loopback, "exposure"
                )
                try expectEqual(
                    PortAggregator.exposure(for: ["192.168.1.7"]),
                    .interface, "exposure"
                )
            }),
            ("two processes sharing a port get a stable owner", {
                let listeners = [
                    RawListener(pid: 42, port: 9000, address: "127.0.0.1", family: AF_INET),
                    RawListener(pid: 7, port: 9000, address: "127.0.0.1", family: AF_INET),
                ]
                let rows = PortAggregator().aggregate(
                    listeners: listeners, inspector: ProcessInspector()
                )
                try expectEqual(rows.count, 1, "row count")
                try expectEqual(rows[0].pid, 7, "owner pid")
            }),
            ("our own argv is read back intact", {
                // The harness is launched with --selftest, so that flag must be
                // present in the argv the kernel reports for this process.
                let args = ProcessInspector().arguments(of: getpid(), executablePath: nil)
                try expect(args.contains("--selftest"),
                           "argv was \(args)")
                try expect(args.allSatisfy { !$0.isEmpty },
                           "argv contains empty padding: \(args)")
            }),
        ]
    }
}

/// A real TCP listener on an ephemeral loopback port, owned by this process.
/// Using a real socket rather than a fixture is what makes the scan check
/// end-to-end: it exercises the same libproc path the app uses.
final class LoopbackListener {
    let port: Int
    private let fd: Int32

    init() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw CheckFailure(description: "socket() failed") }
        fd = descriptor

        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // let the kernel pick
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            Darwin.close(descriptor)
            throw CheckFailure(description: "bind() failed: \(String(cString: strerror(errno)))")        }
        guard listen(fd, 1) == 0 else {
            Darwin.close(descriptor)
            throw CheckFailure(description: "listen() failed")
        }

        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard named == 0 else {
            Darwin.close(descriptor)
            throw CheckFailure(description: "getsockname() failed")
        }
        port = Int(UInt16(bigEndian: actual.sin_port))
    }

    func close() { _ = Darwin.close(fd) }
}
