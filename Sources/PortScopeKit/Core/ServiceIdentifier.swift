import Foundation

/// Combines every available signal into one `ServiceInfo` per port.
///
/// Evidence is gathered in three tiers, strongest first:
///
/// 1. **Process** — the executable, its argv and its working directory. A
///    `manage.py runserver` is Django with near-certainty; this tier is what
///    makes the answer trustworthy.
/// 2. **HTTP** — response headers. `Server: AirTunes` identifies the AirPlay
///    receiver even though the process is just `ControlCenter`.
/// 3. **Well-known port** — the weakest tier, only used when nothing above
///    matched, and always labelled as a guess.
///
/// The three are merged rather than replaced: a Node process on 3000 that
/// answers with `X-Powered-By: Express` reports "Express" (HTTP tier, 0.85)
/// with the Node observation kept as supporting evidence.
public struct ServiceIdentifier: Sendable {
    /// Ports that never speak HTTP, so probing them wastes a timeout and would
    /// produce a misleading "not HTTP" note.
    private static let nonHTTPPorts: Set<Int> = [22, 3306, 5432, 6379, 27017, 9092, 11211, 5672]

    public init() {}

    public func identify(
        port: Int,
        details: ProcessDetails,
        probe: HTTPProbeResult?
    ) -> ServiceInfo {
        var evidence: [Evidence] = []
        var candidates: [(ServiceMatch, sourceKey: String)] = []

        // Tier 1: process fingerprints.
        if let processMatch = matchProcess(details) {
            candidates.append((processMatch, "evidence.process"))
            evidence.append(Evidence(
                sourceKey: "evidence.process",
                detail: describeProcess(details),
                weight: processMatch.confidence
            ))
        }

        // Tier 2: HTTP fingerprints.
        if let probe, probe.spokeHTTP {
            if let headerMatch = matchHeaders(probe.headers) {
                candidates.append((headerMatch, "evidence.httpHeader"))
                let headerName = ServiceCatalog.httpFingerprints
                    .first { $0.matches(probe.headers) }?.header ?? "server"
                evidence.append(Evidence(
                    sourceKey: "evidence.httpHeader",
                    detail: "\(headerName): \(probe.headers[headerName] ?? "")",
                    weight: headerMatch.confidence
                ))
            } else {
                // It answered HTTP but nothing recognised it. That is still
                // worth saying: "a web server is here".
                evidence.append(Evidence(
                    sourceKey: "evidence.httpStatus",
                    detail: "HTTP \(probe.status)",
                    weight: 0.2
                ))
            }
        } else if probe != nil {
            evidence.append(Evidence(
                sourceKey: "evidence.nonHTTP",
                detail: "",
                weight: 0.3
            ))
        }

        // It answered HTTP but nothing recognised it: say so rather than
        // "unknown", because "an HTTP server is here" is already useful.
        if candidates.isEmpty, let probe, probe.spokeHTTP {
            let looksLikeJSON = probe.headers["content-type"]?.contains("json") == true
            candidates.append((
                ServiceMatch(
                    kind: looksLikeJSON ? .api : .web,
                    title: looksLikeJSON ? L10nKey.httpAPI : L10nKey.httpServer,
                    summaryKey: looksLikeJSON ? "service.genericAPI" : "service.genericHTTP",
                    confidence: 0.35
                ),
                "evidence.httpStatus"
            ))
        }

        // Tier 3: well-known port, only if the stronger tiers were silent.
        if candidates.isEmpty, let portMatch = ServiceCatalog.portFingerprints.first(where: { $0.port == port }) {
            candidates.append((portMatch.match, "evidence.wellKnownPort"))
            evidence.append(Evidence(
                sourceKey: "evidence.wellKnownPort",
                detail: String(port),
                weight: portMatch.match.confidence
            ))
        }

        // Pick the strongest candidate. Ties go to the earlier (process) tier.
        let best = candidates.max { $0.0.confidence < $1.0.confidence }?.0
            ?? ServiceMatch(
                kind: .other,
                title: L10nKey.unknownService,
                summaryKey: "service.unknown",
                confidence: 0.1
            )

        // Corroboration: an independent tier that *agrees* with the winner
        // raises confidence. Mere extra observations must not, or a vague
        // "Node.js" (0.55) would outrank a precise "HTTP API" (0.35) just
        // because the port also answered HTTP.
        // Only a *different* candidate agreeing counts; the winner matching
        // itself would bump every result by a flat 5%.
        let agrees = candidates.contains { $0.0 != best && $0.0.kind == best.kind }
        let confidence = min(0.99, best.confidence + (agrees ? 0.05 : 0))

        let project = projectInfo(for: details)
        return ServiceInfo(
            kind: best.kind,
            title: best.title,
            summaryKey: best.summaryKey,
            confidence: confidence,
            evidence: evidence.sorted { $0.weight > $1.weight },
            httpStatus: probe?.spokeHTTP == true ? probe?.status : nil,
            serverHeader: probe?.headers["server"],
            projectPath: project?.path,
            projectName: project?.name
        )
    }

    /// Whether a port is worth an HTTP probe at all.
    public func shouldProbe(port: Int, kind: ServiceInfo.Kind?) -> Bool {
        if Self.nonHTTPPorts.contains(port) { return false }
        if kind == .database || kind == .cache { return false }
        return true
    }

    // MARK: - Matching

    private func matchProcess(_ details: ProcessDetails) -> ServiceMatch? {
        ServiceCatalog.processFingerprints
            .first { $0.matches(details) }?
            .match
    }

    private func matchHeaders(_ headers: [String: String]) -> ServiceMatch? {
        ServiceCatalog.httpFingerprints
            .first { $0.matches(headers) }?
            .match
    }

    /// A compact description of why the process tier matched, for the evidence
    /// list. Shows the executable name plus the argument that gave it away.
    private func describeProcess(_ details: ProcessDetails) -> String {
        if details.arguments.count > 1 {
            return details.arguments.dropFirst().prefix(3).joined(separator: " ")
        }
        return details.executablePath.map { ($0 as NSString).lastPathComponent } ?? details.name
    }

    // MARK: - Project attribution

    /// Finds the project a service belongs to by walking up from its working
    /// directory to the nearest directory that looks like a project root.
    ///
    /// The signal that matters in practice is a manifest file: `package.json`,
    /// `pyproject.toml`, `go.mod`, `Cargo.toml`. A process whose cwd is
    /// `…/acme-web/src/server` should be attributed to `acme-web`, not to
    /// `server`, which is why this walks up rather than taking the basename.
    func projectInfo(for details: ProcessDetails) -> (path: String, name: String)? {
        guard let cwd = details.workingDirectory else { return nil }
        let manifests = [
            "package.json", "pyproject.toml", "Cargo.toml", "go.mod",
            "Gemfile", "pom.xml", "build.gradle", "composer.json", "mix.exs",
        ]

        var directory = cwd
        var depth = 0
        while depth < 6 {
            let candidate = (directory as NSString).appendingPathComponent("package.json")
            _ = candidate
            for manifest in manifests {
                let file = (directory as NSString).appendingPathComponent(manifest)
                if FileManager.default.fileExists(atPath: file) {
                    return (directory, (directory as NSString).lastPathComponent)
                }
            }
            let parent = (directory as NSString).deletingLastPathComponent
            if parent == directory || parent == "/" || parent.isEmpty { break }
            directory = parent
            depth += 1
        }
        // No manifest anywhere. Only fall back to the directory name when it
        // looks like a project folder rather than a system container path —
        // "Data" from ~/Library/Containers is noise, not a project.
        let name = (cwd as NSString).lastPathComponent
        let systemRoots = ["/Library", "/System", "/private/var", "/Users/Shared"]
        let isSystemPath = systemRoots.contains { cwd.hasPrefix($0) }
        if isSystemPath || name == "Data" || name.isEmpty { return nil }
        return (cwd, name)
    }
}

/// Keys that are not translations but sentinels.
enum L10nKey {
    /// Title used when nothing matched; the UI translates it.
    static let unknownService = "Unknown service"
    /// Title used for a port that answers HTTP but matches no fingerprint.
    static let httpServer = "HTTP server"
    static let httpAPI = "HTTP API"
}
