import AppKit
import PortScopeKit
import SwiftUI

@main
struct PortScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var locale = AppLocale.shared
    /// The delegate owns the store; reading it through the adaptor keeps the
    /// window and the menu bar popover on the same object.
    private var store: PortStore { delegate.store }

    var body: some Scene {
        WindowGroup(LocalizationSupport.string("app.name", language: locale.language, bundle: .module)) {
            RootView(store: store)
                .environmentObject(locale)
                .environmentObject(store)
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
        if ActionCommand.handleIfNeeded() {
            exit(0)
        }
        return false
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shared with the menu bar controller. The app owns one store so the
    /// window and the popover never disagree about the machine.
    @MainActor let store = PortStore()
    private var menuBar: MenuBarController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = HeadlessMode.handleIfNeeded()
        // The window is fully custom; the standard title bar would only add a
        // strip of chrome above the app's own top bar.
        NSWindow.allowsAutomaticWindowTabbing = false
        // PortScope lives in the menu bar. `.accessory` is what makes the
        // status item render at all — a `.regular` app gets no status item in
        // this configuration — and it is the right policy anyway: no Dock icon
        // and no app switcher entry for a background monitor. The main window
        // is opened explicitly below.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(
            store: store,
            locale: AppLocale.shared,
            openWindow: { [weak self] in self?.showMainWindow() }
        )
        // With `.accessory`, SwiftUI does not bring the window up on its own,
        // so the first launch opens it once. Afterwards the app is a menu bar
        // citizen and the window appears only when asked for.
        showMainWindow()
    }

    /// Bring the main window forward, creating it again if the user closed it —
    /// the app keeps running in the menu bar, so "Open PortScope" must always
    /// have something to show.
    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Closing the window leaves PortScope in the menu bar rather than quitting:
    /// a port monitor is most useful when it is always there.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
