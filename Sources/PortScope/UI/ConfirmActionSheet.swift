import PortScopeKit
import SwiftUI

/// The confirmation sheet shown before anything is signalled.
///
/// Stops are not undoable, so this always asks — but it is a single click, not
/// a type-the-name ritual. What the sheet does add is *context*: which service,
/// which port, how long it has been running, and whether a restart will be
/// possible. That is what makes the decision easy.
struct ConfirmActionSheet: View {
    let action: PendingAction
    @EnvironmentObject private var locale: AppLocale
    @EnvironmentObject private var store: PortStore

    private var isRestart: Bool { action.kind == .restart }
    private var info: PortInfo { action.info }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: isRestart ? "arrow.clockwise" : "stop.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isRestart ? Theme.accent : Theme.danger)
                    .frame(width: 34, height: 34)
                    .background(
                        (isRestart ? Theme.accent : Theme.danger).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(locale.t(isRestart ? "confirm.restartTitle" : "confirm.stopTitle"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(locale.t(isRestart ? "confirm.restartSubtitle" : "confirm.stopSubtitle"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 7) {
                fact(locale.t("confirm.service"), info.service?.title ?? info.processName)
                fact(locale.t("confirm.port"), ":\(info.port)")
                fact(locale.t("confirm.pid"), String(info.pid))
                if let uptime = info.uptime {
                    fact(locale.t("confirm.uptime"), Presentation.uptime(uptime))
                }
                if isRestart {
                    fact(locale.t("confirm.command"), info.arguments.first ?? info.processName)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 8))

            if isRestart, info.workingDirectory == nil {
                Text(locale.t("confirm.noWorkingDirectory"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warning)
            }

            if info.service?.kind == .system || info.appBundleName != nil {
                Text(locale.t("confirm.appWarning"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Spacer()
                sheetButton(
                    locale.t("common.cancel"),
                    tint: Theme.textSecondary,
                    filled: false
                ) { store.cancelPendingAction() }
                .keyboardShortcut(.cancelAction)
                sheetButton(
                    locale.t(isRestart ? "confirm.restart" : "confirm.stop"),
                    tint: isRestart ? Theme.accent : Theme.danger,
                    filled: true
                ) {
                    Task { await store.confirmPendingAction() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.surface)

    }

    /// Buttons drawn to match the app rather than the system defaults, which
    /// read as a different product next to this canvas.
    private func sheetButton(
        _ title: String, tint: Color, filled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(filled ? Color.white : Theme.textSecondary)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(
                    filled ? tint : Theme.surfaceInset,
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(filled ? .clear : Theme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(Theme.monoSmall)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

/// Transient banner after an action completes.
struct ActionBanner: View {
    let message: ActionMessage
    @EnvironmentObject private var locale: AppLocale

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.isError ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(message.isError ? Theme.danger : Theme.live)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        // Opaque, not translucent: the toast sits over the list and must be
        // readable without the rows behind it bleeding through.
        .background(
            Theme.surfaceRaised,
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder((message.isError ? Theme.danger : Theme.live).opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 460)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Localized text, with the service name and detail interpolated where the
    /// message calls for them.
    private var text: String {
        let service = message.service?.service?.title
            ?? message.service?.processName
            ?? ""
        let base = locale.t(message.text, service)
        if let detail = message.detail, !detail.isEmpty {
            return base + " — " + detail
        }
        return base
    }
}
