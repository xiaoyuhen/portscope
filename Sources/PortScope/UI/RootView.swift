import PortScopeKit
import SwiftUI

/// The window's content: top bar, then the selected page.
struct RootView: View {
    @EnvironmentObject private var locale: AppLocale
    @StateObject private var store = PortStore()
    @StateObject private var page = LocalState(Page.ports)
    /// Ports are identified by number; 0 means "nothing selected".
    @StateObject private var selection = LocalState(0)

    var body: some View {
        VStack(spacing: 0) {
            TopBar(page: page)
            Hairline()
            content
        }
        .background(Theme.canvas)
        .environmentObject(store)
        // The window title follows the language switch.
        .navigationTitle(locale.t("app.name"))
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
