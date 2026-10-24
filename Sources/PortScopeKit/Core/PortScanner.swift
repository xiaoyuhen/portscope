import Foundation

/// Periodically scans the machine and publishes snapshots.
///
/// A port watcher is a long-lived object owned by the UI; it owns its polling
/// task and cancels it on deinit so a closed window stops consuming CPU.
public actor PortScanner {
    private let aggregator = PortAggregator()
    private let inspector = ProcessInspector()
    private let identifier = ServiceIdentifier()
    private let prober: HTTPProber
    private var previousPorts: Set<Int> = []
    private var hasScannedOnce = false

    /// - Parameter probeHTTP: when false, skips HTTP probing entirely. The
    ///   self-test harness uses this so checks stay hermetic and fast.
    public init(probeHTTP: Bool = true) {
        self.prober = HTTPProber()
        self.probeHTTP = probeHTTP
    }

    private let probeHTTP: Bool

    /// One scan, diffed against the previous one.
    public func snapshot() async -> PortSnapshot {
        let listeners = LibprocScanner.scan()
        var ports = aggregator.aggregate(listeners: listeners, inspector: inspector)

        // Identify each port. Process-only identification is synchronous; the
        // HTTP tier needs a network round trip, so probes are gathered first.
        var probes: [Int: HTTPProbeResult] = [:]
        if probeHTTP {
            let candidates = ports.filter { info in
                let details = inspector.details(for: info.pid)
                let processMatch = ServiceCatalog.processFingerprints
                    .first { $0.matches(details) }?.match
                return identifier.shouldProbe(port: info.port, kind: processMatch?.kind)
            }
            probes = await probeAll(candidates.map(\.port))
        }

        ports = ports.map { info in
            let details = inspector.details(for: info.pid)
            var identified = info
            identified.service = identifier.identify(
                port: info.port,
                details: details,
                probe: probes[info.port]
            )
            return identified
        }

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

    /// Probes ports concurrently, in a bounded batch.
    ///
    /// The bound exists so a machine with 40 dev servers does not open 40
    /// sockets at once, but it also sets the worst case: a batch takes as long
    /// as its slowest port, and a port that accepts a connection and then says
    /// nothing (Redis, Postgres, SSH) burns the whole timeout. With a
    /// batch of 8 that put a cold scan near 4 s, which is far too slow for a
    /// list that refreshes every couple of seconds.
    ///
    /// A batch of 16 with a 1 s timeout keeps the socket count modest and cuts
    /// the cold path roughly in half. The timeout is still generous enough for
    /// a local HTTP server, which answers in single-digit milliseconds.
    private func probeAll(_ ports: [Int]) async -> [Int: HTTPProbeResult] {
        var results: [Int: HTTPProbeResult] = [:]
        let batchSize = 16
        for start in stride(from: 0, to: ports.count, by: batchSize) {
            let batch = Array(ports[start..<min(start + batchSize, ports.count)])
            await withTaskGroup(of: (Int, HTTPProbeResult?).self) { group in
                for port in batch {
                    group.addTask { [prober] in
                        (port, await prober.probe(port: port))
                    }
                }
                for await (port, result) in group {
                    if let result { results[port] = result }
                }
            }
        }
        return results
    }

    /// Re-reads process metadata on the next scan. Used after a restart, when
    /// the same port is now owned by a different process.
    public func invalidateCache() {
        inspector.invalidate()
    }
}
