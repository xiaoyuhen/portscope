import Foundation

/// One row of the ports list.
///
/// The main window and the menu bar panel draw the same list at different
/// densities. They used to each filter the store themselves, and they drifted:
/// the popover listed WeChat and ControlCenter inline while the window folded
/// them. The rows are now computed in one place, so the two surfaces can only
/// differ in how a row is drawn, never in which rows exist.
public enum PortListRow: Identifiable, Equatable {
    case port(PortInfo, muted: Bool)
    /// The quiet row that opens the folded background section.
    case backgroundDisclosure(count: Int)

    public var id: String {
        switch self {
        case .port(let info, _): return "port-\(info.port)"
        case .backgroundDisclosure: return "background-disclosure"
        }
    }
}

public enum PortListModel {
    /// The rows to draw, in order: foreground first, then the background set
    /// either expanded, matched by a search, or folded behind a disclosure.
    ///
    /// A search shows background matches even while folded — typing "wechat"
    /// has to find WeChat — but never shows the disclosure row, because there
    /// is nothing folded away in that state.
    public static func rows(
        foreground: [PortInfo],
        background: [PortInfo],
        backgroundExpanded: Bool,
        searching: Bool
    ) -> [PortListRow] {
        var rows = foreground.map { PortListRow.port($0, muted: false) }
        if backgroundExpanded || searching {
            rows += background.map { PortListRow.port($0, muted: true) }
        } else if !background.isEmpty {
            rows.append(.backgroundDisclosure(count: background.count))
        }
        return rows
    }
}
