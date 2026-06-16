import Foundation

/// Modal presentation styles
public enum ModalPresentationStyle: Sendable {
    case sheet         // iOS sheet with detents (default)
    case fullScreen    // Full screen modal
    case formSheet     // Smaller sheet (iPad optimized)
    case pageSheet     // Page sheet
    case crossDissolve // Full screen modal with fade transition
    case custom        // Engine-driven custom transition (see NavigationRequest.transition)
}

/// Navigation request types posted via NotificationCenter
public enum NavigationRequestType {
    /// Push a new screen onto the navigation stack
    case push(screenId: String, params: [String: Any])
    /// Pop the current screen (go back)
    case pop
    /// Pop to the root screen of the current navigation stack (back to the list)
    case popToRoot
    /// Complete current flow and transition to destination flow (one-way)
    case completeFlow(destination: String)
    /// Switch to a different flow (reversible) - Future
    case switchFlow(flowId: String)
    /// Present a modal screen
    case presentModal(
        screenId: String,
        params: [String: Any],
        style: ModalPresentationStyle,
        detents: [DSL.Model.Action.SheetDetent]?,
        grabber: Bool?
    )
    /// Dismiss current modal
    case dismiss
    /// Select a tab by index or id
    case selectTab(index: Int?, id: String?)
}

/// Request to navigate, posted by components via NotificationCenter
public struct NavigationRequest {
    public let type: NavigationRequestType

    /// Resolved action-level transition for a `.push` / `.presentModal`. Engine
    /// internal — host code never constructs these. `nil` means "no action-level
    /// transition" (the navigation container falls back to the screen/app default
    /// for pushes, or the native modal animation).
    let transition: DSL.Model.ScreenTransition.Resolved?

    public init(type: NavigationRequestType) {
        self.type = type
        self.transition = nil
    }

    /// Engine-internal initializer attaching a resolved transition.
    init(type: NavigationRequestType, transition: DSL.Model.ScreenTransition.Resolved?) {
        self.type = type
        self.transition = transition
    }
}

/// Notification names for navigation events
public extension Notification.Name {
    /// Posted when a component requests navigation
    static let app8NavigationRequest = Notification.Name("app8NavigationRequest")
    /// Posted when a flow completes
    static let app8FlowComplete = Notification.Name("app8FlowComplete")
    /// Posted when the visible screen changes (e.g., after didShow, tab switch)
    static let app8ScreenContextChanged = Notification.Name("app8ScreenContextChanged")
}
