import PortScopeKit
import SwiftUI

/// The window's top bar: brand, centered navigation, and trailing controls.
///
/// Matches the reference layout — the nav is centred in the window rather than
/// left-aligned after the logo, which keeps it in the same place as pages
/// change.
struct TopBar: View {
    @EnvironmentObject private var locale: AppLocale
    @EnvironmentObject private var store: PortStore
    @ObservedObject var page: LocalState<Page>

    var body: some View {
        HStack(spacing: 0) {
            brand
                .frame(maxWidth: .infinity, alignment: .leading)

            PageTabs(selection: page)
                .fixedSize()

            trailing
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Theme.gutter)
        .frame(height: 52)
        .background(Theme.canvas)
    }

    private var brand: some View {
        HStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(locale.t("app.name"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var trailing: some View {
        HStack(spacing: 4) {
            // Live indicator: a green dot and the last refresh time. It reads
            // as "the list is current" without a spinner.
            HStack(spacing: 5) {
                StatusDot(color: store.isScanning ? Theme.warning : Theme.live, size: 5)
                Text(store.isScanning ? locale.t("topbar.scanning") : locale.t("topbar.live"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.trailing, 8)

            IconButton(
                systemName: "arrow.clockwise",
                help: locale.t("topbar.refresh"),
                action: { store.refresh() }
            )
            IconButton(
                systemName: "gearshape",
                help: locale.t("topbar.settings"),
                action: { page.value = .settings }
            )
        }
    }
}

/// The pages of the app. Ordering follows the reference: the thing you look at
/// most is first and selected by default.
enum Page: String, CaseIterable, Identifiable {
    case ports, overview, settings
    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .ports: return "page.ports"
        case .overview: return "page.overview"
        case .settings: return "page.settings"
        }
    }
}

/// Centred pill navigation. The selected pill is a raised capsule; unselected
/// items are plain text — the same treatment as the reference.
struct PageTabs: View {
    @ObservedObject var selection: LocalState<Page>
    @EnvironmentObject private var locale: AppLocale

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Page.allCases) { page in
                Button { selection.value = page } label: {
                    Text(locale.t(page.titleKey))
                        .font(.system(size: 12, weight: selection.value == page ? .medium : .regular))
                        .foregroundStyle(selection.value == page ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background {
                            if selection.value == page {
                                Capsule().fill(Theme.surfaceInset)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.surface.opacity(0.6)))
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }
}
