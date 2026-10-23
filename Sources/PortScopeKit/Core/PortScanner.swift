import Foundation

/// Periodically scans the machine and publishes snapshots.
///
/// A port watcher is a long-lived object owned by the UI; it owns its polling
/// task and cancels it on deinit so a closed window stops consuming CPU.
public actor PortScanner {
    private let aggregator = PortAggregator()
    private let inspector = ProcessInspector()
    private var previousPorts: Set<Int> = []
    private var hasScannedOnce = false

    public init() {}

    /// One scan, diffed against the previous one.
    public func snapshot() -> PortSnapshot {
        let listeners = LibprocScanner.scan()
        let ports = aggregator.aggregate(listeners: listeners, inspector: inspector)
        let current = Set(ports.map(\.port))

        let snapshot = PortSnapshot(
            ports: ports,
            capturedAt: Date(),
            // The first scan is the baseline, not a burst of "new" ports.
            newPorts: hasScannedOnce ? current.subtracting(previousPorts) : [],
            closedPorts: hasScannedOnce ? previousPorts.subtracting(current) : []
        )
        previousPorts = current
        hasScannedOnce = true
        return snapshot
    }

    /// Re-reads process metadata on the next scan. Used after a restart, when
    /// the same port is now owned by a different process.
    public func invalidateCache() {
        inspector.invalidate()
    }
}
