import PortScopeKit
import SwiftUI

/// A dashboard of the machine at a glance: how many ports, how many are
/// reachable from the network, what kinds of services are running.
///
/// Deliberately not a chart page — port counts are small integers and a bar
/// chart of "5 dev servers" would be decoration. The one visual that earns its
/// place is the kind breakdown, because the relative sizes are the point.
struct OverviewView: View {
    @EnvironmentObject private var locale: AppLocale
    @EnvironmentObject private var store: PortStore
    @ObservedObject var selection: LocalState<Int>
    @ObservedObject var page: LocalState<Page>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statTiles
                HStack(alignment: .top, spacing: 16) {
                    kindBreakdown
                    exposurePanel
                }
                activityPanel
            }
            .padding(Theme.gutter)
        }
    }

    // MARK: - Tiles

    private var statTiles: some View {
        Card {
            HStack(spacing: 0) {
                tile(value: "\(store.totalCount)", label: locale.t("overview.listening"))
                divider
                tile(
                    value: "\(store.developmentCount)",
                    label: locale.t("overview.devServers"),
                    accent: store.developmentCount > 0 ? Theme.live : nil
                )
                divider
                tile(
                    value: "\(store.databaseCount)",
                    label: locale.t("overview.dataStores"),
                    accent: store.databaseCount > 0 ? Theme.tint(for: .database) : nil
                )
                divider
                tile(
                    value: "\(store.exposedCount)",
                    label: locale.t("overview.networkReachable"),
                    accent: store.exposedCount > 0 ? Theme.warning : nil
                )
            }
            .frame(height: 82)
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.stroke).frame(width: 1, height: 40)
    }

    private func tile(value: String, label: String, accent: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundStyle(accent ?? Theme.textPrimary)
                .contentTransition(.numericText())
            CapsLabel(text: label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
    }

    // MARK: - Kind breakdown

    private var kinds: [(ServiceKind, Int)] {
        Dictionary(grouping: store.ports) { $0.service?.kind ?? .other }
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    private var kindBreakdown: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CapsLabel(text: locale.t("overview.byKind"))
                // A stacked bar plus a legend: the bar shows proportion, the
                // legend names each segment. No axis — the counts are too small
                // for one to add anything.
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(kinds, id: \.0) { kind, count in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.tint(for: kind))
                                .frame(width: max(4, geometry.size.width * fraction(count)))
                        }
                    }
                }
                .frame(height: 10)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(kinds, id: \.0) { kind, count in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.tint(for: kind))
                                .frame(width: 8, height: 8)
                            Text(locale.t("kind.\(kind.rawValue)"))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("\(count)")
                                .font(Theme.monoSmall)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func fraction(_ count: Int) -> CGFloat {
        let total = max(1, store.ports.count)
        return CGFloat(count) / CGFloat(total)
    }

    // MARK: - Exposure

    private var exposurePanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CapsLabel(text: locale.t("overview.exposure"))
                Text(locale.t("overview.exposureHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                let exposed = store.ports.filter(\.exposure.isPubliclyReachable)
                if exposed.isEmpty {
                    Text(locale.t("overview.nothingExposed"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.live)
                        .padding(.top, 2)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(exposed.prefix(6)) { info in
                            Button {
                                selection.value = info.port
                                page.value = .ports
                            } label: {
                                HStack(spacing: 8) {
                                    StatusDot(color: Theme.warning, size: 5)
                                    Text(info.service?.title ?? info.processName)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(":\(info.port)")
                                        .font(Theme.monoSmall)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if exposed.count > 6 {
                            Text(locale.t("overview.andMore", exposed.count - 6))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .frame(width: 260)
    }

    // MARK: - Activity

    /// What opened and closed while PortScope was running.
    ///
    /// This answers a question the live list cannot: "something was on 8080 a
    /// minute ago — what was it?" Ports that come and go are exactly the ones
    /// people need help identifying.
    private var activityPanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    CapsLabel(text: locale.t("overview.activity"))
                    Spacer()
                    if !store.activity.isEmpty {
                        Text(locale.t("overview.events", store.activity.count))
                            .font(Theme.monoMicro)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                if store.activity.isEmpty {
                    Text(locale.t("overview.noActivity"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                } else {
                    ForEach(store.activity.prefix(12)) { event in
                        HStack(spacing: 10) {
                            Image(systemName: event.kind == .appeared
                                  ? "arrow.up.right.circle" : "arrow.down.right.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(event.kind == .appeared ? Theme.live : Theme.textTertiary)
                            Text(event.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text(":\(event.port)")
                                .font(Theme.monoSmall)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(event.date.formatted(date: .omitted, time: .standard))
                                .font(Theme.monoMicro)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        if event.id != store.activity.prefix(12).last?.id {
                            Hairline(inset: 16)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

/// Settings: refresh rate, language, and the list of ignored ports.
struct SettingsView: View {
    @EnvironmentObject private var locale: AppLocale
    @EnvironmentObject private var store: PortStore

    private let intervals: [TimeInterval] = [1, 2, 5, 10, 30]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        row(
                            title: locale.t("settings.refreshTitle"),
                            subtitle: locale.t("settings.refreshSubtitle")
                        ) {
                            HStack(spacing: 2) {
                                ForEach(intervals, id: \.self) { interval in
                                    Button {
                                        store.refreshInterval = interval
                                    } label: {
                                        Text(locale.t("settings.seconds", Int(interval)))
                                            .font(.system(size: 11, weight: store.refreshInterval == interval ? .medium : .regular))
                                            .foregroundStyle(store.refreshInterval == interval ? Theme.textPrimary : Theme.textSecondary)
                                            .padding(.horizontal, 8)
                                            .frame(height: 24)
                                            .background {
                                                if store.refreshInterval == interval {
                                                    RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceInset)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(2)
                            .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.surfaceInset.opacity(0.5)))
                        }

                        Hairline()

                        row(
                            title: locale.t("settings.languageTitle"),
                            subtitle: locale.t("settings.languageSubtitle")
                        ) {
                            HStack(spacing: 2) {
                                ForEach(LocalizationSupport.supportedLanguages, id: \.self) { language in
                                    Button {
                                        locale.language = language
                                    } label: {
                                        Text(LocalizationSupport.displayName(for: language))
                                            .font(.system(size: 11, weight: locale.language == language ? .medium : .regular))
                                            .foregroundStyle(locale.language == language ? Theme.textPrimary : Theme.textSecondary)
                                            .padding(.horizontal, 10)
                                            .frame(height: 24)
                                            .background {
                                                if locale.language == language {
                                                    RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceInset)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(2)
                            .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.surfaceInset.opacity(0.5)))
                        }
                    }
                    .padding(16)
                }

                if store.hiddenCount > 0 {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                CapsLabel(text: locale.t("settings.hiddenTitle"))
                                Spacer()
                                Button(locale.t("settings.unhideAll")) { store.unhideAll() }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.accent)
                            }
                            Text(locale.t("settings.hiddenSubtitle"))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(16)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        CapsLabel(text: locale.t("settings.about"))
                        Text(locale.t("settings.aboutBody"))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                }
            }
            .padding(Theme.gutter)
        }
    }

    private func row<Accessory: View>(
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 12)
            accessory()
        }
    }
}
