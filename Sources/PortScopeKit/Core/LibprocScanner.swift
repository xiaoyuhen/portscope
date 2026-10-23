import Darwin
import Foundation

/// A raw listening socket as reported by the kernel, before any process or
/// service information is attached.
public struct RawListener: Sendable, Hashable {
    public var pid: pid_t
    public var port: Int
    public var address: String
    public var family: Int32
}

/// Enumerates every TCP socket in LISTEN state using `libproc`.
///
/// This is deliberately not `lsof`: libproc answers in a few milliseconds,
/// needs no parsing of human-readable output, and cannot be confused by a
/// process name that contains spaces. It also needs no elevated privileges —
/// the kernel exposes socket tables for the current user's processes, and for
/// other users' processes it exposes everything except their command line.
public enum LibprocScanner {
    /// All listening TCP sockets, IPv4 and IPv6, de-duplicated by pid+port.
    ///
    /// A process commonly holds two sockets for one port — one IPv4 and one
    /// IPv6, or one per interface — and a person thinks of that as one service.
    /// So sockets are grouped by (pid, port) and the bound addresses collected.
    public static func scan() -> [RawListener] {
        var seen = Set<String>()
        var listeners: [RawListener] = []

        for pid in allPids() {
            for socket in listeningSockets(of: pid) {
                let key = "\(pid):\(socket.port):\(socket.address)"
                guard seen.insert(key).inserted else { continue }
                listeners.append(socket)
            }
        }
        return listeners.sorted { $0.port < $1.port }
    }

    /// Every process id the kernel will name. The list is sized by asking for
    /// a count first, then padded because processes can appear between the two
    /// calls.
    static func allPids() -> [pid_t] {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        let capacity = Int(bytes) / MemoryLayout<pid_t>.size + 32
        var pids = [pid_t](repeating: 0, count: capacity)
        let written = proc_listpids(
            UInt32(PROC_ALL_PIDS), 0, &pids, Int32(capacity * MemoryLayout<pid_t>.size)
        )
        guard written > 0 else { return [] }
        return pids.prefix(Int(written) / MemoryLayout<pid_t>.size).filter { $0 > 0 }
    }

    /// TCP sockets in LISTEN state held by `pid`.
    static func listeningSockets(of pid: pid_t) -> [RawListener] {
        var fdBytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard fdBytes > 0 else { return [] }

        // The table can grow between the size query and the read, so retry
        // once with extra headroom before giving up.
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(fdBytes) / MemoryLayout<proc_fdinfo>.size + 32)
        fdBytes = proc_pidinfo(
            pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * MemoryLayout<proc_fdinfo>.size)
        )
        guard fdBytes > 0 else { return [] }

        var result: [RawListener] = []
        let count = Int(fdBytes) / MemoryLayout<proc_fdinfo>.size
        for index in 0..<count {
            let fd = fds[index]
            guard fd.proc_fdtype == PROX_FDTYPE_SOCKET else { continue }

            var socketInfo = socket_fdinfo()
            let size = proc_pidfdinfo(
                pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &socketInfo,
                Int32(MemoryLayout<socket_fdinfo>.size)
            )
            guard size == MemoryLayout<socket_fdinfo>.size else { continue }

            let info = socketInfo.psi
            guard info.soi_kind == SOCKINFO_TCP else { continue }

            let tcp = info.soi_proto.pri_tcp
            guard tcp.tcpsi_state == TSI_S_LISTEN else { continue }

            // The port is stored network byte order in the low 16 bits.
            let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)))
            guard port > 0 else { continue }

            let address = addressString(from: tcp.tcpsi_ini, family: info.soi_family)
            result.append(RawListener(pid: pid, port: port, address: address, family: info.soi_family))
        }
        return result
    }

    /// Formats a bound address as a person would write it: `127.0.0.1`,
    /// `0.0.0.0`, `::1`, `::`, or the concrete interface address.
    static func addressString(from ini: in_sockinfo, family: Int32) -> String {
        // insi_laddr is a 16-byte union holding either in_addr or in6_addr,
        // always in network byte order.
        var bytes = ini.insi_laddr.ina_46.i46a_addr4
        let v4 = withUnsafeBytes(of: &bytes) { Array($0) }
        if family == AF_INET {
            return "\(v4[0]).\(v4[1]).\(v4[2]).\(v4[3])"
        }
        var addr6 = ini.insi_laddr.ina_6
        let raw = withUnsafeBytes(of: &addr6) { Array($0) }
        var storage = in6_addr()
        withUnsafeMutableBytes(of: &storage) { dest in
            raw.prefix(16).enumerated().forEach { dest[$0.offset] = $0.element }
        }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        var addr = storage
        guard inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else {
            return "::"
        }
        return String(cString: buffer)
    }
}
