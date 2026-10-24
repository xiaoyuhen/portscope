import AppKit
import Combine
import PortScopeKit
import SwiftUI

/// The menu bar item and its popover.
///
/// `NSStatusItem` is used directly rather than SwiftUI's `MenuBarExtra`, which
/// does not register in this bundle configuration (no icon appears). The status
/// item is also the more capable API: it can show a live count, own a custom
/// popover, and keep working when the main window is closed.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    /// The panel is a borderless `NSPanel` rather than an `NSPopover`: popovers
    /// do not present in this bundle configuration (same runtime limitation as
    /// SwiftUI `.sheet`), while a panel window does.
    private var panel: NSPanel?
    /// Global mouse monitor and workspace observer used to dismiss the panel.
    private var dismissMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private let store: PortStore
    private let locale: AppLocale
    private let openWindow: () -> Void
    /// Holds the store subscriptions. Dropping it would silently stop the
    /// count from updating.
    private var cancellables: Set<AnyCancellable> = []

    init(store: PortStore, locale: AppLocale, openWindow: @escaping () -> Void) {
        self.store = store
        self.locale = locale
        self.openWindow = openWindow

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // The app's own mark, not an SF Symbol: the status item is the one
            // place the product is always visible, so it should carry the mark.
            // A template image lets macOS tint it for light and dark menu bars.
            button.image = MenuBarController.statusIcon()
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover(_:))
        }


        updateLabel()

        // Two subscriptions: one for the count, one for the language (the
        // tooltip is localized). A NotificationCenter observer with a nil name
        // does not fire for @Published changes, so Combine is the right tool.
        store.$ports
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateLabel() }
            .store(in: &cancellables)
        locale.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateLabel() }
            .store(in: &cancellables)
    }

    /// The menu bar mark, loaded from the bundle.
    ///
    /// Falls back to the SF Symbol the app used before if the resource is
    /// missing, so a stripped-down build still shows something recognisable
    /// rather than an empty menu bar slot.
    static func statusIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        let fallback = NSImage(
            systemSymbolName: "dot.radiowaves.left.and.right",
            accessibilityDescription: "PortScope"
        )
        fallback?.isTemplate = true
        return fallback
    }

    /// The count beside the icon. It is the whole point of a menu bar presence:
    /// you can see that something is listening without opening anything.
    private func updateLabel() {
        guard let button = statusItem.button else { return }
        let count = store.ports.count
        button.title = count > 0 ? " \(count)" : ""
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        button.toolTip = locale.t("menubar.tooltip", count)
    }

    @objc private func togglePopover(_ sender: Any?) {
        if let panel, panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        installDismissHandlers()
        let size = NSSize(width: MenuBarPanel.width, height: MenuBarPanel.height)
        let panel = self.panel ?? makePanel(size: size)
        self.panel = panel

        // Anchor under the status item, kept inside the screen's visible frame
        // so the panel never hangs off the right edge on a small display.
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = NSPoint(x: buttonFrame.midX - size.width / 2, y: buttonFrame.minY - size.height - 6)
        if let screen = buttonWindow.screen {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Dismisses the panel when the user clicks anywhere outside it.
    ///
    /// `didResignKey` alone is not enough: the panel is non-activating, so it
    /// never becomes key and that notification never fires — the panel stayed
    /// open until the status item was clicked again. A global mouse monitor
    /// catches clicks that land in other apps, and the workspace observer
    /// catches app switches (⌘-Tab, clicking the Dock).
    private func installDismissHandlers() {
        removeDismissHandlers()
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            // The monitor fires for clicks outside this app only; a click on
            // the status item is handled by its own action.
            self?.closePanel()
        }
        // `queue: .main` guarantees the main thread, but the compiler cannot
        // infer actor isolation from that, so it is asserted explicitly.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closePanel()
            }
        }
    }

    private func removeDismissHandlers() {
        if let dismissMonitor {
            NSEvent.removeMonitor(dismissMonitor)
            self.dismissMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        // `NSPanel` keeps its corners square even with a clear background, so
        // the window itself is made transparent and non-opaque, and the panel
        // view draws the rounded surface.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        let hosting = NSHostingController(
            rootView: MenuBarPanel(openWindow: { [weak self] in
                self?.closePanel()
                self?.openWindow()
            })
            .environmentObject(store)
            .environmentObject(locale)
        )
        // A transparent, non-opaque hosting view is what lets the rounded
        // corners actually show through; otherwise AppKit paints a square
        // window background behind them.
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hosting
        return panel
    }

    private func closePanel() {
        removeDismissHandlers()
        panel?.orderOut(nil)
    }
}

/// The popover's content: a compact version of the ports list.
struct MenuBarPanel: View {
    /// The panel's dimensions are computed from the row height so the list
    /// always ends on a whole row. A partially visible row at the bottom looked
    /// like a rendering bug and made the footer hard to read.
    static let rowHeight: CGFloat = 40
    static let rowDivider: CGFloat = 1
    static let headerHeight: CGFloat = 38
    static let footerHeight: CGFloat = 36
    static let visibleRows = 9
    static let width: CGFloat = 340
    static let listHeight: CGFloat = CGFloat(visibleRows) * (rowHeight + rowDivider)
    static let height: CGFloat = headerHeight + rowDivider + listHeight + rowDivider + footerHeight

    let openWindow: () -> Void
    @EnvironmentObject private var locale: AppLocale
    @EnvironmentObject private var store: PortStore

    var body: some View {
        // Fixed height on each band, with the list taking the remainder: a
        // ScrollView with `maxHeight: .infinity` alone let its content paint
        // over the footer.
        VStack(spacing: 0) {
            header
            Hairline()
            list
                .frame(height: 460 - 38 - 36 - 2)
            Hairline()
            footer
        }
        .frame(width: Self.width, height: Self.height)
        .background(Theme.surface)
        // The panel window itself is borderless and clear; the rounded shape
        // and its border are drawn here so the corners match the app.
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.strokeStrong, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(locale.t("app.name"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(spacing: 4) {
                StatusDot(color: store.isScanning ? Theme.warning : Theme.live, size: 5)
                Text("\(store.totalCount)")
                    .font(Theme.monoMicro)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    private var list: some View {
        // An explicit height, not `maxHeight: .infinity`: inside a fixed-size
        // panel that modifier let the scroll content paint over the footer.
        ScrollView {
            LazyVStack(spacing: 0) {
                // Same rows as the main window, from the same model: desktop
                // apps and system services stay folded here too, behind the
                // same disclosure. The popover used to filter on its own and
                // listed WeChat and ControlCenter inline.
                ForEach(store.rows) { row in
                    switch row {
                    case .port(let info, let muted):
                        MenuBarRow(info: info, isMuted: muted)
                    case .backgroundDisclosure(let count):
                        MenuBarDisclosure(count: count)
                    }
                    Hairline(inset: 12)
                }
            }
            .padding(.bottom, 4)
        }
        .frame(height: Self.listHeight)
        .clipped()
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(locale.t("menubar.openApp")) { openWindow() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)
            Spacer()
            Button(locale.t("menubar.quit")) { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Theme.surface)
    }
}

/// One row in the popover. Deliberately shorter than the main list: a popover
/// is for a glance, not for investigation.
struct MenuBarRow: View {
    let info: PortInfo
    /// Background rows are drawn at reduced contrast, as in the main window.
    var isMuted: Bool = false
    @EnvironmentObject private var locale: AppLocale
    @EnvironmentObject private var store: PortStore
    @StateObject private var hovering = LocalFlag()

    private var tint: Color { Theme.tint(for: info.service?.kind ?? .other) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: Presentation.symbol(for: info.service?.kind))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(
                    tint.opacity(isMuted ? 0.07 : 0.12),
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .opacity(isMuted ? 0.75 : 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(info.service?.title ?? info.processName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isMuted ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                Text(info.service?.projectName ?? info.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if info.exposure.isPubliclyReachable {
                StatusDot(color: Theme.warning, size: 5)
            }

            Text(":\(info.port)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)

            if hovering.value {
                IconButton(systemName: "arrow.clockwise", help: locale.t("ports.restart")) {
                    store.requestRestart(info)
                }
                IconButton(
                    systemName: "stop.circle",
                    help: locale.t("ports.stop"),
                    tint: Theme.danger.opacity(0.85)
                ) {
                    store.requestStop(info)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: MenuBarPanel.rowHeight)
        .background(hovering.value ? Theme.rowHover : .clear)
        .onHover { hovering.value = $0 }
        .onTapGesture {
            if let url = info.localURL { NSWorkspace.shared.open(url) }
        }
    }
}

/// The folded-background row in the popover.
///
/// Same job as the window's disclosure: say how many ports are put away and
/// open them on click. It is a row height rather than the window's 32 pt so the
/// panel's fixed height stays a whole number of rows.
struct MenuBarDisclosure: View {
    let count: Int
    @EnvironmentObject private var locale: AppLocale
    @EnvironmentObject private var store: PortStore
    @StateObject private var hovering = LocalFlag()

    var body: some View {
        Button {
            store.showBackgroundServices = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                Text(locale.t("ports.backgroundHidden", count))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(locale.t("ports.backgroundHint"))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: MenuBarPanel.rowHeight)
            .contentShape(Rectangle())
            .background(hovering.value ? Theme.rowHover : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering.value = $0 }
    }
}

/// A borderless panel that can take key focus without activating the app.
///
/// `NSPanel` with `.nonactivatingPanel` refuses key status by default, which
/// left the search-free panel unable to dismiss itself and made clicks inside
/// it feel unresponsive. Accepting key focus is what a menu bar popover does.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
