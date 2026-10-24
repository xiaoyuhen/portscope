import AppKit
import Combine
import ServiceManagement

/// "Open at login", through `SMAppService`.
///
/// The status is read back from the system rather than remembered: the user
/// can remove the item in System Settings at any time, and a switch that says
/// "on" for an item macOS has dropped is worse than no switch.
@MainActor
final class LoginItem: ObservableObject {
    enum State: Equatable {
        case off
        case on
        /// Registered, but macOS is waiting for the user to allow it in
        /// System Settings → General → Login Items.
        case needsApproval
    }

    @Published private(set) var state: State = .off
    /// Why the last change failed, in macOS's words. Shown under the switch.
    @Published private(set) var failure: String?

    init() { refresh() }

    var isOn: Bool { state != .off }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled: state = .on
        case .requiresApproval: state = .needsApproval
        default: state = .off
        }
    }

    func set(_ enabled: Bool) {
        failure = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            failure = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
