import AppKit
import PortScopeKit
import SwiftUI

@main
struct PortScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var locale = AppLocale.shared

    var body: some Scene {
        WindowGroup(LocalizationSupport.string("app.name", language: locale.language, bundle: .module)) {
            RootView()
                .environmentObject(locale)
                .frame(minWidth: 860, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 720)
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
        // The window is fully custom; the standard title bar would only add a
        // strip of chrome above the app's own top bar.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
