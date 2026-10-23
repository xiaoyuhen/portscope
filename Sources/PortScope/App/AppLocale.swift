import Combine
import Foundation
import PortScopeKit

/// Runtime language switch. Reads the user's system preference the first time,
/// then remembers an explicit choice in UserDefaults.
///
/// This is an `ObservableObject` rather than an `@Observable` class on purpose:
/// Apple's Command Line Tools ship SwiftUI without the `SwiftUIMacros` plugin,
/// so `@State` is unavailable and `@StateObject` is the only way to own an
/// observable object from a view. See README › Toolchain notes.
@MainActor
final class AppLocale: ObservableObject {
    static let shared = AppLocale()

    private static let defaultsKey = "PortScope.language"

    @Published var language: String {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language, forKey: Self.defaultsKey)
        }
    }

    var isChinese: Bool { language == "zh-Hans" }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        let valid = stored.map { LocalizationSupport.supportedLanguages.contains($0) } ?? false
        language = valid ? stored! : LocalizationSupport.preferredLanguage()
    }

    /// Translate a key in the current language.
    func t(_ key: String, _ arguments: CVarArg...) -> String {
        let format = LocalizationSupport.string(key, language: language, bundle: .module)
        return arguments.isEmpty ? format : String(format: format, arguments: arguments)
    }
}
