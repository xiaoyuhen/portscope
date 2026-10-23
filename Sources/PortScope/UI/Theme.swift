import PortScopeKit
import SwiftUI

/// Design tokens.
///
/// The reference app (magpie) sits on a near-flat canvas with one large
/// container whose rows are separated by hairlines — almost no shadows, and
/// colour reserved for status. These tokens keep every view on that system,
/// in both light and dark.
///
/// Colours are defined as dynamic `NSColor`s so the whole app follows the
/// system appearance without any per-view branching.
enum Theme {
    // MARK: - Surfaces

    /// The window background, slightly darker/lighter than the cards.
    static let canvas = dynamic(
        light: NSColor(white: 0.957, alpha: 1),
        dark: NSColor(red: 0.055, green: 0.055, blue: 0.063, alpha: 1)
    )
    /// The one large container that holds rows.
    static let surface = dynamic(
        light: NSColor.white,
        dark: NSColor(red: 0.086, green: 0.086, blue: 0.098, alpha: 1)
    )
    /// Inset controls: search field, segmented control, pills.
    static let surfaceInset = dynamic(
        light: NSColor(white: 0.945, alpha: 1),
        dark: NSColor(white: 0.145, alpha: 1)
    )
    /// Floating surfaces: toasts, popovers.
    static let surfaceRaised = dynamic(
        light: NSColor.white,
        dark: NSColor(red: 0.145, green: 0.145, blue: 0.16, alpha: 1)
    )
    /// Hover / selected row.
    static let rowHover = dynamic(
        light: NSColor(white: 0.965, alpha: 1),
        dark: NSColor(white: 0.115, alpha: 1)
    )
    static let rowSelected = dynamic(
        light: NSColor(white: 0.945, alpha: 1),
        dark: NSColor(white: 0.135, alpha: 1)
    )

    // MARK: - Lines

    static let stroke = dynamic(
        light: NSColor(white: 0, alpha: 0.085),
        dark: NSColor(white: 1, alpha: 0.075)
    )
    static let strokeStrong = dynamic(
        light: NSColor(white: 0, alpha: 0.14),
        dark: NSColor(white: 1, alpha: 0.14)
    )

    // MARK: - Text

    static let textPrimary = dynamic(
        light: NSColor(white: 0.09, alpha: 1),
        dark: NSColor(white: 0.94, alpha: 1)
    )
    static let textSecondary = dynamic(
        light: NSColor(white: 0.40, alpha: 1),
        dark: NSColor(white: 0.62, alpha: 1)
    )
    static let textTertiary = dynamic(
        light: NSColor(white: 0.58, alpha: 1),
        dark: NSColor(white: 0.45, alpha: 1)
    )

    // MARK: - Status

    /// Live / healthy.
    static let live = Color(red: 0.24, green: 0.78, blue: 0.42)
    /// Reachable from the network — a caution, not an error.
    static let warning = Color(red: 0.95, green: 0.67, blue: 0.20)
    static let danger = Color(red: 0.93, green: 0.32, blue: 0.36)
    static let accent = Color(red: 0.42, green: 0.55, blue: 0.98)

    /// Kind colours for the service glyph. Muted on purpose: the list should
    /// read as one system, not as a rainbow.
    static func tint(for kind: ServiceKind) -> Color {
        switch kind {
        case .database: return Color(red: 0.45, green: 0.72, blue: 0.98)
        case .cache: return Color(red: 0.95, green: 0.45, blue: 0.38)
        case .devServer, .bundler: return Color(red: 0.55, green: 0.80, blue: 0.42)
        case .api: return Color(red: 0.70, green: 0.58, blue: 0.96)
        case .web: return Color(red: 0.40, green: 0.70, blue: 0.88)
        case .ai: return Color(red: 0.95, green: 0.62, blue: 0.85)
        case .messaging: return Color(red: 0.95, green: 0.72, blue: 0.35)
        case .container: return Color(red: 0.38, green: 0.68, blue: 0.95)
        case .system: return Color(white: 0.55)
        case .other: return Color(white: 0.55)
        }
    }

    // MARK: - Metrics

    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8
    static let gutter: CGFloat = 20
    static let rowHeight: CGFloat = 58

    // MARK: - Type

    static let mono = Font.system(.body, design: .monospaced)
    static let monoSmall = Font.system(.caption, design: .monospaced)
    static let monoMicro = Font.system(size: 10, weight: .medium, design: .monospaced)
    /// Section labels like "PROFILES" in the reference: small, caps, tracked.
    static let capsLabel = Font.system(size: 10, weight: .semibold)

    // MARK: - Helpers

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

/// Short alias so view code doesn't have to spell out `ServiceInfo.Kind`.
typealias ServiceKind = ServiceInfo.Kind
