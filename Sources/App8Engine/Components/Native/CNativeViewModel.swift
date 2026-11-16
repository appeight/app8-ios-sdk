//
//  CNativeViewModel.swift
//  App8Engine
//

import Combine
import Foundation

final class CNativeViewModel: CBaseViewModel<NativeContent> {

    var module: String { currentProperties.module }

    /// Event names the engine owns (visibility); a module can't emit them.
    static let reservedEvents: Set<String> = ["appear", "disappear"]

    /// `properties.props` with every string leaf resolved against this
    /// component's scope.
    func resolvedProps() -> [String: Any] {
        guard let props = currentProperties.props else { return [:] }
        let context = getVariableContext()
        return props.mapValues { resolve($0, context: context) }
    }

    private func resolve(_ value: JSONValue, context: VariableContext) -> Any {
        switch value {
        case .string(let s):
            return s.contains("{{") ? resolveProperty(s, context: context) : s
        case .number(let n):
            return n
        case .bool(let b):
            return b
        case .null:
            return NSNull()
        case .array(let items):
            return items.map { resolve($0, context: context) }
        case .object(let dict):
            return dict.mapValues { resolve($0, context: context) }
        }
    }

    /// A module event: forward it to the event bus as
    /// `native.<module>.<event>`, then run `actions[event]` with the payload
    /// in scope as `event`.
    func handleModuleEvent(_ event: String, payload: [String: Any]) {
        guard !Self.reservedEvents.contains(event) else {
            service.context.logger.warning(
                "native.event.reserved: module '\(module)' emitted '\(event)' at '\(componentPath)' — 'appear' and 'disappear' are the engine's visibility events; ignored"
            )
            return
        }
        dispatchToEventBus(name: "native.\(module).\(event)", payload: payload)
        if let binding = component.eventAnalytics[event] {
            fireAnalyticsBinding(binding, context: getVariableContext().overlaying("event", value: payload))
        }
        guard let actions = component.eventActions[event], !actions.isEmpty else { return }
        executeActions(actions, scope: ["event": payload], label: "native '\(module)' \(event)")
    }

    /// `actions.appear` / `actions.disappear` (and their analytics bindings)
    /// when the component becomes visible / stops being visible. Payload empty.
    func handleVisibilityChange(_ visible: Bool) {
        let event = visible ? "appear" : "disappear"
        if let binding = component.eventAnalytics[event] {
            fireAnalyticsBinding(binding, context: getVariableContext().overlaying("event", value: [String: Any]()))
        }
        guard let actions = component.eventActions[event], !actions.isEmpty else { return }
        executeActions(actions, scope: ["event": [String: Any]()], label: "native '\(module)' \(event)")
    }

    /// Builds the context handed to the host factory.
    func makeNativeContext() -> App8NativeContext {
        App8NativeContext(
            module: module,
            appId: service.context.appId,
            screenId: screenIdForEvents,
            props: resolvedProps(),
            emit: { [weak self] event, payload in
                self?.handleModuleEvent(event, payload: payload)
            }
        )
    }
}
