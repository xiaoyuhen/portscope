import Foundation

/// What a fingerprint says a service is.
///
/// Kept separate from `ServiceInfo` because a fingerprint is a *rule* — static
/// knowledge — while `ServiceInfo` is the result of applying rules to one
/// process. Splitting them keeps the knowledge base readable and testable.
public struct ServiceMatch: Sendable, Hashable {
    public var kind: ServiceInfo.Kind
    public var title: String
    public var summaryKey: String
    public var confidence: Double

    public init(kind: ServiceInfo.Kind, title: String, summaryKey: String, confidence: Double) {
        self.kind = kind
        self.title = title
        self.summaryKey = summaryKey
        self.confidence = confidence
    }
}

/// A rule that recognises a service from process metadata.
public struct ProcessFingerprint: Sendable {
    public enum Pattern: Sendable {
        /// Matches the basename of the executable, case-insensitively.
        case executable(String)
        /// Matches when any argument's basename equals this, e.g. "manage.py".
        case argumentBasename(String)
        /// Matches when an argument's path ends with this suffix. Node's own
        /// argv holds the *resolved* script path, so `node_modules/.bin/vite`
        /// arrives as `.../node_modules/vite/bin/vite.js`; matching on the
        /// tail is what recognises it.
        case argumentPathSuffix(String)
        /// Matches when any argument contains this substring.
        case argumentContains(String)
        /// Matches when the working directory contains this path component.
        case workingDirectoryContains(String)
        /// Matches when the executable path contains this substring.
        case pathContains(String)
    }

    public var patterns: [Pattern]
    public var match: ServiceMatch
    /// Whether every pattern must match or any one of them is enough.
    ///
    /// Most fingerprints list the several ways one service shows up in argv
    /// (`postgres` or `postmaster`, `next` or `next dev`) and want `any`.
    /// `all` is for narrowing a common binary down to a specific tool.
    public var requireAll: Bool

    /// Any listed pattern is enough — the common case.
    public init(any patterns: [Pattern], _ match: ServiceMatch) {
        self.patterns = patterns
        self.match = match
        self.requireAll = false
    }

    /// Every listed pattern must match.
    public init(all patterns: [Pattern], _ match: ServiceMatch) {
        self.patterns = patterns
        self.match = match
        self.requireAll = true
    }

    public func matches(_ details: ProcessDetails) -> Bool {
        if requireAll {
            return patterns.allSatisfy { matches($0, details) }
        }
        return patterns.contains { matches($0, details) }
    }

    private func matches(_ pattern: Pattern, _ details: ProcessDetails) -> Bool {
        switch pattern {
            case .executable(let name):
                // Match either the kernel's process name or the executable's
                // basename: Electron apps report a helper binary path but a
                // friendly process name ("Discord" vs "Discord Helper").
                let candidates = [details.name, Self.basename(details.executablePath ?? "")]
                return candidates.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            case .argumentBasename(let name):
                return details.arguments.contains {
                    Self.basename($0).caseInsensitiveCompare(name) == .orderedSame
                }
            case .argumentPathSuffix(let suffix):
                return details.arguments.contains {
                    $0.hasSuffix(suffix) || $0.hasSuffix("/" + suffix)
                }
            case .argumentContains(let text):
                return details.arguments.contains { $0.localizedCaseInsensitiveContains(text) }
            case .workingDirectoryContains(let text):
                guard let cwd = details.workingDirectory else { return false }
                return cwd.localizedCaseInsensitiveContains(text)
        case .pathContains(let text):
            guard let path = details.executablePath else { return false }
            return path.localizedCaseInsensitiveContains(text)
        }
    }

    static func basename(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

/// A rule that recognises a service from its HTTP response headers.
public struct HTTPFingerprint: Sendable {
    /// Header name, lowercased, e.g. "server".
    public var header: String
    /// Substring the header value must contain, case-insensitive. Nil matches
    /// any value (useful when the header's mere presence is the signal).
    public var contains: String?
    public var match: ServiceMatch

    public func matches(_ headers: [String: String]) -> Bool {
        guard let value = headers[header.lowercased()] else { return false }
        guard let contains else { return true }
        return value.localizedCaseInsensitiveContains(contains)
    }
}

/// A rule that recognises a service from a well-known port number.
///
/// Port-based guesses are the weakest kind of evidence and are only consulted
/// when nothing better matched, so a Vite server on 3000 is not called
/// "Ruby on Rails" just because 3000 is Rails' default.
public struct PortFingerprint: Sendable {
    public var port: Int
    public var match: ServiceMatch
}
