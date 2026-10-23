import Foundation

/// Language resolution shared by the app and the self-test harness.
///
/// PortScope ships its own string tables rather than relying on the system
/// language alone, because the in-app switcher must be able to override it at
/// runtime without relaunching.
public enum LocalizationSupport {
    /// Languages PortScope ships, in fallback order.
    public static let supportedLanguages = ["en", "zh-Hans"]

    /// Native name of a language, always written in that language.
    public static func displayName(for language: String) -> String {
        switch language {
        case "zh-Hans": return "简体中文"
        default: return "English"
        }
    }

    /// First supported language matching the user's system preference.
    public static func preferredLanguage() -> String {
        for preferred in Locale.preferredLanguages {
            for supported in supportedLanguages
            where preferred == supported || preferred.hasPrefix(supported + "-") {
                return supported
            }
        }
        return "en"
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
