import CoreGraphics

public struct DSL {
    public struct Model {}
}

extension DSL.Model {

    protocol Node: Decodable, Sendable {}

    protocol TemplatesHolder: Node {
        var templates: [Component.`Any`]? { get }
    }

    protocol ChildrenHolder: Node {
        var children: [Component.`Any`] { get set }
    }

    protocol StyleHolder: Node {
        associatedtype Style: Decodable
        var style: Style? { get set }
    }

    protocol LayoutHolder: Node {
        var layout: Layout? { get }
    }

    protocol PropertiesHolder: Node {
        associatedtype Properties: Decodable
        var properties: Properties { get }
    }

    /// Protocol for optional properties (used by states that may not override base properties)
    protocol OptionalPropertiesHolder: Node {
        associatedtype Properties: Decodable
        var properties: Properties? { get }
    }

    protocol ActionsHolder: Node {
        var actions: [ActionTrigger: Action]? { get }
    }

    /// Protocol for nodes that can define variables
    protocol VariablesHolder: Node {
        var variables: [String: VariableDefinition]? { get }
    }

    /// Protocol for nodes that can have event triggers
    protocol EventTriggersHolder: Node {
        var onEvent: [EventTrigger]? { get }
    }

    /// Protocol for nodes that accept input parameters (screens)
    protocol InputParametersHolder: Node {
        var inputParameters: [String: InputParameterDefinition]? { get }
    }
    
    protocol StateProtocol: StyleHolder, LayoutHolder, OptionalPropertiesHolder {
        var childStates: [String: String]? { get }
        var animation: Animation? { get }
    }

    /// Trigger types for user-definable state changes
    enum Trigger: String, Decodable, Sendable {
        case touchDown      // Finger touches component
        case touchUp        // Finger releases
        case focus          // TextField gains focus
        case blur           // TextField loses focus
        case hover          // Pointer hovers (iPadOS)
        case hoverEnd       // Pointer leaves
    }

    /// Protocol for content that supports states
    protocol StatefulContent: StyleHolder, LayoutHolder, PropertiesHolder {
        associatedtype StateType: StateProtocol where StateType.Style == Style, StateType.Properties == Properties
        /// Default state name - can be static ("normal") or expression ("{{condition ? 'a' : 'b'}}")
        var defaultStateName: String? { get }
        var states: [String: StateType]? { get }
        var triggers: [Trigger: String]? { get }
    }

    // MARK: - Edge Insets

    /// Edge insets for padding/margins
    struct EdgeInsets: Decodable, Sendable {
        let top: CGFloat?
        let left: CGFloat?
        let bottom: CGFloat?
        let right: CGFloat?

        /// Create with uniform value
        static func uniform(_ value: CGFloat) -> EdgeInsets {
            EdgeInsets(top: value, left: value, bottom: value, right: value)
        }

        /// Get value with defaults
        func resolve(defaultTop: CGFloat = 0, defaultLeft: CGFloat = 0, defaultBottom: CGFloat = 0, defaultRight: CGFloat = 0) -> (top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
            (
                top: top ?? defaultTop,
                left: left ?? defaultLeft,
                bottom: bottom ?? defaultBottom,
                right: right ?? defaultRight
            )
        }
    }

    // MARK: - Tab Bar

    /// Tab configuration for tab bar screens
    struct Tab: Decodable, Sendable {
        /// Unique identifier for this tab
        let id: String
        /// Tab label shown below icon
        let label: String
        /// SF Symbol name for tab icon
        let icon: String
        /// Screen ID to render in this tab
        let screen: String
    }

    /// Content for tab bar screens
    struct TabBarContent: Decodable, Sendable {
        /// Array of tabs
        let tabs: [Tab]
        /// ID of the initially selected tab (defaults to first tab)
        let initialTab: String?
        /// Tint color for selected tab items (hex string)
        let tintColor: String?
        /// Color for unselected tab items (hex string)
        let unselectedColor: String?
    }

    // MARK: - Navigation Bar

    /// Navigation bar configuration for screens
    struct NavigationBar: Decodable, Sendable {
        /// Title displayed in the navigation bar (ignored when titleView is set)
        let title: String?
        /// Custom DSL component rendered as the navigation bar title
        let titleView: Component.`Any`?
        /// Alignment for titleView: "left" places it as leftBarButtonItem, "center" (default) uses titleView
        let titleAlignment: String?
        /// Custom back button label (replaces default "Back")
        let backLabel: String?
        /// Left bar button action (e.g., Cancel, Close)
        let leftAction: BarAction?
        /// Right bar button action (e.g., Save, Done) — kept for backward compatibility
        let rightAction: BarAction?
        /// Multiple right bar button actions — takes priority over rightAction
        let rightActions: [BarAction]?
        /// Hide the navigation bar entirely
        let hidden: Bool?
        /// Title text color (hex string)
        let titleColor: String?
    }

    /// Action for navigation bar buttons
    struct BarAction: Decodable, Sendable {
        /// Button label text
        let label: String?
        /// SF Symbol icon name
        let icon: String?
        /// Action to execute when tapped
        let action: Action
        /// Button style: "bold", "destructive"
        let style: String?
        /// Tint color override (hex string) — overrides style
        let color: String?
    }
}

extension DSL.Model.StyleHolder {

    @discardableResult
    mutating func setResolvedStyle(_ style: DSL.Model.Style.StylePointerResolvable) -> Bool {
        if let style = style as? Style {
            self.style = style
            return true
        }
        return false
    }
}
