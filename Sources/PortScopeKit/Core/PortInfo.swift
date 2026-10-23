import Foundation

/// How a listening socket is bound. This decides who can reach it, which is the
/// single most useful security signal on the list.
enum Exposure: String, Codable, Sendable, CaseIterable {
    /// Bound to 127.0.0.1 / ::1 — only this machine can connect.
    case loopback
    /// Bound to a specific LAN or bridge address (e.g. 192.168.1.7, docker0).
    case interface
    /// Bound to 0.0.0.0 / :: — reachable from the network.
    case allInterfaces

    var isPubliclyReachable: Bool { self == .allInterfaces || self == .interface }
}

/// One TCP port in LISTEN state, joined with everything we know about the
/// process behind it.
struct PortInfo: Identifiable, Codable, Sendable, Hashable {
    var port: Int
    /// Addresses the port is bound to, already de-duplicated and sorted.
    var addresses: [String]
    var exposure: Exposure

    var pid: pid_t
    var processName: String
    var executablePath: String?
    /// Full command line, split into arguments. Empty when not inspectable.
    var arguments: [String]
    var workingDirectory: String?
    /// Seconds since the process started.
    var uptime: TimeInterval?
    /// Name of the app bundle the process belongs to, e.g. "Docker Desktop".
    var appBundleName: String?

    /// Classification produced by `ServiceIdentifier` (M2). Nil until resolved.
    var service: ServiceInfo?

    var id: Int { port }

    /// Human-friendly label: the app bundle name when there is one, otherwise
    /// the process name.
    var displayName: String { appBundleName ?? processName }

    /// The address a person would actually type in a browser.
    var localURL: URL? {
        guard let host = addresses.first(where: { $0 != "0.0.0.0" && $0 != "::" }) ?? addresses.first else {
            return nil
        }
        let clean = host.replacingOccurrences(of: "::1", with: "localhost")
        let encoded = clean.contains(":") && clean != "localhost" ? "[\(clean)]" : clean
        return URL(string: "http://\(encoded):\(port)")
    }

    var commandLine: String {
        arguments.isEmpty ? executablePath ?? processName : arguments.joined(separator: " ")
    }
}

/// Everything PortScope can infer about what a service *does*. Filled in by
/// `ServiceIdentifier`; every field is optional because inference is best-effort.
struct ServiceInfo: Codable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case web, api, database, cache, devServer, bundler, container, ai, messaging, system, other
    }

    var kind: Kind
    /// Short label, e.g. "Express API", "Redis", "Vite dev server".
    var title: String
    /// One sentence a person can act on: what this thing is for.
    var summary: String
    /// Where the judgement came from, so the UI can show confidence honestly.
    var evidence: [Evidence]
    /// HTTP status we got when probing, if we probed.
    var httpStatus: Int?
    var serverHeader: String?
    /// The project directory this service belongs to, when we can tell.
    var projectPath: String?
    var projectName: String?

    var confidence: Double {
        let weights = evidence.map(\.weight)
        return min(1.0, weights.reduce(0, +))
    }
}

struct Evidence: Codable, Sendable, Hashable {
    var source: String
    var detail: String
    var weight: Double
}

/// A snapshot of the whole machine at one moment.
struct PortSnapshot: Sendable {
    var ports: [PortInfo]
    var capturedAt: Date
    /// Ports that appeared since the previous snapshot.
    var newPorts: Set<Int>
    /// Ports that disappeared since the previous snapshot.
    var closedPorts: Set<Int>
}
