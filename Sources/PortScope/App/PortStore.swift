import Combine
import Foundation
import PortScopeKit

/// The app's single source of truth about the machine.
///
/// Owns the scanner, the refresh timer and the derived state the UI reads.
/// Everything here is `@MainActor`: views observe it, and the scanning itself
/// happens off the main actor inside `PortScanner`.
@MainActor
final class PortStore: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all, development, databases, exposed, system
        var id: String { rawValue }

        /// Which rows this filter keeps. Filters are deliberately few: more
        /// than a handful turns a list into a query builder.
        func matches(_ info: PortInfo) -> Bool {
            switch self {
            case .all:
                return true
            case .development:
                return [.devServer, .bundler, .web, .api].contains(info.service?.kind)
            case .databases:
                return [.database, .cache].contains(info.service?.kind)
            case .exposed:
                return info.exposure.isPubliclyReachable
            case .system:
                return info.service?.kind == .system
            }
        }
    }

    @Published private(set) var ports: [PortInfo] = []
    @Published private(set) var lastScan: Date?
    @Published private(set) var isScanning = false
    /// Ports that appeared since the previous scan, for the "new" badge.
    @Published private(set) var recentlyAppeared: Set<Int> = []
    /// Non-nil when scanning failed in a way worth telling the user about.
    @Published private(set) var scanError: String?

    /// Ports that opened or closed while the app was running. Newest first.
    /// Capped so a long session cannot grow it without bound.
    @Published private(set) var activity: [PortEvent] = []

    @Published var filter: Filter = .all
    @Published var searchText = ""

    /// Refresh interval in seconds. Changing it restarts the timer.
    @Published var refreshInterval: TimeInterval {
        didSet { restartTimer() }
    }

    /// Ports the user has chosen to ignore; persisted across launches.
    @Published private(set) var hiddenPorts: Set<Int> {
        didSet { UserDefaults.standard.set(Array(hiddenPorts), forKey: Self.hiddenKey) }
    }

    private static let hiddenKey = "PortScope.hiddenPorts"
    private static let activityLimit = 60
    private let scanner = PortScanner()
    private var timer: Timer?
    private var scanTask: Task<Void, Never>?

    init(refreshInterval: TimeInterval = 2) {
        self.refreshInterval = refreshInterval
        let stored = UserDefaults.standard.array(forKey: Self.hiddenKey) as? [Int] ?? []
        hiddenPorts = Set(stored)
        start()
    }

    // MARK: - Derived state

    var visiblePorts: [PortInfo] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return ports.filter { info in
            guard !hiddenPorts.contains(info.port), filter.matches(info) else { return false }
            guard !query.isEmpty else { return true }
            return [info.processName, info.service?.title ?? "", info.service?.projectName ?? "",
                    info.workingDirectory ?? "", String(info.port)]
                .contains { $0.lowercased().contains(query) }
        }
    }

    var totalCount: Int { ports.count }
    var hiddenCount: Int { ports.filter { hiddenPorts.contains($0.port) }.count }
    var exposedCount: Int { ports.filter(\.exposure.isPubliclyReachable).count }
    /// Development-facing ports: dev servers, bundlers, and the generic web /
    /// API servers that are almost always a `node` or `python` process someone
    /// started locally. Counting only `.devServer` showed 0 while four dev
    /// servers were plainly running, because a bare `node` process identifies
    /// as `.web`.
    var developmentCount: Int {
        ports.filter {
            [.devServer, .bundler, .web, .api].contains($0.service?.kind)
        }.count
    }
    var databaseCount: Int {
        ports.filter { [.database, .cache].contains($0.service?.kind) }.count
    }

    /// Counts per filter, shown next to each filter's name.
    func count(for filter: Filter) -> Int {
        ports.filter { !hiddenPorts.contains($0.port) && filter.matches($0) }.count
    }

    // MARK: - Scanning

    func start() {
        restartTimer()
        refresh()
    }

    func restartTimer() {
        timer?.invalidate()
        guard refreshInterval > 0 else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // The list is a table; letting the timer drift during a drag makes
        // rows jump under the cursor.
        timer.tolerance = refreshInterval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// One refresh. Overlapping calls are coalesced: a slow scan (many ports,
    /// several HTTP probes) must not queue up a backlog of scans behind it.
    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        scanTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await scanner.snapshot()
            await MainActor.run {
                self.apply(snapshot)
                self.isScanning = false
            }
        }
    }

    /// After a stop or restart, the same port changes owner. Re-read process
    /// metadata immediately rather than waiting for the next tick.
    func refreshAfterProcessChange() {
        Task {
            await scanner.invalidateCache()
            await MainActor.run { self.refresh() }
        }
    }

    private func apply(_ snapshot: PortSnapshot) {
        let previous = Dictionary(uniqueKeysWithValues: ports.map { ($0.port, $0) })
        ports = snapshot.ports
        lastScan = snapshot.capturedAt
        scanError = nil
        recordActivity(snapshot, previous: previous)
        recentlyAppeared = snapshot.newPorts
        // The "new" badge is a moment, not a state: clear it after a few
        // seconds so the list settles.
        if !snapshot.newPorts.isEmpty {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                await MainActor.run { self?.recentlyAppeared = [] }
            }
        }
    }

    /// Records what changed since the last scan. The event captures the name at
    /// the time of the change, because by the next scan the process may be
    /// gone and its name unrecoverable.
    private func recordActivity(_ snapshot: PortSnapshot, previous: [Int: PortInfo]) {
        guard !snapshot.newPorts.isEmpty || !snapshot.closedPorts.isEmpty else { return }
        let now = snapshot.capturedAt
        var events: [PortEvent] = []

        for info in snapshot.ports where snapshot.newPorts.contains(info.port) {
            events.append(PortEvent(
                id: UUID(), date: now, port: info.port, kind: .appeared,
                title: info.service?.title ?? info.processName,
                processName: info.processName
            ))
        }
        for port in snapshot.closedPorts {
            let gone = previous[port]
            events.append(PortEvent(
                id: UUID(), date: now, port: port, kind: .closed,
                title: gone?.service?.title ?? gone?.processName ?? "",
                processName: gone?.processName ?? ""
            ))
        }

        activity = (events + activity).prefix(Self.activityLimit).map { $0 }
    }

    // MARK: - Mutations

    func hide(port: Int) {
        hiddenPorts.insert(port)
    }

    func unhide(port: Int) {
        hiddenPorts.remove(port)
    }

    func unhideAll() {
        hiddenPorts.removeAll()
    }
}

/// One change to the machine: a port opened or closed.
struct PortEvent: Identifiable, Sendable, Hashable {
    enum Kind: Sendable { case appeared, closed }

    let id: UUID
    let date: Date
    let port: Int
    let kind: Kind
    /// Service title at the time, e.g. "Vite". Empty if unknown.
    let title: String
    let processName: String

    var label: String { title.isEmpty ? processName : title }
}
