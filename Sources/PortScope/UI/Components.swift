import AppKit
import PortScopeKit
import SwiftUI

/// Shared presentation helpers. Keeping these out of the views means the same
/// phrasing is used everywhere — a port described as "on all interfaces" in the
/// list says the same thing in the inspector.
enum Presentation {
    /// Human label for how a port is bound.
    @MainActor
    static func exposureLabel(_ exposure: Exposure, _ locale: AppLocale) -> String {
        switch exposure {
        case .loopback: return locale.t("exposure.loopback")
        case .interface: return locale.t("exposure.interface")
        case .allInterfaces: return locale.t("exposure.allInterfaces")
        }
    }

    static func exposureColor(_ exposure: Exposure) -> Color {
        exposure.isPubliclyReachable ? Theme.warning : Theme.textTertiary
    }

    /// "2h 14m", "3d 4h", "45s". Compact because it sits in a dense row.
    static func uptime(_ interval: TimeInterval?) -> String {
        guard let interval, interval > 0 else { return "—" }
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 {
            let remainder = minutes % 60
            return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
        }
        let days = hours / 24
        let remainder = hours % 24
        return remainder == 0 ? "\(days)d" : "\(days)d \(remainder)h"
    }

    /// Confidence as a percentage, rounded down so 0.99 never reads as 100%.
    static func confidence(_ value: Double) -> Int {
        min(99, Int(value * 100))
    }

    /// SF Symbol for a service kind. Icons are outlines, like the reference.
    static func symbol(for kind: ServiceKind?) -> String {
        switch kind {
        case .database: return "cylinder.split.1x2"
        case .cache: return "bolt.horizontal.circle"
        case .devServer: return "hammer"
        case .bundler: return "shippingbox"
        case .api: return "curlybraces"
        case .web: return "globe"
        case .ai: return "sparkles"
        case .messaging: return "bubble.left.and.bubble.right"
        case .container: return "shippingbox.and.arrow.backward"
        case .system: return "gearshape"
        case .other, .none: return "questionmark.circle"
        }
    }

    /// The address a person would type, without the scheme.
    ///
    /// A service bound to a wildcard address is shown as `localhost:port`,
    /// because that is the address that works — `0.0.0.0` and `::` are not
    /// connectable names.
    static func hostAndPort(_ info: PortInfo) -> String {
        let connectable = info.addresses.first {
            $0 != "0.0.0.0" && $0 != "::"
        } ?? "localhost"
        let host = connectable == "::1" ? "localhost" : connectable
        return host.contains(":") ? "[\(host)]:\(info.port)" : "\(host):\(info.port)"
    }

    /// Trim a long path to its last few components, keeping the start.
    static func abbreviate(_ path: String, keep: Int = 2) -> String {
        let components = (path as NSString).pathComponents.filter { $0 != "/" }
        guard components.count > keep else { return path }
        return "…/" + components.suffix(keep).joined(separator: "/")
    }
}

// MARK: - Reusable pieces

/// A small caps label, matching the reference's "PROFILES" treatment.
struct CapsLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.capsLabel)
            .tracking(0.6)
            .foregroundStyle(Theme.textTertiary)
    }
}

/// The status dot used beside a service name.
struct StatusDot: View {
    var color: Color
    var size: CGFloat = 6
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

/// A bordered container with the card radius, used for every panel.
struct Card<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

/// A hairline separator that spans a row.
struct Hairline: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// A small pill, used for badges like "NEW" or a confidence value.
struct Pill: View {
    var text: String
    var color: Color
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(Theme.monoMicro)
            .foregroundStyle(filled ? Color.white : color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(filled ? color : color.opacity(0.12))
            )
            .overlay(Capsule().strokeBorder(filled ? .clear : color.opacity(0.25), lineWidth: 1))
    }
}

/// An icon button that only shows a background on hover.
struct IconButton: View {
    var systemName: String
    var help: String
    var tint: Color = Theme.textSecondary
    var action: () -> Void

    @StateObject private var hovering = LocalFlag()

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering.value ? Theme.textPrimary : tint)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering.value ? Theme.rowHover : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering.value = $0 }
        .help(help)
    }
}

/// Rounded, low-contrast text field matching the inset controls.
struct InsetSearchField: View {
    var placeholder: String
    var text: Binding<String>

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }
}
