import Combine
import SwiftUI

/// Local, view-owned state.
///
/// `@State` is a macro in the current SDK and its plugin ships only with
/// Xcode, so this stands in for it: a tiny observable object owned by the view
/// through `@StateObject`. Views declare one property and read/write `state.value`.
///
///     @StateObject private var page = LocalState(Page.ports)
///     page.value = .settings
///
/// It is intentionally minimal — anything shared belongs in `PortStore`.
@MainActor
final class LocalState<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) { self.value = value }
}

/// Local mutable flag, for hover and disclosure state.
typealias LocalFlag = LocalState<Bool>

extension LocalState where Value == Bool {
    convenience init() { self.init(false) }
}
