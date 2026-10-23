import Foundation

/// Decides which ports are folded away by default.
///
/// WeChat, Discord, ControlCenter and `rapportd` hold ports all day. They are
/// real, but they are never what someone opens a port monitor to look at, so
/// the app groups them behind a disclosure. The rule lives here rather than in
/// the UI because it is a judgement with consequences — folding the wrong row
/// makes a service someone started invisible — and so it can be tested.
public enum BackgroundClassification {
    /// Kinds that are always shown, even when launched from an app bundle.
    /// Work you started is never folded, whatever else is true about it.
    public static let alwaysForeground: Set<ServiceInfo.Kind> = [
        .devServer, .bundler, .database, .cache, .ai, .container,
    ]

    /// Whether a port belongs to something that runs in the background by
    /// nature: a macOS service, a chat client, or a desktop app.
    ///
    /// This is a judgement, not a fact, which is why the UI folds it into a
    /// disclosure rather than filtering it silently — nothing is ever truly
    /// hidden, and a search still reaches everything.
    public static func isBackground(_ info: PortInfo) -> Bool {
        if let kind = info.service?.kind, alwaysForeground.contains(kind) {
            return false
        }
        switch info.service?.kind {
        case .system:
            return true
        case .messaging:
            // Slack, Discord, WeChat — desktop clients, not services you run.
            return true
        default:
            // Any other app-bundle process is an app someone installed, not a
            // service they started.
            return info.appBundleName != nil
        }
    }
}
