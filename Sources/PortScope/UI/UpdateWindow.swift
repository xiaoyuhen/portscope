import AppKit
import PortScopeKit
import SwiftUI

/// The "update available" window: what is new, and install / later / skip.
///
/// A window of its own rather than an overlay in the main window, because the
/// check usually fires while the main window is closed and PortScope is only
/// in the menu bar.
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    private let locale: AppLocale
    private var window: NSWindow?

    init(locale: AppLocale) {
        self.locale = locale
        super.init()
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: UpdateView(close: { [weak self] in self?.close() })
                .environmentObject(locale)
                .environmentObject(Updater.shared)
        )
        return window
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

struct UpdateView: View {
    let close: () -> Void
    @EnvironmentObject private var locale: AppLocale
    @EnvironmentObject private var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(locale.t("update.title"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let release = updater.pending {
                        Text(locale.t("update.versions", release.version, updater.currentVersion))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            CapsLabel(text: locale.t("update.notes"))
            ScrollView {
                Text(notes)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxHeight: .infinity)
            .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 8))

            if let status {
                Text(status.text)
                    .font(.system(size: 11))
                    .foregroundStyle(status.isError ? Theme.danger : Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                button(locale.t("update.skip"), primary: false) {
                    if let release = updater.pending { updater.skip(release) }
                    close()
                }
                Spacer()
                button(locale.t("update.later"), primary: false) {
                    if let release = updater.pending { updater.remindLater(release) }
                    close()
                }
                .keyboardShortcut(.cancelAction)
                button(locale.t("update.install"), primary: true) {
                    guard let release = updater.pending else { return }
                    Task { await updater.install(release) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isBusy)
            }
        }
        .padding(20)
        .frame(width: 480, height: 380)
        .background(Theme.surface)
    }

    /// Release notes as written, with inline Markdown (code, emphasis, links)
    /// rendered and line breaks kept.
    private var notes: AttributedString {
        let raw = updater.pending?.notes ?? ""
        let text = raw.isEmpty ? locale.t("update.noNotes") : raw
        return (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    private var isBusy: Bool {
        updater.state == .downloading || updater.state == .installing
    }

    private var status: (text: String, isError: Bool)? {
        switch updater.state {
        case .downloading: return (locale.t("update.downloading"), false)
        case .installing: return (locale.t("update.installing"), false)
        case .failed(let reason): return (locale.t("update.failed", reason), true)
        default: return nil
        }
    }

    private func button(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(primary ? Color.white : Theme.textSecondary)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(primary ? Theme.accent : Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(primary ? .clear : Theme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
