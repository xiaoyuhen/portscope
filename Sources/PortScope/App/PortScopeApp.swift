import AppKit
import PortScopeKit
import SwiftUI

@main
struct PortScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var locale = AppLocale.shared

    var body: some Scene {
        WindowGroup(LocalizationSupport.string("app.name", language: locale.language, bundle: .module)) {
            PlaceholderView()
                .environmentObject(locale)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Headless entry points are handled before SwiftUI installs its app loop, so
/// `PortScope --selftest` works from a terminal with no window server.
enum HeadlessMode {
    static func handleIfNeeded() -> Bool {
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.main())
        }
        if ListCommand.handleIfNeeded() {
            exit(0)
        }
        return false
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = HeadlessMode.handleIfNeeded()
    }
}

/// Temporary shell for M0. Replaced by the real dashboard in M3.
private struct PlaceholderView: View {
    @EnvironmentObject private var locale: AppLocale

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 42, weight: .light))
            Text(locale.t("app.name"))
                .font(.system(size: 22, weight: .semibold))
            Text(locale.t("placeholder.subtitle"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }
}
