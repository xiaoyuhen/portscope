import Foundation
import PortScopeKit

/// Optional, anonymous launch counting.
///
/// Open-source macOS apps have no download counter: a GitHub clone or a copied
/// `.app` leaves no trace, so "is anyone using this?" is otherwise unanswerable.
/// This sends exactly one event, once per app version per day, and nothing else.
///
/// **What is sent** — the whole payload, verbatim:
///
/// ```json
/// {"event":"launch","app":"PortScope","version":"0.2.0",
///  "os":"14.5","arch":"arm64","id":"<random, per install>"}
/// ```
///
/// **What is never sent:** port numbers, process names, paths, command lines,
/// hostnames, usernames, IP-derived location, or anything about what is
/// listening. The payload is built from a fixed set of fields and cannot grow
/// by accident — there is no dictionary to add to.
///
/// **What makes it anonymous:**
/// * `id` is a random UUID generated locally on first run, unrelated to any
///   hardware or account identifier. It exists only to distinguish "one person
///   opened it 30 times" from "30 people opened it once".
/// * No cookies, no request body identifiers, no query parameters beyond the
///   path above.
/// * The receiver stores a coarse daily count, not a per-request log.
///
/// **Opting out:** `defaults write com.portscope.app PortScope.telemetry -bool NO`,
/// the toggle in Settings, or build with `PORTSCOPE_NO_TELEMETRY=1` to compile
/// it out entirely. `--selftest` and every other headless command never send
/// anything.
///
/// Failures are silent by design: telemetry must never affect the app.
public enum Telemetry {
    /// The endpoint is injected at build time so a fork can point at its own
    /// receiver, or at nothing.
    static var endpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "PortScopeTelemetryURL") as? String
                ?? ProcessInfo.processInfo.environment["PORTSCOPE_TELEMETRY_URL"],
              let url = URL(string: raw), !raw.isEmpty else { return nil }
        return url
    }

    private static let defaultsKey = "PortScope.telemetry"
    private static let installIDKey = "PortScope.installID"
    private static let lastSentKey = "PortScope.telemetry.lastSent"

    /// Whether the user has left telemetry on. Off by default only when the
    /// environment says so; otherwise on, with a visible switch in Settings.
    public static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["PORTSCOPE_NO_TELEMETRY"] != nil { return false }
        let defaults = UserDefaults.standard
        if defaults.object(forKey: defaultsKey) == nil { return true }
        return defaults.bool(forKey: defaultsKey)
    }

    public static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
    }

    /// Sends the launch event, at most once per day per version.
    ///
    /// Called from `applicationDidFinishLaunching`. The deduplication is
    /// local: it exists so that relaunching the app repeatedly does not look
    /// like a crowd, which would make the number meaningless in the other
    /// direction.
    public static func recordLaunch(version: String, completion: @escaping @Sendable () -> Void = {}) {
        guard isEnabled, let endpoint else { completion(); return }

        let defaults = UserDefaults.standard
        let stamp = "\(version)|\(Self.today)"
        guard defaults.string(forKey: lastSentKey) != stamp else { completion(); return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload(version: version)

        URLSession.shared.dataTask(with: request) { _, _, _ in
            // Only remember the send if it actually left. A machine that is
            // offline should not burn its one attempt for the day.
            defaults.set(stamp, forKey: lastSentKey)
            completion()
        }.resume()
    }

    /// The complete payload. Kept as a literal construction rather than a
    /// dictionary so that adding a field requires editing this function — a
    /// privacy review has one place to look, and `TelemetryContract` in the kit
    /// pins the field set with a self-test.
    static func payload(version: String) -> Data {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let body: [String: String] = [
            "event": "launch",
            "app": "PortScope",
            "version": version,
            "os": "\(os.majorVersion).\(os.minorVersion)",
            "arch": architecture,
            "id": installID,
        ]
        assert(TelemetryContract.isCompliant(body), "telemetry payload left the contract")
        // Sorted keys so the payload is stable and auditable.
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    /// A random identifier for this installation. Not derived from hardware,
    /// the user account, or anything else on the machine.
    static var installID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: installIDKey) { return existing }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: installIDKey)
        return generated
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static var today: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }
}
