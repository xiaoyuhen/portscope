import Foundation

/// How a listening socket is bound. This decides who can reach it, which is the
/// single most useful security signal on the list.
public enum Exposure: String, Codable, Sendable, CaseIterable {
    /// Bound to 127.0.0.1 / ::1 — only this machine can connect.
    case loopback
    /// Bound to a specific LAN or bridge address (e.g. 192.168.1.7, docker0).
    case interface
    /// Bound to 0.0.0.0 / :: — reachable from the network.
    case allInterfaces

    public var isPubliclyReachable: Bool { self == .allInterfaces || self == .interface }
}

/// One TCP port in LISTEN state, joined with everything we know about the
/// process behind it.
public struct PortInfo: Identifiable, Codable, Sendable, Hashable {
    public var port: Int
    /// Addresses the port is bound to, already de-duplicated and sorted.
    public var addresses: [String]
    public var exposure: Exposure

    public var pid: pid_t
    public var processName: String
    public var executablePath: String?
    /// Full command line, split into arguments. Empty when not inspectable.
    public var arguments: [String]
    public var workingDirectory: String?
    /// Seconds since the process started.
    public var uptime: TimeInterval?
    /// Name of the app bundle the process belongs to, e.g. "Docker Desktop".
    public var appBundleName: String?

    /// Classification produced by `ServiceIdentifier` (M2). Nil until resolved.
    /// The container that publishes this port, when the port belongs to a
    /// Docker engine. Stop and restart then act on the container, never on
    /// the engine process that forwards the port.
    public var container: ContainerInfo? = nil

    public var service: ServiceInfo?

    public var id: Int { port }

    /// Human-friendly label: the app bundle name when there is one, otherwise
    /// the process name.
    public var displayName: String { appBundleName ?? processName }

    /// The address a person would actually type in a browser.
    public var localURL: URL? {
        guard let host = addresses.first(where: { $0 != "0.0.0.0" && $0 != "::" }) ?? addresses.first else {
            return nil
        }
        let clean = host.replacingOccurrences(of: "::1", with: "localhost")
        let encoded = clean.contains(":") && clean != "localhost" ? "[\(clean)]" : clean
        return URL(string: "http://\(encoded):\(port)")
    }

    public var commandLine: String {
        arguments.isEmpty ? executablePath ?? processName : arguments.joined(separator: " ")
    }
}

/// Everything PortScope can infer about what a service *does*. Filled in by
/// `ServiceIdentifier`; every field is optional because inference is best-effort.
public struct ServiceInfo: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case web, api, database, cache, devServer, bundler, container, ai, messaging, system, other
    }

    public var kind: Kind
    /// Short product label, e.g. "Express", "Redis", "Vite". A proper noun, so
    /// it is not translated.
    public var title: String
    /// Localization key for the one-sentence explanation of what this is.
    /// Sentences are assembled in the UI layer so they read naturally in both
    /// languages; storing English prose here would leak it into the Chinese UI.
    public var summaryKey: String

    /// How sure we are about `title`. Taken from the strongest match, with a
    /// small boost when an independent tier agrees — but never presented as
    /// certainty, because every signal here is inference.
    public var confidence: Double
    /// Where the judgement came from, so the UI can show confidence honestly.
    public var evidence: [Evidence]
    /// HTTP status we got when probing, if we probed.
    public var httpStatus: Int?
    public var serverHeader: String?
    /// The project directory this service belongs to, when we can tell.
    public var projectPath: String?
    public var projectName: String?
}

public struct Evidence: Codable, Sendable, Hashable {
    /// Localization key for the kind of evidence, e.g. "evidence.serverHeader".
    public var sourceKey: String
    /// The raw observed value, shown verbatim: a header value, a path, a name.
    public var detail: String
    public var weight: Double
}

/// A snapshot of the whole machine at one moment.
public struct PortSnapshot: Sendable {
    public var ports: [PortInfo]
    public var capturedAt: Date
    /// Ports that appeared since the previous snapshot.
    public var newPorts: Set<Int>
    /// Ports that disappeared since the previous snapshot.
    public var closedPorts: Set<Int>
}
