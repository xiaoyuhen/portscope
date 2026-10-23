import PortScopeKit
import SwiftUI

/// The list of listening ports.
///
/// One large container with hairline-separated rows, following the reference.
/// Rows are selectable, and selecting one opens the inspector beside the list
/// rather than replacing it — the list stays readable while you investigate.
struct PortsView: View {
    @EnvironmentObject private var locale: AppLocale
    @EnvironmentObject private var store: PortStore
    @ObservedObject var selection: LocalState<Int>

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            if store.visiblePorts.isEmpty {
                emptyState
            } else {
                rowList
            }
            footer
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            FilterPicker()
            Spacer(minLength: 12)
            InsetSearchField(
                placeholder: locale.t("ports.search"),
                text: Binding(
                    get: { store.searchText },
                    set: { store.searchText = $0 }
                )
            )
            .frame(width: 230)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    // MARK: - Rows

    private var rowList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.visiblePorts) { info in
                    PortRow(
                        info: info,
                        isSelected: selection.value == info.port,
                        isNew: store.recentlyAppeared.contains(info.port)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selection.value = info.port }
                    .contextMenu {
                        rowMenu(for: info)
                    }
                    Hairline(inset: 14)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func rowMenu(for info: PortInfo) -> some View {
        if let url = info.localURL {
            Button(locale.t("ports.openInBrowser")) { NSWorkspace.shared.open(url) }
        }
        Button(locale.t("ports.copyAddress")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Presentation.hostAndPort(info), forType: .string)
        }
        Divider()
        Button(locale.t("ports.restart")) { store.requestRestart(info) }
        Button(locale.t("ports.stop"), role: .destructive) { store.requestStop(info) }
        Divider()
        Button(locale.t("ports.hide")) { store.hide(port: info.port) }
        Button(locale.t("ports.revealInFinder")) {
            if let cwd = info.workingDirectory {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd)
            }
        }
        .disabled(info.workingDirectory == nil)
    }

    // MARK: - Empty and footer

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(store.searchText.isEmpty ? locale.t("ports.empty") : locale.t("ports.noMatches"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            if !store.searchText.isEmpty {
                Button(locale.t("ports.clearSearch")) { store.searchText = "" }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(locale.t("ports.footer", store.visiblePorts.count, store.totalCount))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            if store.hiddenCount > 0 {
                Button(locale.t("ports.showHidden", store.hiddenCount)) {
                    store.unhideAll()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
            }
            Spacer()
            if let last = store.lastScan {
                Text(locale.t("ports.updated", last.formatted(date: .omitted, time: .standard)))
                    .font(Theme.monoMicro)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(Theme.surface)
    }
}

/// Segmented filter control with counts, styled like the reference's period
/// selector rather than the system segmented control.
struct FilterPicker: View {
    @EnvironmentObject private var locale: AppLocale
    @EnvironmentObject private var store: PortStore

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PortStore.Filter.allCases) { filter in
                let count = store.count(for: filter)
                Button { store.filter = filter } label: {
                    HStack(spacing: 4) {
                        Text(locale.t("filter.\(filter.rawValue)"))
                            .font(.system(size: 11, weight: store.filter == filter ? .medium : .regular))
                        if count > 0 {
                            Text("\(count)")
                                .font(Theme.monoMicro)
                                .opacity(0.65)
                        }
                    }
                    .foregroundStyle(store.filter == filter ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background {
                        // The selected filter needs a clear edge, not just a
                        // slightly lighter fill: on a near-black canvas a fill
                        // alone is nearly invisible.
                        if store.filter == filter {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Theme.rowSelected)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(Theme.strokeStrong, lineWidth: 1)
                                )
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.surfaceInset.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

/// One port. Layout mirrors the reference's agent rows: icon, name + subtitle,
/// then right-aligned metadata columns and an action.
struct PortRow: View {
    let info: PortInfo
    let isSelected: Bool
    let isNew: Bool

    @EnvironmentObject private var locale: AppLocale
    @EnvironmentObject private var store: PortStore
    @StateObject private var hovering = LocalFlag()

    private var tint: Color { Theme.tint(for: info.service?.kind ?? .other) }

    var body: some View {
        HStack(spacing: 12) {
            glyph

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(info.service?.title ?? info.processName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    if isNew {
                        Pill(text: locale.t("ports.new"), color: Theme.accent, filled: true)
                    }
                }
                HStack(spacing: 6) {
                    Text(info.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    if let project = info.service?.projectName {
                        Text("·").foregroundStyle(Theme.textTertiary)
                        Text(project)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Exposure: only flagged when it is reachable from the network.
            if info.exposure.isPubliclyReachable {
                HStack(spacing: 4) {
                    StatusDot(color: Theme.warning, size: 5)
                    Text(Presentation.exposureLabel(info.exposure, locale))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.warning)
                }
                .help(locale.t("exposure.help"))
            }

            if let confidence = info.service?.confidence {
                Text("\(Presentation.confidence(confidence))%")
                    .font(Theme.monoMicro)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 28, alignment: .trailing)
            }

            Text(":\(info.port)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 52, alignment: .trailing)

            action
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.rowHeight)
        .background(rowBackground)
        .onHover { hovering.value = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Theme.rowSelected }
        if hovering.value { return Theme.rowHover }
        return .clear
    }

    private var glyph: some View {
        Image(systemName: Presentation.symbol(for: info.service?.kind))
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
    }

    private var action: some View {
        HStack(spacing: 2) {
            if let url = info.localURL {
                IconButton(
                    systemName: "safari",
                    help: locale.t("ports.openInBrowser"),
                    action: { NSWorkspace.shared.open(url) }
                )
            }
            // Destructive actions stay hidden until the row is hovered or
            // selected: they should be available, never inviting.
            IconButton(
                systemName: "arrow.clockwise",
                help: locale.t("ports.restart"),
                action: { store.requestRestart(info) }
            )
            .opacity(hovering.value || isSelected ? 1 : 0)
            IconButton(
                systemName: "stop.circle",
                help: locale.t("ports.stop"),
                tint: Theme.danger.opacity(0.85),
                action: { store.requestStop(info) }
            )
            .opacity(hovering.value || isSelected ? 1 : 0)
        }
    }
}
