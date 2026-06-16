import Combine
import Foundation
import SafariServices
import UIKit

/// Abstract protocol for component view models - enables ViewModel reuse in collections
@MainActor
protocol ComponentViewModelAbstract: AnyObject {
    var variableStore: ScopedVariableStore { get }
    var componentPath: String { get }
}

protocol ComponentService: AnyObject, ComponentRenderer, A8.DataSourceHolder {
    @MainActor var componentRegistry: ComponentRegistry { get }
    @MainActor var appVariableStore: VariableStore { get }
    @MainActor var imageLoader: ImageLoader { get }
    @MainActor var context: App8Context { get }

    /// Resolve a template by name from the app's template registry
    @MainActor func resolveTemplate(named name: String) -> DSL.Model.Component.`Any`?
}

@MainActor
class CBaseViewModel<Component: DSL.Model.Component.EntityContent & DSL.Model.StatefulContent & DSL.Model.VariablesHolder & DSL.Model.EventTriggersHolder> {

    typealias Props = Component.Properties
    typealias State = Component.StateType

    let component: Component
    unowned let service: ComponentService

    /// Full hierarchical path for this component (e.g., "parent.child.grandchild")
    /// Used for scoped childStates resolution in template instances
    let componentPath: String

    /// Parent's component path (for sibling constraint resolution in ViewRegistry)
    /// e.g., if componentPath is "card-1.email-label", parentPath is "card-1"
    var parentPath: String? {
        guard let lastDot = componentPath.lastIndex(of: ".") else { return nil }
        return String(componentPath[..<lastDot])
    }

    // MARK: - Variable Store

    /// This component's variable store (scoped to parent)
    let variableStore: ScopedVariableStore

    /// Strong reference to parent variable store to prevent deallocation
    /// Needed when the parent store is not otherwise retained (e.g., screen params store)
    private var retainedParentStore: VariableStoreProtocol?

    private lazy var propertyResolver: PropertyResolver = PropertyResolver(
        translationStore: service.context.translationStore
    )

    /// Handler for variable actions
    private let variableActionHandler = VariableActionHandler()

    // MARK: - State Manager

    private(set) lazy var stateManager: ComponentStateManager<Component> = {
        let manager = ComponentStateManager(content: component)
        manager.delegate = self
        // Re-apply initial state now delegate is set, so childStates propagate.
        if let initialState = manager.currentStateNameValue {
            manager.setState(initialState, animated: false)
        }
        return manager
    }()

    private var cancellables = Set<AnyCancellable>()

    /// Active timers from onEvent triggers
    private var activeTimers: [Timer] = []

    var layout: AnyPublisher<DSL.Model.Layout?, Never> {
        stateManager.effectiveLayout
    }

    /// Layout combined with variable changes - use this for expression-based dimensions
    var layoutWithVariables: AnyPublisher<DSL.Model.Layout?, Never> {
        Publishers.CombineLatest(
            stateManager.effectiveLayout,
            variableStore.anyVariableChanged.prepend("").map { _ in () }
        )
        .map { layout, _ in layout }
        .eraseToAnyPublisher()
    }

    var style: AnyPublisher<Component.Style?, Never> {
        stateManager.effectiveStyle.eraseToAnyPublisher()
    }

    var properties: AnyPublisher<Component.Properties, Never> {
        stateManager.effectiveProperties
    }

    /// Properties combined with variable changes - use this to trigger re-resolution
    var propertiesWithVariables: AnyPublisher<Component.Properties, Never> {
        Publishers.CombineLatest(
            stateManager.effectiveProperties,
            variableStore.anyVariableChanged.prepend("").map { _ in () }
        )
        .map { props, _ in props }
        .eraseToAnyPublisher()
    }

    /// Fires when any variable in this component's scope changes
    var variablesChanged: AnyPublisher<String, Never> {
        variableStore.anyVariableChanged
    }

    var animation: AnyPublisher<DSL.Model.Animation?, Never> {
        stateManager.animation
    }

    var currentStyle: Component.Style? {
        stateManager.currentEffectiveStyle
    }

    var currentProperties: Component.Properties {
        stateManager.currentEffectiveProperties
    }

    // MARK: - Init

    init?(component: any DSL.Model.Component.Entity, service: ComponentService, componentPath: String, parentVariableStore: VariableStoreProtocol? = nil) {
        guard let c = component.content as? Component else {
            return nil
        }
        self.component = c
        self.service = service
        self.componentPath = componentPath

        let parent = parentVariableStore ?? service.appVariableStore
        let store = ScopedVariableStore(parent: parent)
        store.logger = service.context.logger
        self.variableStore = store
        self.variableActionHandler.logger = service.context.logger

        // appVariableStore is retained by service; an explicit parent is not, so retain it.
        if parentVariableStore != nil {
            self.retainedParentStore = parentVariableStore
        }

        if let variables = c.variables {
            service.context.logger.debug("Initializing \(variables.count) variables for component: \(componentPath)")

            var effectiveDefinitions: [String: VariableDefinition] = [:]
            for (name, definition) in variables {
                if definition.hasExternalSource,
                   let resolvedValue = parent.getValue(name: "__datasource_\(name)") {
                    effectiveDefinitions[name] = definition.withResolvedValue(resolvedValue)
                    service.context.logger.debug("Using resolved datasource for '\(name)'")
                } else if definition.initialValue == nil, !definition.hasExternalSource,
                          let injectedValue = parent.getValue(name: name) {
                    effectiveDefinitions[name] = definition.withResolvedValue(injectedValue)
                    service.context.logger.debug("Using injected param for '\(name)'")
                } else {
                    effectiveDefinitions[name] = definition
                    if definition.schema != nil, definition.initialValue == nil, !definition.hasExternalSource {
                        let hint = definition.preview != nil ? "preview datasource resolution failed — check earlier logs" : "pass it via the push action's 'params' or add a 'preview' to the variable definition"
                        service.context.logger.warning("Variable '\(name)' in '\(componentPath)' declares schema '\(definition.schema!)' but has no value after all resolution. It will be empty. Hint: \(hint).")
                    }
                }
            }

            do {
                try variableStore.defineVariables(effectiveDefinitions)
            } catch {
                service.context.logger.error("Failed to define variables for '\(componentPath)': \(error)")
            }
        }

        setupStateBinding()
        setup()
    }

    /// Override in children
    func setup() {

    }

    // MARK: - State Binding

    /// Set up reactive state binding if defaultStateName is an expression
    private func setupStateBinding() {
        guard let defaultState = component.defaultStateName else { return }
        guard defaultState.contains("{{") else { return }

        evaluateStateBinding(defaultState, animated: false)

        variableStore.anyVariableChanged
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.evaluateStateBinding(defaultState, animated: true)
            }
            .store(in: &cancellables)
    }

    /// Evaluate state expression and set the resulting state
    private func evaluateStateBinding(_ expression: String, animated: Bool) {
        let resolvedStateName = resolvePropertyToString(expression)
        if !resolvedStateName.isEmpty && resolvedStateName != currentStateName {
            setState(resolvedStateName, animated: animated)
        }
    }

    // MARK: - Variable Context

    /// Get a variable context for property resolution
    func getVariableContext() -> VariableContext {
        return VariableContext(store: variableStore)
    }

    /// Resolve a string property that may contain {{expressions}}
    func resolveProperty(_ value: String) -> Any {
        do {
            return try propertyResolver.resolve(value, context: getVariableContext())
        } catch {
            service.context.logger.error("Failed to resolve property '\(value)': \(error)")
            return value
        }
    }

    /// Resolve a `LocalizedString` to its user-facing string: i18n lookup (for
    /// `.key`) then `{{var}}` interpolation on the result.
    func resolveLocalizedToString(_ value: LocalizedString) -> String {
        do {
            return try propertyResolver.resolveLocalizedToString(value, context: getVariableContext())
        } catch {
            service.context.logger.error("Failed to resolve localized text '\(value.rawValue)': \(error)")
            return value.rawValue
        }
    }

    /// Resolve a string property to string (for text properties)
    func resolvePropertyToString(_ value: String) -> String {
        do {
            return try propertyResolver.resolveToString(value, context: getVariableContext())
        } catch {
            service.context.logger.error("Failed to resolve property '\(value)': \(error)")
            return value
        }
    }

    /// Resolve a string expression to a CGFloat (for layout dimensions)
    func resolvePropertyToFloat(_ value: String) -> CGFloat? {
        let resolved = resolveProperty(value)
        if let num = resolved as? Double {
            return CGFloat(num)
        } else if let num = resolved as? Int {
            return CGFloat(num)
        } else if let num = resolved as? NSNumber {
            return CGFloat(num.doubleValue)
        } else if let str = resolved as? String, let num = Double(str), num.isFinite {
            return CGFloat(num)
        }
        return nil
    }

    /// Resolve a string expression to a Bool (for visibility, etc.)
    func resolvePropertyToBool(_ value: String) -> Bool? {
        let resolved = resolveProperty(value)
        if let bool = resolved as? Bool {
            return bool
        } else if let num = resolved as? Int {
            return num != 0
        } else if let num = resolved as? Double {
            return num != 0
        } else if let str = resolved as? String {
            return str.lowercased() == "true" || str == "1"
        }
        return nil
    }

    // MARK: - Action Execution

    /// Execute a variable action
    func executeVariableAction(_ action: DSL.Model.Action) {
        try? variableActionHandler.execute(action: action, store: variableStore, context: getVariableContext())
    }

    /// Execute every action declared for `trigger` (in JSON order) and fire
    /// any author-declared analytics for the same trigger. Also auto-fires
    /// the built-in `app8.component.tapped` analytics event when applicable.
    func executeAction(for trigger: DSL.Model.ActionTrigger) {
        dispatchTrigger(trigger) { [self] action in executeAction(action) }
    }

    /// Fire analytics + author-declared bindings for `trigger`, then run each
    /// declared action via `execute`. Use this from any trigger dispatch site
    /// — including those that need scoped variable stores (e.g. cell taps,
    /// annotation taps, refresh, load-more, scroll threshold, text change) —
    /// so the analytics pipeline is never bypassed.
    func dispatchTrigger(
        _ trigger: DSL.Model.ActionTrigger,
        execute: (DSL.Model.Action) -> Void
    ) {
        fireTriggerAnalytics(for: trigger)
        guard let actions = component.actions?[trigger], !actions.isEmpty else { return }
        for action in actions { execute(action) }
    }

    /// Fire row-anchored tap analytics on behalf of a TableView row. Rows
    /// aren't full Component view models, so `fireTriggerAnalytics` (which
    /// attributes to the *enclosing* component) wouldn't tag events with the
    /// row's own id. Use this from the row-tap delegate site instead.
    func fireRowTapAnalytics(rowId: String, binding: DSL.Model.AnalyticsBinding?) {
        let config = service.context.analyticsConfig
        if config.autoComponentTaps {
            service.context.analyticsBus.dispatch(App8AnalyticsEvent(
                name: App8AnalyticsEvent.Auto.componentTapped,
                screenId: screenIdForEvents,
                componentId: rowId,
                componentType: "tableViewRow",
                locale: currentLocale,
                properties: [:]
            ))
        }
        if let binding {
            let resolved = resolvePayload(binding.properties)
            checkAuthorPropertyCollisions(resolved, bindingName: binding.name)
            service.context.analyticsBus.dispatch(App8AnalyticsEvent(
                name: normalizeAuthorAnalyticsName(binding.name),
                screenId: screenIdForEvents,
                componentId: rowId,
                componentType: "tableViewRow",
                locale: currentLocale,
                properties: resolved
            ))
        }
    }

    // MARK: - Analytics + Events helpers

    /// Component path's leaf segment — matches the `"id"` the author wrote
    /// on this component in the DSL JSON.
    private var leafComponentId: String? {
        guard let lastDot = componentPath.lastIndex(of: ".") else {
            return componentPath.isEmpty ? nil : componentPath
        }
        return String(componentPath[componentPath.index(after: lastDot)...])
    }

    /// DSL type token (`button`, `view`, `label`, `image`, etc.) for the
    /// component this view model wraps. The concrete view sets this at
    /// configure-time via `setComponentTypeKey(_:)`; the base type can't
    /// derive it from the generic `Component` parameter reliably enough
    /// for analytics.
    fileprivate(set) var componentTypeKey: String?

    /// Called by component view layer once during configure so analytics
    /// events can be tagged with the DSL type token.
    func setComponentTypeKey(_ key: String) {
        componentTypeKey = key
    }

    /// Resolve a `[String: AnyCodableValue]` against the variable scope:
    /// string values get `{{var}}` interpolation, other scalars pass through.
    /// Nested arrays/dicts are passed through unchanged (v1 limitation).
    fileprivate func resolvePayload(_ raw: [String: AnyCodableValue]?) -> [String: Any] {
        guard let raw else { return [:] }
        var resolved: [String: Any] = [:]
        for (key, codable) in raw {
            if let s = codable.value as? String {
                resolved[key] = resolveProperty(s)
            } else {
                resolved[key] = codable.value
            }
        }
        return resolved
    }

    /// Screen id this component is rendering inside, as the host knows it.
    ///
    /// The engine uses a flat dotted `componentPath` whose first segment IS
    /// the screen's identifier. That identifier is the **alias the host
    /// requested** — the value passed to `App8.Instance.renderScreen(screenId:)`
    /// or `App8Cloud.Instance.screen(id:)` — NOT the DSL document's internal
    /// `"id"` (which is irrelevant to the host and is typically a private
    /// dashboard label). This is the value stamped onto every `App8Event` and
    /// `App8AnalyticsEvent` so that `subscribe(onScreen: alias)` matches.
    ///
    /// Set by `App8Service.renderScreenSync` at render-root construction;
    /// see `screenRootId` there for the fallback rules.
    fileprivate var screenIdForEvents: String {
        if let dot = componentPath.firstIndex(of: ".") {
            return String(componentPath[..<dot])
        }
        return componentPath
    }

    /// Current translation locale, snapshotted at fire time. Read fresh each
    /// call so locale-switches mid-session show up in subsequent events.
    fileprivate var currentLocale: String {
        service.context.translationStore.activeLocale
    }

    /// Fire any author-declared analytics binding for this trigger, plus the
    /// engine's auto `app8.component.tapped` event when configured.
    private func fireTriggerAnalytics(for trigger: DSL.Model.ActionTrigger) {
        let config = service.context.analyticsConfig

        // Auto-fire app8.component.tapped on .tap when enabled.
        if trigger == .tap, config.autoComponentTaps {
            service.context.analyticsBus.dispatch(App8AnalyticsEvent(
                name: App8AnalyticsEvent.Auto.componentTapped,
                screenId: screenIdForEvents,
                componentId: leafComponentId,
                componentType: componentTypeKey,
                locale: currentLocale,
                properties: [:]
            ))
        }

        // Author-declared `analytics` binding for this trigger.
        if let binding = component.analytics?[trigger] {
            let resolved = resolvePayload(binding.properties)
            checkAuthorPropertyCollisions(resolved, bindingName: binding.name)
            service.context.analyticsBus.dispatch(App8AnalyticsEvent(
                name: normalizeAuthorAnalyticsName(binding.name),
                screenId: screenIdForEvents,
                componentId: leafComponentId,
                componentType: componentTypeKey,
                locale: currentLocale,
                properties: resolved
            ))
        }
    }

    /// Coerce an author-declared analytics binding name into the canonical
    /// `app8.<name>` form. Three cases:
    ///
    /// - **Already prefixed** (`"app8.foo"`): strip the leading `app8.`,
    ///   re-prepend, warn once. Idempotent — `"app8.foo"` always lands as
    ///   `"app8.foo"` regardless of how many times it bounces through here.
    /// - **Collides with reserved auto-event** (after prefix, e.g.
    ///   `"screen.appeared"`): dispatch under the canonical name and warn once.
    /// - **Otherwise** (`"stripeConnectClicked"`): prepend `app8.` →
    ///   `"app8.stripeConnectClicked"`.
    ///
    /// Empty post-strip names fall back to the raw input — defensive guard
    /// for the pathological `"app8."` case so we never produce an empty name.
    private func normalizeAuthorAnalyticsName(_ raw: String) -> String {
        let stripped: String
        let warnStripped: Bool
        if raw.hasPrefix("app8.") {
            stripped = String(raw.dropFirst("app8.".count))
            warnStripped = true
        } else {
            stripped = raw
            warnStripped = false
        }
        // Defensive: an author-supplied `"app8."` strips to empty — keep raw.
        guard !stripped.isEmpty else {
            warnOnce(
                key: "author-name:\(raw)",
                "analytics binding name '\(raw)' is empty after stripping reserved 'app8.' prefix; dispatching as '\(raw)' unchanged"
            )
            return raw
        }
        let canonical = "app8.\(stripped)"
        if warnStripped {
            warnOnce(
                key: "author-name:app8-prefix:\(raw)",
                "analytics binding name '\(raw)' has reserved 'app8.' prefix; SDK strips and re-prepends — dispatching as '\(canonical)'"
            )
        }
        if App8AnalyticsEvent.reservedNames.contains(canonical) {
            warnOnce(
                key: "author-name:reserved:\(canonical)",
                "analytics binding name '\(raw)' (normalised to '\(canonical)') collides with reserved auto-event name; dispatching anyway"
            )
        }
        return canonical
    }

    /// Warn once per instance if the author-resolved properties dict writes a
    /// key that the analytics bus will overwrite with SDK-canonical context
    /// (see `App8AnalyticsEvent.canonicalKeys`). SDK wins; this surfaces the
    /// silent overwrite so authors can rename their key.
    private func checkAuthorPropertyCollisions(_ resolved: [String: Any], bindingName: String) {
        guard !resolved.isEmpty else { return }
        for key in resolved.keys where App8AnalyticsEvent.canonicalKeys.contains(key) {
            warnOnce(
                key: "author-prop:\(bindingName):\(key)",
                "analytics binding '\(bindingName)' wrote property '\(key)' which is a reserved SDK-canonical key; SDK value will overwrite the author value"
            )
        }
    }

    /// Per-instance dedup wrapper around `logger.warning`. Each unique `key`
    /// fires exactly one warning across the lifetime of an `App8.Instance` —
    /// the same colliding binding firing 100 times produces one log line.
    private func warnOnce(key: String, _ message: @autoclosure () -> String) {
        if service.context.warnedNames.insert(key).inserted {
            service.context.logger.warning(message())
        }
    }

    // MARK: - State API

    /// Transition to a named state
    func setState(_ stateName: String?, animated: Bool = true) {
        stateManager.setState(stateName, animated: animated)
    }

    /// Force re-apply a state (even if it's the current state)
    /// Used after children are rendered to propagate childStates
    func forceReapplyState(_ stateName: String) {
        stateManager.setState(stateName, animated: false, force: true)
    }

    /// Get current state name
    var currentStateName: String? {
        stateManager.currentStateNameValue
    }

    // MARK: - Trigger API

    /// Fire a trigger - looks up state name in component.triggers
    func fireTrigger(_ trigger: DSL.Model.Trigger) {
        guard let triggers = component.triggers,
              let stateName = triggers[trigger] else { return }
        setState(stateName, animated: true)
    }

    // MARK: - Event Triggers (onEvent)

    /// Start event triggers defined in onEvent array
    func startEventTriggers() {
        guard let events = component.onEvent else { return }

        for event in events {
            switch event.event {
            case .timer:
                startTimer(for: event)
            case .appear:
                executeAction(event.action)
            case .disappear:
                break // handled by cancelEventTriggers
            }
        }
    }

    /// Cancel all active event triggers
    func cancelEventTriggers() {
        // Fire disappear events before cancelling.
        if let events = component.onEvent {
            for event in events where event.event == .disappear {
                executeAction(event.action)
            }
        }

        for timer in activeTimers {
            timer.invalidate()
        }
        activeTimers.removeAll()
    }

    /// Start a timer for a timer event
    private func startTimer(for event: DSL.Model.EventTrigger) {
        let initialDelay = event.delay ?? 0
        let repeats = event.repeats ?? false
        let interval = event.interval ?? event.delay ?? 1.0
        let action = event.action

        if initialDelay == 0 {
            executeAction(action)

            if repeats {
                let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
                    guard let self = self else {
                        timer.invalidate()
                        return
                    }
                    Task { @MainActor in
                        self.executeAction(action)
                    }
                }
                activeTimers.append(timer)
            }
        } else {
            let timer = Timer.scheduledTimer(withTimeInterval: initialDelay, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.executeAction(action)

                    if repeats && !self.activeTimers.isEmpty {
                        let repeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
                            guard let self = self else {
                                timer.invalidate()
                                return
                            }
                            Task { @MainActor in
                                self.executeAction(action)
                            }
                        }
                        self.activeTimers.append(repeatTimer)
                    }
                }
            }
            activeTimers.append(timer)
        }
    }

    /// Expand an action's transition reference into its concrete resolved form,
    /// resolving any animation pointer against the app animation registry.
    private func resolveTransition(_ transition: DSL.Model.ScreenTransition?) -> DSL.Model.ScreenTransition.Resolved? {
        guard let transition, let inline = transition.inlineOrNil else { return nil }
        let animationResolver = service.context.animationResolver ?? { _ in nil }
        return DSL.Model.ScreenTransition.resolve(inline, animationResolver: animationResolver)
    }

    /// Execute an action directly (for event triggers)
    func executeAction(_ action: DSL.Model.Action) {
        switch action.type {
        case .updateVariable, .incrementVariable, .updateMultipleVariables, .resetVariables, .toggleArrayValue, .appendToArray:
            executeVariableAction(action)

        case .setState:
            if let stateName = action.stateName {
                let animated = action.animated ?? true
                let resolvedStateName = resolvePropertyToString(stateName)
                setState(resolvedStateName, animated: animated)
            }

        case .navigation:
            // Post the navigation request first so the analytics event only
            // fires for navigations that actually got dispatched.
            var didPost = false
            if action.isBack == true {
                let request = NavigationRequest(type: action.toRoot == true ? .popToRoot : .pop)
                NotificationCenter.default.post(name: .app8NavigationRequest, object: request)
                didPost = true
            } else if let nextScreen = action.nextScreen {
                var resolvedParams: [String: Any] = [:]
                if let params = action.params {
                    for (key, value) in params {
                        if let stringValue = value.value as? String {
                            resolvedParams[key] = resolveProperty(stringValue)
                        } else {
                            resolvedParams[key] = value.value
                        }
                    }
                }

                // Resolve the action-level transition. `mode` decides the route
                // when the transition is custom; an explicit `.system` opts out
                // (and suppresses screen/app defaults downstream).
                let actionTransition = resolveTransition(action.transition)

                if let actionTransition, actionTransition.kind != .system, actionTransition.mode == .modal {
                    // Custom modal — engine-driven transition replaces the system modal.
                    let request = NavigationRequest(
                        type: .presentModal(
                            screenId: nextScreen,
                            params: resolvedParams,
                            style: .custom,
                            detents: action.detents,
                            grabber: action.grabber
                        ),
                        transition: actionTransition
                    )
                    NotificationCenter.default.post(name: .app8NavigationRequest, object: request)
                } else if let presentation = action.presentation, presentation != .push {
                    // System modal (sheet / fullScreen / …). Native animation.
                    let modalStyle = presentation.toModalPresentationStyle
                    let request = NavigationRequest(type: .presentModal(
                        screenId: nextScreen,
                        params: resolvedParams,
                        style: modalStyle,
                        detents: action.detents,
                        grabber: action.grabber
                    ))
                    NotificationCenter.default.post(name: .app8NavigationRequest, object: request)
                } else {
                    // Push. A nil transition lets the container apply the screen/app default.
                    let request = NavigationRequest(
                        type: .push(screenId: nextScreen, params: resolvedParams),
                        transition: actionTransition
                    )
                    NotificationCenter.default.post(name: .app8NavigationRequest, object: request)
                }
                didPost = true
            }
            if didPost, service.context.analyticsConfig.autoNavigationEvents {
                // `from_screen_alias` / `to_screen_alias` (not `_id`): these
                // are the host-facing aliases that DSL/host code passes in,
                // not the DSL document's internal id. The engine has no
                // reverse alias→DSL-id map at navigation time and shouldn't
                // pretend to.
                var properties: [String: Any] = [
                    "from_screen_alias": screenIdForEvents
                ]
                if let nextScreen = action.nextScreen {
                    properties["to_screen_alias"] = nextScreen
                }
                if let presentation = action.presentation {
                    properties["presentation"] = presentation.rawValue
                }
                if action.isBack == true { properties["is_back"] = true }
                service.context.analyticsBus.dispatch(App8AnalyticsEvent(
                    name: App8AnalyticsEvent.Auto.navigationPushed,
                    screenId: screenIdForEvents,
                    componentId: leafComponentId,
                    componentType: componentTypeKey,
                    locale: currentLocale,
                    properties: properties
                ))
            }

        case .completeFlow:
            if let destination = action.destination {
                let request = NavigationRequest(type: .completeFlow(destination: destination))
                NotificationCenter.default.post(name: .app8NavigationRequest, object: request)
            }

        case .dismiss:
            let request = NavigationRequest(type: .dismiss)
            NotificationCenter.default.post(name: .app8NavigationRequest, object: request)

        case .selectTab:
            let request = NavigationRequest(type: .selectTab(index: action.tabIndex, id: action.tabId))
            NotificationCenter.default.post(name: .app8NavigationRequest, object: request)

        case .focus:
            if let targetId = action.target {
                let fullPath = targetId.contains(".") ? targetId : "\(componentPath).\(targetId)"
                service.context.focusManager.focus(id: fullPath)
            }

        case .focusNext:
            service.context.focusManager.focusNext()

        case .focusPrevious:
            service.context.focusManager.focusPrevious()

        case .dismissKeyboard:
            service.context.focusManager.dismissKeyboard()

        case .showAlert:
            let title = action.alertTitle.map { resolvePropertyToString($0) }
            let message = action.alertMessage.map { resolvePropertyToString($0) }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

            if let alertActions = action.alertActions {
                for alertAction in alertActions {
                    let style: UIAlertAction.Style
                    switch alertAction.style {
                    case .cancel: style = .cancel
                    case .destructive: style = .destructive
                    default: style = .default
                    }
                    alert.addAction(UIAlertAction(title: alertAction.title, style: style) { [weak self] _ in
                        if let followUp = alertAction.action {
                            self?.executeAction(followUp)
                        }
                    })
                }
            } else {
                alert.addAction(UIAlertAction(title: "OK", style: .default))
            }

            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.keyWindow?.rootViewController {
                var top = root
                while let presented = top.presentedViewController { top = presented }
                top.present(alert, animated: true)
            }

        case .haptic:
            switch action.hapticStyle ?? .medium {
            case .light:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .medium:
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .heavy:
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .warning:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            case .error:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            case .selection:
                UISelectionFeedbackGenerator().selectionChanged()
            }

        case .openURL:
            if let urlString = action.url {
                let resolved = resolvePropertyToString(urlString)
                if service.context.analyticsConfig.autoUrlEvents {
                    service.context.analyticsBus.dispatch(App8AnalyticsEvent(
                        name: App8AnalyticsEvent.Auto.urlOpened,
                        screenId: screenIdForEvents,
                        componentId: leafComponentId,
                        componentType: componentTypeKey,
                        locale: currentLocale,
                        properties: ["url": resolved]
                    ))
                }
                if let url = URL(string: resolved) {
                    let presentation = action.urlPresentation ?? .external
                    // SFSafariViewController only supports http/https. Non-web URLs (tel:, mailto:, etc.)
                    // always fall back to the system handler regardless of requested presentation.
                    let isWebURL = (url.scheme == "http" || url.scheme == "https")
                    if presentation == .external || !isWebURL {
                        UIApplication.shared.open(url)
                    } else {
                        let safariVC = SFSafariViewController(url: url)
                        safariVC.modalPresentationStyle = (presentation == .fullScreen) ? .fullScreen : .pageSheet
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let root = scene.keyWindow?.rootViewController {
                            var top = root
                            while let presented = top.presentedViewController { top = presented }
                            top.present(safariVC, animated: true)
                        }
                    }
                }
            }

        case .emit:
            guard let eventName = action.name, !eventName.isEmpty else {
                service.context.logger.warning("Action .emit missing `name` — dropped. componentPath='\(componentPath)'")
                return
            }
            let resolved = resolvePayload(action.payload)
            service.context.eventBus.dispatch(App8Event(
                name: eventName,
                screenId: screenIdForEvents,
                componentId: leafComponentId,
                componentType: componentTypeKey,
                locale: currentLocale,
                payload: resolved
            ))

        case .executeFunction, .complete:
            break
        }
    }
}

// MARK: - ComponentStateManagerDelegate

extension CBaseViewModel: ComponentStateManagerDelegate {
    func stateManagerDidRequestChildStates(_ childStates: [String: String], animated: Bool) {
        // Resolve child IDs to full paths by prepending this component's path.
        let resolvedStates = Dictionary(uniqueKeysWithValues: childStates.map { key, value in
            ("\(componentPath).\(key)", value)
        })
        service.componentRegistry.setStates(resolvedStates, animated: animated)
    }
}

// MARK: - StateControllable

extension CBaseViewModel: StateControllable {}

// MARK: - ComponentViewModelAbstract

extension CBaseViewModel: ComponentViewModelAbstract {}
