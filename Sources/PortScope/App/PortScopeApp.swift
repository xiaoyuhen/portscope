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
    private var mainWindow: MainWindowController?

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
        let window = MainWindowController(store: store, locale: AppLocale.shared)
        mainWindow = window
        menuBar = MenuBarController(
            store: store,
            locale: AppLocale.shared,
            openWindow: { window.show() }
        )
        // With `.accessory`, SwiftUI does not bring the window up on its own,
        // so the first launch opens it once. Afterwards the app is a menu bar
        // citizen and the window appears only when asked for.
        window.show()
    }

    /// Clicking the Dock icon is the other way back to the window, and with an
    /// accessory app it is the only standard gesture left.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        mainWindow?.show()
        return false
    }

    /// Closing the window leaves PortScope in the menu bar rather than quitting:
    /// a port monitor is most useful when it is always there.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// Owns the one main window and keeps it reopenable.
///
/// SwiftUI's `WindowGroup` window is destroyed when it is closed, which left
/// "Open PortScope" with nothing to bring forward — the button did nothing at
/// all. Closing is therefore intercepted and turned into hiding, so the window
/// survives and can be shown again. If it is ever gone anyway (SwiftUI rebuilt
/// the scene, the window was released), a fresh one is built from the same
/// root view, so the menu bar item always has something to open.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let store: PortStore
    private let locale: AppLocale
    private var window: NSWindow?

    init(store: PortStore, locale: AppLocale) {
        self.store = store
        self.locale = locale
        super.init()
    }

    func show() {
        let window = self.window ?? adoptSwiftUIWindow() ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The window SwiftUI created for its `WindowGroup`.
    ///
    /// It is kept rather than rebuilt because it already carries the scene's
    /// size, position and styling. The strong reference held here also keeps it
    /// alive: `windowShouldClose` below declines the close, so it is never
    /// destroyed and this reference can never dangle.
    private func adoptSwiftUIWindow() -> NSWindow? {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return nil }
        window.delegate = self
        return window
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = locale.t("app.name")
        window.minSize = NSSize(width: 860, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: RootView(store: store)
                .environmentObject(locale)
                .environmentObject(store)
        )
        window.center()
        return window
    }

    /// Hide instead of destroy, so the window can be shown again.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
