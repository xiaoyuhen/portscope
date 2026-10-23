import PortScopeKit
import SwiftUI

/// The window's content: top bar, then the selected page.
struct RootView: View {
    @EnvironmentObject private var locale: AppLocale
    @ObservedObject private var store: PortStore

    init(store: PortStore) {
        self.store = store
    }
    @StateObject private var page = LocalState(Page.ports)
    /// Ports are identified by number; 0 means "nothing selected".
    @StateObject private var selection = LocalState(0)

    var body: some View {
        main
    }

    private var main: some View {
        VStack(spacing: 0) {
            TopBar(page: page)
            Hairline()
            content
        }
        .background(Theme.canvas)
        .environmentObject(store)
        // The window title follows the language switch.
        .navigationTitle(locale.t("app.name"))
        // Toast anchored below the top bar: floating it over the bar itself
        // collided with the brand and the nav.
        .overlay(alignment: .top) {
            if let message = store.lastActionMessage {
                ActionBanner(message: message)
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 62)
                    .animation(.easeOut(duration: 0.18), value: message.id)
            }
        }
        // An in-window confirmation rather than a sheet: it keeps the list
        // visible behind it, and a modal overlay is the right weight for a
        // decision that is one click away from done.
        //
        // Note this overlay is applied *after* `.environmentObject(store)`.
        // Applied before it, the overlay's subtree would not receive the store
        // and the binding would silently never present.
        .overlay {
            if let action = store.pendingAction {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture { store.cancelPendingAction() }
                    ConfirmActionSheet(action: action)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Theme.strokeStrong, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
                        .transition(.scale(scale: 0.97).combined(with: .opacity))
                }
            }
        }
        .animation(.easeOut(duration: 0.14), value: store.pendingAction?.id)
        .onChange(of: store.ports.map(\.port)) { _, ports in
            // Keep the selection valid: a port can disappear between refreshes.
            if selection.value != 0, !ports.contains(selection.value) {
                selection.value = 0
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page.value {
        case .ports:
            portsPage
        case .overview:
            OverviewView(selection: selection, page: page)
        case .settings:
            SettingsView()
        }
    }

    private var portsPage: some View {
        HStack(alignment: .top, spacing: 12) {
            PortsView(selection: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let selected = selectedInfo {
                InspectorView(info: selected)
                    .frame(width: 330)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Resolved from the store every time, so the inspector shows live data
    /// (uptime, HTTP status) rather than a stale copy.
    private var selectedInfo: PortInfo? {
        guard selection.value != 0 else { return nil }
        return store.ports.first { $0.port == selection.value }
    }
}
