import PortScopeKit
import SwiftUI

/// Detail pane for the selected port.
///
/// This is where the app answers the question the list only hints at: what this
/// service is, what evidence that conclusion rests on, and how to reach or stop
/// it. The evidence section is deliberately prominent — a confident-sounding
/// label with no visible basis is worse than no label.
struct InspectorView: View {
    let info: PortInfo
    @EnvironmentObject private var locale: AppLocale
    @EnvironmentObject private var store: PortStore
    @StateObject private var showCommandLine = LocalFlag()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Hairline()
                summarySection
                evidenceSection
                detailsSection
                // A container's listener is the engine's port forwarder; its
                // working directory and uptime are the forwarder's, not the
                // container's.
                if info.container == nil, let cwd = info.workingDirectory {
                    projectSection(cwd)
                }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: Presentation.symbol(for: info.service?.kind))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.tint(for: info.service?.kind ?? .other))
                    .frame(width: 34, height: 34)
                    .background(
                        Theme.tint(for: info.service?.kind ?? .other).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(info.service?.title ?? info.processName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                    Text(info.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Text(Presentation.hostAndPort(info))
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                Spacer()
                if let url = info.localURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label(locale.t("inspector.open"), systemImage: "arrow.up.right")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.accent)
                }
            }

            HStack(spacing: 6) {
                badge(
                    Presentation.exposureLabel(info.exposure, locale),
                    color: Presentation.exposureColor(info.exposure)
                )
                if let kind = info.service?.kind {
                    badge(locale.t("kind.\(kind.rawValue)"), color: Theme.tint(for: kind))
                }
                if info.container == nil, let uptime = info.uptime {
                    badge(locale.t("inspector.uptime", Presentation.uptime(uptime)),
                          color: Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                actionButton(
                    locale.t("inspector.restart"), symbol: "arrow.clockwise", tint: Theme.accent
                ) { store.requestRestart(info) }
                actionButton(
                    locale.t("inspector.stop"), symbol: "stop.circle", tint: Theme.danger
                ) { store.requestStop(info) }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(14)
    }

    private func actionButton(
        _ title: String, symbol: String, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7).strokeBorder(tint.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            CapsLabel(text: locale.t("inspector.whatItIs"))
            Text(locale.t(info.service?.summaryKey ?? "service.unknown"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(14)
    }

    // MARK: - Evidence

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CapsLabel(text: locale.t("inspector.evidence"))
                Spacer()
                if let confidence = info.service?.confidence {
                    Text(locale.t("inspector.confidence", Presentation.confidence(confidence)))
                        .font(Theme.monoMicro)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            let evidence = info.service?.evidence ?? []
            if evidence.isEmpty {
                Text(locale.t("inspector.noEvidence"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(evidence.enumerated()), id: \.offset) { _, item in
                        evidenceRow(item)
                    }
                }
            }
        }
        .padding(14)
    }

    private func evidenceRow(_ item: Evidence) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // A bar rather than a number: it communicates relative strength at
            // a glance without implying precision.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.accent.opacity(0.35 + item.weight * 0.65))
                .frame(width: 3, height: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(locale.t(item.sourceKey))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text(item.detail.isEmpty ? locale.t(item.sourceKey + ".detail") : item.detail)
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel(text: locale.t("inspector.process"))
            detailRow(locale.t("inspector.pid"), String(info.pid))
            if let path = info.executablePath {
                detailRow(locale.t("inspector.executable"), Presentation.abbreviate(path, keep: 3),
                          full: path)
            }
            if let status = info.service?.httpStatus {
                detailRow(locale.t("inspector.httpStatus"), "HTTP \(status)")
            }
            if let server = info.service?.serverHeader {
                detailRow(locale.t("inspector.server"), server)
            }

            Button {
                showCommandLine.value.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showCommandLine.value ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text(locale.t("inspector.commandLine"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            if showCommandLine.value {
                Text(info.commandLine)
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textTertiary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(14)
    }

    private func detailRow(_ label: String, _ value: String, full: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(Theme.monoSmall)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(full ?? value)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Project

    private func projectSection(_ cwd: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel(text: locale.t("inspector.project"))
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                Text(Presentation.abbreviate(cwd, keep: 3))
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(cwd)
                Spacer(minLength: 0)
                Button(locale.t("inspector.reveal")) {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(14)
    }
}
