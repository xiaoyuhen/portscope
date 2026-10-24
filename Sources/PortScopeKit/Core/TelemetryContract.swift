import Foundation

/// The privacy contract for the anonymous launch count, in one place.
///
/// The app builds its payload from `allowedFields`, and the receiver
/// (`infra/telemetry/worker.js`) drops anything not on its own copy of the
/// same list. Both sides being able to state the contract is what makes it
/// checkable: `SelfTest` asserts that no field outside this set can be added
/// without a failing check, so the documentation and the code cannot drift.
public enum TelemetryContract {
    /// Every field the app may send. Nothing else, ever.
    public static let allowedFields: Set<String> = [
        "event", "app", "version", "os", "arch", "id",
    ]

    /// Field names that would mean local data is leaving the machine. Used by
    /// the self-test, not by the app.
    public static let forbiddenFields: Set<String> = [
        "port", "ports", "pid", "process", "processName", "path", "cwd",
        "command", "arguments", "args", "host", "hostname", "user", "username",
        "service", "project", "title", "exposure", "address", "addresses",
    ]

    /// True when `payload` contains only allowed keys. The app does not need
    /// this at runtime — it constructs the payload from literals — but a test
    /// (or a reviewer) can run it against a real payload.
    public static func isCompliant(_ payload: [String: String]) -> Bool {
        payload.keys.allSatisfy { allowedFields.contains($0) }
    }
}
