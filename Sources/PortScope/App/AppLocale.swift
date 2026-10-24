import Combine
import Foundation
import PortScopeKit

/// Runtime language switch. Starts in English for everyone and only changes
/// when the user picks a language in Settings.
///
/// This is an `ObservableObject` rather than an `@Observable` class on purpose:
/// Apple's Command Line Tools ship SwiftUI without the `SwiftUIMacros` plugin,
/// so `@State` is unavailable and `@StateObject` is the only way to own an
/// observable object from a view. See README › Toolchain notes.
@MainActor
final class AppLocale: ObservableObject {
    static let shared = AppLocale()

    private static let defaultsKey = "PortScope.language"
    /// Where the choice is remembered. Injectable so a check can use a scratch
    /// suite instead of the real user's preferences.
    private let defaults: UserDefaults

    @Published var language: String {
        didSet {
            guard language != oldValue else { return }
            defaults.set(language, forKey: Self.defaultsKey)
        }
    }

    var isChinese: Bool { language == "zh-Hans" }

    init(defaults: UserDefaults = .standard) {
        LegacyPreferences.migrateIfNeeded()
        self.defaults = defaults
        // Not the system language: the default is English even on a Chinese
        // macOS, and Simplified Chinese is applied only when it was chosen
        // here. See `LocalizationSupport.defaultLanguage` for why.
        language = LocalizationSupport.resolve(stored: defaults.string(forKey: Self.defaultsKey))
    }

    /// Translate a key in the current language.
    func t(_ key: String, _ arguments: CVarArg...) -> String {
        let format = LocalizationSupport.string(key, language: language, bundle: .module)
        return arguments.isEmpty ? format : String(format: format, arguments: arguments)
    }
}
