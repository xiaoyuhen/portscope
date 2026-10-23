import Foundation

/// Turns raw sockets plus process details into the `PortInfo` rows the UI shows.
public struct PortAggregator: Sendable {
    public init() {}

    /// Groups listeners by port.
    ///
    /// A port is owned by exactly one process in normal operation, but during a
    /// handover (`SO_REUSEPORT` load balancing, or a restart where the old and
    /// new process briefly overlap) two processes can share it. The oldest
    /// process wins so the row stays stable instead of flickering between
    /// owners; the other is kept as a note on the row.
    public func aggregate(
        listeners: [RawListener],
        inspector: ProcessInspector
    ) -> [PortInfo] {
        let grouped = Dictionary(grouping: listeners, by: \.port)
        return grouped.keys.sorted().map { port in
            let sockets = grouped[port]!
            // Pick a deterministic owner: lowest pid, which is the one that was
            // there first in every restart scenario.
            let ownerPID = sockets.map(\.pid).min()!
            let addresses = Array(Set(sockets.map(\.address))).sorted(by: addressOrder)
            let exposure = Self.exposure(for: addresses)
            let details = inspector.details(for: ownerPID)

            let uptime = details.startedAt.map { Date().timeIntervalSince($0) }
            let arguments = details.arguments

            return PortInfo(
                port: port,
                addresses: addresses,
                exposure: exposure,
                pid: ownerPID,
                processName: details.name,
                executablePath: details.executablePath,
                arguments: arguments,
                workingDirectory: details.workingDirectory,
                uptime: uptime,
                appBundleName: details.appBundleName,
                service: nil
            )
        }
    }

    /// A port is only as private as its most exposed socket.
    static func exposure(for addresses: [String]) -> Exposure {
        if addresses.contains("0.0.0.0") || addresses.contains("::") {
            return .allInterfaces
        }
        let isLoopbackOnly = addresses.allSatisfy(Self.isLoopback)
        return isLoopbackOnly ? .loopback : .interface
    }

    static func isLoopback(_ address: String) -> Bool {
        address == "::1" || address == "localhost" || address.hasPrefix("127.")
    }

    /// Loopback first, then wildcard, then concrete interface addresses; each
    /// group sorted so the row doesn't reshuffle between refreshes.
    private func addressOrder(_ lhs: String, _ rhs: String) -> Bool {
        let rank: (String) -> Int = { address in
            if Self.isLoopback(address) { return 0 }
            if address == "0.0.0.0" || address == "::" { return 1 }
            return 2
        }
        let (l, r) = (rank(lhs), rank(rhs))
        return l == r ? lhs < rhs : l < r
    }
}
