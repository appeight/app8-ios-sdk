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
        /// Actions keyed by trigger. Each trigger maps to a list because JSON
        /// authors may chain multiple effects (e.g. `[emit, navigation]`).
        /// Decoded from JSON that accepts either a single Action object or an
        /// array — see `ActionList`.
        var actions: [ActionTrigger: [Action]]? { get }

        /// Author-declared analytics bindings keyed by trigger. Independent
        /// from `actions` — same trigger can have both.
        var analytics: [ActionTrigger: AnalyticsBinding]? { get }

        /// Continuous interaction → variable bindings (pan, …). Distinct from
        /// `actions`: these stream raw gesture quantities into variables rather
        /// than firing one-shot actions. Optional; defaults to `nil`.
        var gestures: Gestures? { get }
    }
}

extension DSL.Model.ActionsHolder {
    var gestures: DSL.Model.Gestures? { nil }
}

extension DSL.Model {

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
        /// System badge on the tab item, usually an expression over app
        /// variables (`"{{length(cart)}}"`). Empty, `0` or nil hides it.
        let badge: String?
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
        /// Bar button tint (back chevron, bar actions) as hex. Applied while
        /// this screen is on top; nil restores the system tint.
        let tintColor: String?
        /// iOS 26 scroll-edge effect under the bar (the blur + tint over content
        /// scrolling behind it): `automatic` (default), `soft`, `hard`, `hidden`.
        let topEdgeEffect: EdgeEffect?

        enum EdgeEffect: String, SafeEnumCodable, Sendable {
            case automatic, soft, hard, hidden
            static let unknownCase: EdgeEffect = .automatic
        }
        /// System search field (`UISearchController`) attached to the navigation bar.
        let search: SearchBar?
    }

    /// Native navigation-bar search (`navigationItem.searchController`). The
    /// system owns the field, its glass, the dictation mic, and the cancel (✕)
    /// button that appears while the field is focused.
    struct SearchBar: Decodable, Sendable {
        /// Placeholder text (supports `{{i18n(...)}}` / variables).
        let placeholder: String?
        /// Screen variable kept in sync with the field text.
        let bindVariable: String?
        /// Where the field sits: `automatic`, `stacked` (below the title),
        /// `inline` (in the title row), `integrated` (iOS 26: in the bar itself),
        /// `integratedButton` (iOS 26: a search button that expands),
        /// `integratedCentered` (iOS 26). Defaults to `automatic`.
        let placement: Placement?
        /// Hide the field when the content scrolls. Defaults to `false`.
        let hidesWhenScrolling: Bool?
        /// Field tint (caret, cancel button) as hex.
        let tintColor: String?
        /// iOS 26 `integrated` placement only: stretch the field across the bar
        /// (leading-aligned) instead of the compact trailing field. Defaults to `false`.
        let fillsBar: Bool?
        /// Actions run when the user taps the keyboard's search key.
        let onSubmit: [Action]?

        enum Placement: String, SafeEnumCodable, Sendable {
            case automatic, stacked, inline, integrated, integratedButton, integratedCentered
            static let unknownCase: Placement = .automatic
        }

        enum CodingKeys: String, CodingKey {
            case placeholder, bindVariable, placement, hidesWhenScrolling, tintColor, fillsBar, onSubmit
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
            bindVariable = try c.decodeIfPresent(String.self, forKey: .bindVariable)
            placement = try c.decodeIfPresent(Placement.self, forKey: .placement)
            hidesWhenScrolling = try c.decodeIfPresent(Bool.self, forKey: .hidesWhenScrolling)
            tintColor = try c.decodeIfPresent(String.self, forKey: .tintColor)
            fillsBar = try c.decodeIfPresent(Bool.self, forKey: .fillsBar)
            // A single action or an array, like every other trigger.
            if let list = try? c.decodeIfPresent([Action].self, forKey: .onSubmit) {
                onSubmit = list
            } else {
                onSubmit = (try? c.decodeIfPresent(Action.self, forKey: .onSubmit)).flatMap { $0.map { [$0] } }
            }
        }
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
