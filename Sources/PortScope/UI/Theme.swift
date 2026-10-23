import SwiftUI

/// Design tokens.
///
/// The reference app (magpie) sits on a near-black canvas with cards that are
/// only a few percent lighter and hairline borders — almost no shadows, and
/// colour reserved for status. These tokens keep every view on that system.
enum Theme {
    // Canvas and surfaces
    static let canvas = Color(red: 0.063, green: 0.063, blue: 0.071)
    static let surface = Color(red: 0.094, green: 0.094, blue: 0.106)
    static let surfaceRaised = Color(red: 0.125, green: 0.125, blue: 0.141)
    static let stroke = Color.white.opacity(0.08)
    static let strokeStrong = Color.white.opacity(0.14)

    // Text
    static let textPrimary = Color(red: 0.94, green: 0.94, blue: 0.96)
    static let textSecondary = Color(red: 0.60, green: 0.60, blue: 0.65)
    static let textTertiary = Color(red: 0.42, green: 0.42, blue: 0.46)

    // Status
    static let live = Color(red: 0.30, green: 0.82, blue: 0.45)
    static let warning = Color(red: 0.98, green: 0.72, blue: 0.25)
    static let danger = Color(red: 0.95, green: 0.35, blue: 0.38)
    static let accent = Color(red: 0.47, green: 0.60, blue: 0.98)

    // Metrics
    static let cardRadius: CGFloat = 12
    static let rowRadius: CGFloat = 9
    static let gutter: CGFloat = 20

    static let mono = Font.system(.body, design: .monospaced)
    static let monoSmall = Font.system(.caption, design: .monospaced)
}
