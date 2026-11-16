//
//  Native.swift
//  App8Engine
//
//  `native` component: a host-registered native view (signature pad, video call, …) embedded
//  in a DSL screen. See `App8.registerNativeComponent(_:factory:)`.
//

import Foundation

extension DSL.Model.Component {

    struct Native {
        typealias C = NativeContent
        typealias Entity = ConcreteEntity<C>

        struct Properties: Decodable, Sendable {
            /// Name the host registered the factory under, e.g. `"signaturePad"`.
            let module: String
            /// Values handed to the host view. String leaves may hold `{{expr}}`
            /// and are re-resolved when the variables they read change.
            let props: [String: JSONValue]?
        }
    }
}

/// Content of a `native` component.
///
/// Differs from `Content<P, S>` in two ways:
/// - `actions` keys are the module's own event names (`completed`,
///   `cancelled`, …), not engine `ActionTrigger`s, so they are kept as
///   strings in `eventActions`.
/// - `fallback` is a DSL subtree rendered when no host factory is registered.
///   It is stored as the only child so template / style pointer resolution
///   and the diagnostics walkers reach it like any other child.
struct NativeContent: DSL.Model.Component.EntityContent, DSL.Model.StatefulContent, DSL.Model.VariablesHolder, DSL.Model.EventTriggersHolder {
    typealias Properties = DSL.Model.Component.Native.Properties
    typealias Style = DSL.Model.Style.View
    typealias StateType = DSL.Model.State<Properties, Style>

    let properties: Properties
    var style: Style?
    let layout: DSL.Model.Layout?

    /// Always nil: native events are not engine triggers. See `eventActions`
    /// and `eventAnalytics`.
    let actions: [DSL.Model.ActionTrigger: [DSL.Model.Action]]?
    let analytics: [DSL.Model.ActionTrigger: DSL.Model.AnalyticsBinding]?

    /// Actions keyed by the module's event name.
    let eventActions: [String: [DSL.Model.Action]]

    /// Analytics bindings keyed by the module's event name (`analytics`).
    let eventAnalytics: [String: DSL.Model.AnalyticsBinding]

    let defaultStateName: String?
    var states: [String: StateType]?
    let triggers: [DSL.Model.Trigger: String]?
    let variables: [String: VariableDefinition]?
    let onEvent: [DSL.Model.EventTrigger]?
    let interaction: DSL.Model.Interaction?
    let accessibility: DSL.Model.Accessibility?
    let hiddenFlag: String?
    let hiddenAnimation: DSL.Model.Animation?

    /// `[fallback]` when declared, else empty.
    var children: [DSL.Model.Component.`Any`] = []

    /// Subtree shown when no factory is registered for `properties.module`.
    var fallback: DSL.Model.Component.`Any`? { children.first }

    enum CodingKeys: String, CodingKey {
        case properties, style, layout, actions, analytics, defaultStateName, states, triggers, variables, onEvent, interaction, accessibility, fallback
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        properties = try c.decode(Properties.self, forKey: .properties)
        hiddenFlag = HiddenFlagDecoding.decode(from: c, propertiesKey: .properties)
        hiddenAnimation = HiddenFlagDecoding.decodeAnimation(from: c, propertiesKey: .properties)
        style = try Style.decode(fromContainer: c, key: .style)
        layout = try c.decodeIfPresent(DSL.Model.Layout.self, forKey: .layout)

        var eventActions: [String: [DSL.Model.Action]] = [:]
        if let raw = try c.decodeIfPresent([String: DSL.Model.ActionList].self, forKey: .actions) {
            for (event, list) in raw where !list.actions.isEmpty {
                eventActions[event] = list.actions
            }
        }
        self.eventActions = eventActions
        eventAnalytics = try c.decodeIfPresent([String: DSL.Model.AnalyticsBinding].self, forKey: .analytics) ?? [:]
        actions = nil
        analytics = nil

        defaultStateName = try c.decodeIfPresent(String.self, forKey: .defaultStateName)
        states = try c.decodeIfPresent([String: StateType].self, forKey: .states)
        variables = try c.decodeIfPresent([String: VariableDefinition].self, forKey: .variables)
        onEvent = try c.decodeIfPresent([DSL.Model.EventTrigger].self, forKey: .onEvent)
        interaction = try c.decodeIfPresent(DSL.Model.Interaction.self, forKey: .interaction)
        accessibility = try c.decodeIfPresent(DSL.Model.Accessibility.self, forKey: .accessibility)

        if let rawTriggers = try c.decodeIfPresent([String: String].self, forKey: .triggers) {
            var converted: [DSL.Model.Trigger: String] = [:]
            for (key, value) in rawTriggers {
                if let trigger = DSL.Model.Trigger(rawValue: key) { converted[trigger] = value }
            }
            triggers = converted.isEmpty ? nil : converted
        } else {
            triggers = nil
        }

        if let fallback = try c.decodeIfPresent(DSL.Model.Component.`Any`.self, forKey: .fallback) {
            children = [fallback]
        }
    }

    mutating func resolveStateStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
        guard var statesDict = states else { return }
        for (stateName, var state) in statesDict {
            if var stateStyle = state.style {
                stateStyle.resolveStylePointers(resolver: resolver)
                state.setResolvedStyle(stateStyle)
                statesDict[stateName] = state
            }
        }
        states = statesDict
    }
}
