import Foundation

/// Carries preferences over from the bundle identifier PortScope used to have.
///
/// Releases up to 0.2.2 were `com.portscope.app`, a reverse-DNS name for a
/// domain this project does not own. The identifier is now
/// `io.github.xiaoyuhen.portscope`, and preferences live under the bundle
/// identifier, so without this an update would reset the language, the
/// refresh interval, the hidden ports and the telemetry choice — and the new
/// install ID would count every existing user a second time.
///
/// Copy, not move: the old domain is left as it was, so going back to an old
/// build still finds its settings.
enum LegacyPreferences {
    static let legacyDomain = "com.portscope.app"
    static let currentIdentifier = "io.github.xiaoyuhen.portscope"
    private static let migratedKey = "PortScope.migratedFromLegacyDomain"

    /// Runs at most once per process, and only in the real app: the UI
    /// harness gives its scratch copy an identifier of its own, and must not
    /// inherit the developer's settings.
    static func migrateIfNeeded() { _ = once }

    private static let once: Void = {
        guard Bundle.main.bundleIdentifier == currentIdentifier else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        defer { defaults.set(true, forKey: migratedKey) }

        guard let legacy = UserDefaults.standard.persistentDomain(forName: legacyDomain) else { return }
        for (key, value) in legacy where key.hasPrefix("PortScope.") {
            // A value already written under the new identifier wins.
            if defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
    }()
}
