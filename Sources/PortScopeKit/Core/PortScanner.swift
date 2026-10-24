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
            probes = await probeAll(candidates)
            await prober.retain(ports: Set(ports.map(\.port)))
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

        // Published container ports are all held by the engine's forwarder;
        // the engine API says which container each one belongs to.
        let containers = DockerEngine.publishedPorts()
        if !containers.isEmpty {
            ports = ports.map { info in
                guard let container = containers[info.port] else { return info }
                var attributed = info
                attributed.container = container
                attributed.service = Self.containerService(container, http: info.service)
                return attributed
            }
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
    private func probeAll(_ ports: [PortInfo]) async -> [Int: HTTPProbeResult] {
        var results: [Int: HTTPProbeResult] = [:]
        let batchSize = 16
        for start in stride(from: 0, to: ports.count, by: batchSize) {
            let batch = Array(ports[start..<min(start + batchSize, ports.count)])
            await withTaskGroup(of: (Int, HTTPProbeResult?).self) { group in
                for info in batch {
                    let host = HTTPProber.loopbackHost(for: info.addresses)
                    let started = inspector.details(for: info.pid).startedAt?.timeIntervalSince1970 ?? 0
                    let owner = "\(info.pid):\(started)"
                    group.addTask { [prober] in
                        (info.port, await prober.probe(port: info.port, host: host, owner: owner))
                    }
                }
                for await (port, result) in group {
                    if let result { results[port] = result }
                }
            }
        }
        return results
    }

    /// The service shown for a container's port: the container by name, with
    /// the image and Compose project as evidence. HTTP evidence already taken
    /// for the port is kept — "nginx" answering HTTP 200 is still worth saying.
    static func containerService(_ container: ContainerInfo, http: ServiceInfo?) -> ServiceInfo {
        var detail = container.image
        if let project = container.composeProject, let service = container.composeService {
            detail += " · compose \(project)/\(service)"
        }
        let evidence = [Evidence(sourceKey: "evidence.container", detail: detail, weight: 0.99)]
            + (http?.evidence.filter { $0.sourceKey.hasPrefix("evidence.http") } ?? [])
        return ServiceInfo(
            kind: .container,
            title: container.name,
            summaryKey: "service.dockerContainer",
            confidence: 0.99,
            evidence: evidence,
            httpStatus: http?.httpStatus,
            serverHeader: http?.serverHeader,
            projectPath: nil,
            projectName: container.composeProject
        )
    }

    /// Re-reads process metadata on the next scan. Used after a restart, when
    /// the same port is now owned by a different process.
    public func invalidateCache() {
        inspector.invalidate()
    }
}
