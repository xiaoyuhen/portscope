import Foundation

/// Language resolution shared by the app and the self-test harness.
///
/// PortScope ships its own string tables rather than relying on the system
/// language alone, because the in-app switcher must be able to override it at
/// runtime without relaunching.
public enum LocalizationSupport {
    /// Languages PortScope ships, in fallback order.
    public static let supportedLanguages = ["en", "zh-Hans"]

    /// The language the app starts in for everyone.
    ///
    /// Deliberately not the system language: PortScope's vocabulary is
    /// developer vocabulary, and the English terms (dev server, bundler,
    /// listener, exposure) are the ones people search for. A Chinese macOS
    /// would otherwise land a user in a translated UI they never asked for.
    /// Simplified Chinese is one explicit choice away in Settings.
    public static let defaultLanguage = "en"

    /// Native name of a language, always written in that language.
    public static func displayName(for language: String) -> String {
        switch language {
        case "zh-Hans": return "简体中文"
        default: return "English"
        }
    }

    /// Resolves a stored preference to a language the app can actually show.
    /// Anything unset, unknown or stale falls back to English.
    public static func resolve(stored: String?) -> String {
        guard let stored, supportedLanguages.contains(stored) else { return defaultLanguage }
        return stored
    }

    /// Looks `key` up in `language`, then English, then returns the key itself.
    /// Echoing the key makes an untranslated string visible instead of blank.
    public static func string(_ key: String, language: String, bundle: Bundle) -> String {
        for candidate in [language, "en"] {
            if let path = bundle.path(forResource: candidate, ofType: "lproj"),
               let table = Bundle(path: path) {
                let value = table.localizedString(forKey: key, value: key, table: nil)
                if value != key { return value }
            }
        }
        return key
    }
}
