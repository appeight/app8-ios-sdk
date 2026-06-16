import Foundation

extension DSL.Model.Component {
    typealias M = DSL.Model

    struct Content<Properties: Decodable & Sendable, StyleContent: Decodable & Sendable>: EntityContent, M.StatefulContent, M.VariablesHolder, M.EventTriggersHolder {
        typealias StateType = M.State<Properties, StyleContent>

        let properties: Properties
        var style: StyleContent?
        let layout: M.Layout?
        let actions: [M.ActionTrigger: [M.Action]]?
        let analytics: [M.ActionTrigger: M.AnalyticsBinding]?

        /// Default state name - can be static ("normal") or expression ("{{condition ? 'a' : 'b'}}")
        let defaultStateName: String?
        var states: [String: M.State<Properties, StyleContent>]?
        let triggers: [M.Trigger: String]?

        let variables: [String: VariableDefinition]?

        /// Navigation bar configuration (for screens only)
        let navigationBar: M.NavigationBar?

        /// Per-component transition context. On a **screen root** this is the
        /// screen's default `ScreenTransition` (used when navigating *to* this
        /// screen and the navigation action declares no transition of its own;
        /// overridden by an action-level transition, overrides the app default).
        /// On a **child component** this is an `ElementTransition` participation
        /// context (a matching `key`) for shared-element transitions. See
        /// `M.ComponentTransition`.
        let transition: M.ComponentTransition?

        /// Whether to hide the tab bar when this screen is pushed (for screens only)
        let hidesTabBar: Bool?

        /// Whether tapping outside text inputs dismisses the keyboard (for screens only)
        let dismissKeyboardOnTap: Bool?

        /// When true, ScreenViewController starts a StreamingSession after initial render (for screens only)
        let streaming: Bool?

        /// Additional safe area insets contributed by this component to its parent screen (optional)
        let additionalSafeAreaInsets: M.EdgeInsets?

        let onEvent: [M.EventTrigger]?

        @SafeArrayDecodable
        var children: [`Any`] = []

        mutating func resolveStateStylePointers(resolver: (String) -> (any M.Style.Entity)?) {
            guard var statesDict = states else { return }
            for (stateName, var state) in statesDict {
                if var stateStyle = state.style as? M.Style.StylePointerResolvable {
                    stateStyle.resolveStylePointers(resolver: resolver)
                    state.setResolvedStyle(stateStyle)
                    statesDict[stateName] = state
                }
            }
            states = statesDict
        }

        enum CodingKeys: CodingKey {
            case properties
            case style
            case layout
            case actions
            case analytics
            case defaultStateName
            case states
            case triggers
            case variables
            case navigationBar
            case transition
            case hidesTabBar
            case dismissKeyboardOnTap
            case streaming
            case additionalSafeAreaInsets
            case onEvent
            case children
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let propertiesType = Properties.self as? CustomDecodable.Type {
                let decoded = try propertiesType.decode(fromContainer: c, key: .properties)
                guard let typed = decoded as? Properties else {
                    throw DecodingError.typeMismatch(
                        Properties.self,
                        DecodingError.Context(
                            codingPath: c.codingPath + [CodingKeys.properties],
                            debugDescription: "CustomDecodable returned \(type(of: decoded)), expected \(Properties.self)"
                        )
                    )
                }
                properties = typed
            } else if let decoded = try c.decodeIfPresent(Properties.self, forKey: .properties) {
                properties = decoded
            } else {
                properties = try JSONDecoder().decode(Properties.self, from: Data("{}".utf8))
            }
            if let styleType = StyleContent.self as? CustomDecodable.Type {
                let decoded = try styleType.decode(fromContainer: c, key: .style)
                guard let typed = decoded as? StyleContent else {
                    throw DecodingError.typeMismatch(
                        StyleContent.self,
                        DecodingError.Context(
                            codingPath: c.codingPath + [CodingKeys.style],
                            debugDescription: "CustomDecodable returned \(type(of: decoded)), expected \(StyleContent.self)"
                        )
                    )
                }
                style = typed
            } else {
                style = try c.decodeIfPresent(StyleContent.self, forKey: .style)
            }
            
            layout           = try c.decodeIfPresent(M.Layout.self, forKey: .layout)
            if let rawActions = try c.decodeIfPresent([String: M.ActionList].self, forKey: .actions) {
                var converted: [M.ActionTrigger: [M.Action]] = [:]
                for (key, value) in rawActions {
                    if let trigger = M.ActionTrigger(rawValue: key) {
                        converted[trigger] = value.actions
                    }
                }
                actions = converted.isEmpty ? nil : converted
            } else {
                actions = nil
            }
            if let rawAnalytics = try c.decodeIfPresent([String: M.AnalyticsBinding].self, forKey: .analytics) {
                var converted: [M.ActionTrigger: M.AnalyticsBinding] = [:]
                for (key, value) in rawAnalytics {
                    if let trigger = M.ActionTrigger(rawValue: key) {
                        converted[trigger] = value
                    }
                }
                analytics = converted.isEmpty ? nil : converted
            } else {
                analytics = nil
            }
            defaultStateName = try c.decodeIfPresent(String.self, forKey: .defaultStateName)
            states           = try c.decodeIfPresent([String: M.State<Properties, StyleContent>].self, forKey: .states)
            variables        = try c.decodeIfPresent([String: VariableDefinition].self, forKey: .variables)
            navigationBar    = try c.decodeIfPresent(M.NavigationBar.self, forKey: .navigationBar)
            transition       = try c.decodeIfPresent(M.ComponentTransition.self, forKey: .transition)
            hidesTabBar      = try c.decodeIfPresent(Bool.self, forKey: .hidesTabBar)
            dismissKeyboardOnTap = try c.decodeIfPresent(Bool.self, forKey: .dismissKeyboardOnTap)
            streaming        = try c.decodeIfPresent(Bool.self, forKey: .streaming)
            additionalSafeAreaInsets = try c.decodeIfPresent(M.EdgeInsets.self, forKey: .additionalSafeAreaInsets)
            onEvent          = try c.decodeIfPresent([M.EventTrigger].self, forKey: .onEvent)

            if let rawTriggers = try c.decodeIfPresent([String: String].self, forKey: .triggers) {
                var converted: [M.Trigger: String] = [:]
                for (key, value) in rawTriggers {
                    if let trigger = M.Trigger(rawValue: key) {
                        converted[trigger] = value
                    }
                }
                triggers = converted.isEmpty ? nil : converted
            } else {
                triggers = nil
            }

            if let children = try c.decodeIfPresent(SafeArrayDecodable<`Any`>.self, forKey: .children) {
                _children = children
            }
        }
    }
}
