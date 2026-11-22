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
        /// `properties.isHidden` declared in this state (nil: keep the base value).
        var hiddenFlag: String? { get }
        /// `animation` of a wrapped `properties.isHidden` in this state.
        var hiddenAnimation: Animation? { get }
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
        /// This tab's badge background (hex). Overrides the bar's `badgeColor`.
        let badgeColor: String?
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
        /// Badge background on every tab (hex). Default system red.
        var badgeColor: String? = nil
        /// Badge text color (hex). Default white.
        var badgeTextColor: String? = nil
        /// `style.glassAppearance`: the tab bar's glass, adaptive by default.
        var style: TabBarStyle? = nil
        /// `barStyle` (tab-bar-screen.md, Bar style): a text bar or a
        /// component template instead of the system items. Nil: system bar.
        var barStyle: BarStyle? = nil
        /// `selectionIndicatorColor`: the platform bar's selected-item highlight.
        /// Nil: black 10% on a light bar, white 10% on a dark one. Since 0.7.9.
        var selectionIndicatorColor: String? = nil

        struct TabBarStyle: Decodable, Sendable {
            var glassAppearance: DSL.Model.Style.GlassAppearance?
        }

        /// tab-bar-screen.md "Bar style". `text` / `selectedText` stay raw JSON:
        /// they are handed to the label components the bar renders, where the
        /// engine resolves them like any label style (style ids included).
        struct BarStyle: Decodable, Sendable {
            enum Variant: String, Decodable, Sendable { case system, text }
            enum Selection: String, Decodable, Sendable { case capsule, underline, box, opacity }
            /// `floating`: the platform's bar shape. `edge` (since 0.7.11): a
            /// full-width square stripe flush with the screen's bottom edge.
            enum Shape: String, Decodable, Sendable { case floating, edge }
            /// Where a badge sits: above the end of the label (`corner`) or
            /// after it on the same line (`inline`, since 0.7.11).
            enum BadgePlacement: String, Decodable, Sendable { case corner, inline }

            var variant: Variant = .system
            /// `glass` (default), `solid`, or the id of a fill / material style.
            var background: String = "glass"
            var selection: Selection = .capsule
            var text: AnyCodableValue?
            var selectedText: AnyCodableValue?
            var unselectedOpacity: Double = 0.5
            var indicatorColor: String?
            var height: Double?
            var shape: Shape = .floating
            /// Corners of an engine-drawn floating bar (default: half the height).
            var cornerRadius: Double?
            var badgePlacement: BadgePlacement = .corner
            /// Floating engine-drawn bar: points between its bottom edge and the
            /// bottom safe area (positive above, negative into the inset). nil: platform placement.
            var bottomOffset: Double?
            /// Floating engine-drawn bar: points from each screen edge. nil: platform (21).
            var sideInset: Double?
            /// A component template that draws the whole bar.
            var component: String?

            /// True when the engine draws the bar instead of the system items.
            var isCustom: Bool { component != nil || variant == .text }

            enum CodingKeys: String, CodingKey {
                case variant, background, selection, text, selectedText, unselectedOpacity, indicatorColor, height, component, shape, cornerRadius, badgePlacement, bottomOffset, sideInset
            }

            /// The engine draws the whole bar outside the system `UITabBar`: an
            /// `edge` stripe, or a `floating` bar with a non-glass background
            /// (tab-bar-screen.md, "Flat bars"). Glass stays the system bar.
            var isEngineDrawn: Bool { isCustom && (shape == .edge || background != "glass") }
            var isEdge: Bool { isCustom && shape == .edge }

            /// An engine-drawn bar's exact height: `height`, at least 28
            /// (unset: 49 for a stripe, 62, the iOS 26 platter, when floating).
            var drawnHeight: CGFloat { max(28, CGFloat(height ?? (shape == .edge ? 49 : 62))) }

            /// Corner radius of the engine-drawn bar: square for `edge`,
            /// `cornerRadius` (default half the height) when floating.
            var drawnCornerRadius: CGFloat {
                shape == .edge ? 0 : max(0, CGFloat(cornerRadius ?? Double(drawnHeight / 2)))
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                variant = (try? c.decodeIfPresent(Variant.self, forKey: .variant)) ?? .system
                background = (try? c.decodeIfPresent(String.self, forKey: .background)) ?? "glass"
                selection = (try? c.decodeIfPresent(Selection.self, forKey: .selection)) ?? .capsule
                text = try c.decodeIfPresent(AnyCodableValue.self, forKey: .text)
                selectedText = try c.decodeIfPresent(AnyCodableValue.self, forKey: .selectedText)
                unselectedOpacity = min(1, max(0, (try? c.decodeIfPresent(Double.self, forKey: .unselectedOpacity)) ?? 0.5))
                indicatorColor = try c.decodeIfPresent(String.self, forKey: .indicatorColor)
                height = try? c.decodeIfPresent(Double.self, forKey: .height)
                component = try c.decodeIfPresent(String.self, forKey: .component)
                shape = (try? c.decodeIfPresent(Shape.self, forKey: .shape)) ?? .floating
                cornerRadius = (try? c.decodeIfPresent(Double.self, forKey: .cornerRadius)) ?? nil
                badgePlacement = (try? c.decodeIfPresent(BadgePlacement.self, forKey: .badgePlacement)) ?? .corner
                bottomOffset = ((try? c.decodeIfPresent(Double.self, forKey: .bottomOffset)) ?? nil).flatMap { $0.isFinite && abs($0) <= 200 ? $0 : nil }
                sideInset = ((try? c.decodeIfPresent(Double.self, forKey: .sideInset)) ?? nil).flatMap { $0.isFinite && $0 >= 0 && $0 <= 200 ? $0 : nil }
            }
        }
    }

    // MARK: - Navigation Bar

    /// Navigation bar configuration for screens
    struct NavigationBar: Decodable, Sendable {
        /// Title displayed in the navigation bar (ignored when titleView is set)
        let title: String?
        /// Show `title` as an iOS large title (`prefersLargeTitles`) that
        /// collapses into the inline title as the content scrolls. Android
        /// ignores it (its variant is `topAppBar`).
        let largeTitle: Bool?
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
        /// Hide the back button on a pushed screen (the back swipe still
        /// works): a search screen whose field takes the back button's place.
        let hidesBackButton: Bool?
        /// Title text color (hex string)
        let titleColor: String?
        /// Bar button tint (back chevron, bar actions) as hex. Applied while
        /// this screen is on top; nil restores the system tint.
        let tintColor: String?
        /// iOS 26 scroll-edge effect under the bar (UIKit's own, over content
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
        /// `field` (default): the editable field. `button`: the same field,
        /// drawn by the system, that never takes focus; a tap runs `onTap`.
        let mode: Mode?
        /// `mode: "button"`: actions run on a tap (push the search screen).
        let onTap: [Action]?
        /// Focus the field (keyboard up, ✕ shown) once the screen appears.
        let autoFocus: Bool?
        /// Actions run when the user taps the cancel ✕.
        let onCancel: [Action]?

        enum Mode: String, SafeEnumCodable, Sendable {
            case field, button
            static let unknownCase: Mode = .field
        }

        var isButton: Bool { mode == .button }

        enum Placement: String, SafeEnumCodable, Sendable {
            case automatic, stacked, inline, integrated, integratedButton, integratedCentered
            static let unknownCase: Placement = .automatic
        }

        enum CodingKeys: String, CodingKey {
            case placeholder, bindVariable, placement, hidesWhenScrolling, tintColor, fillsBar, onSubmit
            case mode, onTap, autoFocus, onCancel
        }

        /// A single action or an array, like every other trigger.
        private static func actions(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [Action]? {
            if let list = try? c.decodeIfPresent([Action].self, forKey: key) { return list }
            return (try? c.decodeIfPresent(Action.self, forKey: key)).flatMap { $0.map { [$0] } }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
            bindVariable = try c.decodeIfPresent(String.self, forKey: .bindVariable)
            placement = try c.decodeIfPresent(Placement.self, forKey: .placement)
            hidesWhenScrolling = try c.decodeIfPresent(Bool.self, forKey: .hidesWhenScrolling)
            tintColor = try c.decodeIfPresent(String.self, forKey: .tintColor)
            fillsBar = try c.decodeIfPresent(Bool.self, forKey: .fillsBar)
            onSubmit = Self.actions(c, .onSubmit)
            mode = try c.decodeIfPresent(Mode.self, forKey: .mode)
            onTap = Self.actions(c, .onTap)
            autoFocus = try c.decodeIfPresent(Bool.self, forKey: .autoFocus)
            onCancel = Self.actions(c, .onCancel)
        }
    }

    /// Action for navigation bar buttons
    struct BarAction: Decodable, Sendable {
        /// Button label text (expression allowed, follows its variables)
        let label: String?
        /// SF Symbol icon name (expression allowed, follows its variables)
        let icon: String?
        /// The first action to execute when tapped
        var action: Action { actions[0] }
        /// Actions to execute when tapped, in order: `action` is a single action or an array
        let actions: [Action]
        /// Button style: "bold", "destructive"
        let style: String?
        /// Tint color override (hex string or color expression) — overrides style
        let color: String?

        enum CodingKeys: String, CodingKey { case label, icon, action, style, color }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            label = try c.decodeIfPresent(String.self, forKey: .label)
            icon = try c.decodeIfPresent(String.self, forKey: .icon)
            style = try c.decodeIfPresent(String.self, forKey: .style)
            color = try c.decodeIfPresent(String.self, forKey: .color)
            if let list = try? c.decode([Action].self, forKey: .action), !list.isEmpty {
                actions = list
            } else {
                actions = [try c.decode(Action.self, forKey: .action)]
            }
        }
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
