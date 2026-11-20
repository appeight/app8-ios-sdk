import Combine
import Foundation
import SafariServices
import UIKit

/// Abstract protocol for component view models - enables ViewModel reuse in collections
@MainActor
protocol ComponentViewModelAbstract: AnyObject {
    var variableStore: ScopedVariableStore { get }
    var componentPath: String { get }

    /// Fires when any variable in this component's scope changes. Lets the shared
    /// common-property binder re-resolve `interaction` / `accessibility` reactively.
    var variablesChanged: AnyPublisher<String, Never> { get }

    /// Universal interaction overrides declared on this component's content.
    var interactionProps: DSL.Model.Interaction? { get }
    /// Universal accessibility metadata declared on this component's content.
    var accessibilityProps: DSL.Model.Accessibility? { get }
    /// `properties.isHidden` (any component type), from the current state
    /// when it declares one, else the base content.
    var hiddenFlag: String? { get }
    /// The `animation` of a wrapped `properties.isHidden` (the current
    /// state's when it declares the flag, else the base content's). Nil: a
    /// change applies at once.
    var hiddenAnimation: DSL.Model.Animation.Inline? { get }
    /// Fires when the component's state changes (state-aware `isHidden`).
    var stateChanged: AnyPublisher<Void, Never> { get }
    /// True when a state of this component declares `properties.isHidden`.
    var declaresStateHiddenFlag: Bool { get }

    func resolvePropertyToBool(_ value: String) -> Bool?
    func resolvePropertyToFloat(_ value: String) -> CGFloat?
    func resolvePropertyToString(_ value: String) -> String

    /// `content.contextMenu` declared on this component.
    var contextMenuProps: DSL.Model.ContextMenu? { get }
    /// The service that rendered this component (context-menu previews render through it).
    var componentService: ComponentService? { get }
    /// Runs context-menu item / preview-tap actions in this component's scope.
    func executeContextMenuActions(_ actions: [DSL.Model.Action])
}

/// Defaults for lightweight conformers (e.g. `CellVariableStoreWrapper`) that
/// exist only for caching and never carry component content / a property
/// resolver. `CBaseViewModel` provides real implementations that take precedence
/// as the protocol witnesses.
extension ComponentViewModelAbstract {
    var variablesChanged: AnyPublisher<String, Never> { variableStore.anyVariableChanged }
    var interactionProps: DSL.Model.Interaction? { nil }
    var accessibilityProps: DSL.Model.Accessibility? { nil }
    var hiddenFlag: String? { nil }
    var hiddenAnimation: DSL.Model.Animation.Inline? { nil }
    var stateChanged: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var declaresStateHiddenFlag: Bool { false }
    func resolvePropertyToBool(_ value: String) -> Bool? { nil }
    func resolvePropertyToFloat(_ value: String) -> CGFloat? { nil }
    func resolvePropertyToString(_ value: String) -> String { value }
    var contextMenuProps: DSL.Model.ContextMenu? { nil }
    var componentService: ComponentService? { nil }
    func executeContextMenuActions(_ actions: [DSL.Model.Action]) {}
}

protocol ComponentService: AnyObject, ComponentRenderer, A8.DataSourceHolder {
    @MainActor var componentRegistry: ComponentRegistry { get }
    @MainActor var appVariableStore: VariableStore { get }
    @MainActor var imageLoader: ImageLoader { get }
    @MainActor var context: App8Context { get }

    /// Resolve a template by name from the app's template registry
    @MainActor func resolveTemplate(named name: String) -> DSL.Model.Component.`Any`?

    /// Records that `name` in `store` is fed by datasource `source`.
    @MainActor func registerDatasourceBinding(source: String, name: String, type: VariableType, store: VariableStoreProtocol)
    /// Refetches `source` and updates every variable bound to it; false on failure.
    @MainActor func reloadDatasource(_ source: String, screenId: String) async -> Bool
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

    /// The effective style with its color expressions resolved in this
    /// component's scope. A style that has color expressions re-emits when a
    /// variable changes and a resolved color differs.
    var style: AnyPublisher<Component.Style?, Never> {
        stateManager.effectiveStyle
            .map { [weak self] style -> AnyPublisher<Component.Style?, Never> in
                guard let self, let style else { return Just(style).eraseToAnyPublisher() }
                let first = self.resolveColorExpressions(in: style)
                guard !first.signature.isEmpty else { return Just(style).eraseToAnyPublisher() }
                return self.variableStore.anyVariableChanged
                    .map { [weak self] _ in self?.resolveColorExpressions(in: style) ?? (style, "") }
                    .prepend(first)
                    .removeDuplicates { $0.signature == $1.signature }
                    .map { Optional($0.style) }
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    /// Resolves every color expression in `style` against this component's
    /// scope. `signature` lists the resolved colors (empty when the style has
    /// no expressions). A result that is not a hex color leaves the field
    /// unset and logs `style.color.invalid`.
    func resolveColorExpressions(in style: Component.Style) -> (style: Component.Style, signature: String) {
        // Component-specific color fields (toggle `onTintColor`, slider tints,
        // …) are plain strings resolved at apply time by `resolveColor(_:)`;
        // their results join the signature so the style re-emits when they change.
        var signature = Self.colorExpressionStrings(in: style)
            .map { "\($0)=\(resolvePropertyToString($0));" }
            .joined()
        guard var resolvable = style as? DSL.Model.Style.StylePointerResolvable else { return (style, signature) }
        resolvable.resolveStylePointers { [self] id in
            guard DSL.Model.Style.`Any`.isColorExpression(id) else { return nil }
            let value = resolvePropertyToString(id).trimmingCharacters(in: .whitespacesAndNewlines)
            signature += "\(id)=\(value);"
            guard DSL.Model.Style.Color.Hex.isValidHexString(value),
                  let color = UIColor(withHexString: value) else {
                warnOnce(key: "style.color.invalid:\(componentPath):\(id):\(value)",
                         "style.color.invalid: '\(id)' resolved to '\(value)', not a hex color — field left unset. componentPath='\(componentPath)'")
                return nil
            }
            return DSL.Model.Style.ConcreteEntity<DSL.Model.Style.Color.Themed>(
                DSL.Model.Style.Pointer(id: id, type: .key(.color), typeSpecified: true),
                content: DSL.Model.Style.Color.Themed(color)
            )
        }
        guard let resolved = resolvable as? Component.Style else { return (style, signature) }
        return (resolved, signature)
    }

    /// Plain string fields of `style` that hold a color expression, found by
    /// reflection (Wrapped color fields are handled as pointers instead).
    private static func colorExpressionStrings(in style: Any) -> [String] {
        var found: [String] = []
        func walk(_ value: Any, depth: Int) {
            guard depth < 6 else { return }
            for child in Mirror(reflecting: value).children {
                guard let label = child.label, !label.hasPrefix("_") else { continue }
                let unwrapped: Any? = Mirror(reflecting: child.value).displayStyle == .optional
                    ? Mirror(reflecting: child.value).children.first?.value : child.value
                guard let unwrapped else { continue }
                if let string = unwrapped as? String {
                    if label.lowercased().contains("color"),
                       DSL.Model.Style.`Any`.isColorExpression(string) {
                        found.append(string)
                    }
                } else if Mirror(reflecting: unwrapped).displayStyle == .struct {
                    walk(unwrapped, depth: depth + 1)
                }
            }
        }
        walk(style, depth: 0)
        return found
    }

    /// Resolves a component-specific color field (a hex string or a color
    /// expression) in this component's scope. A result that is not a hex color
    /// returns nil and logs `style.color.invalid`, as for style colors.
    func resolveColor(_ raw: String?, context: VariableContext? = nil) -> UIColor? {
        guard let raw, !raw.isEmpty else { return nil }
        guard DSL.Model.Style.`Any`.isColorExpression(raw) else { return UIColor(withHexString: raw) }
        let value = ((try? propertyResolver.resolveToString(raw, context: context ?? getVariableContext())) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard DSL.Model.Style.Color.Hex.isValidHexString(value),
              let color = UIColor(withHexString: value) else {
            warnOnce(key: "style.color.invalid:\(componentPath):\(raw):\(value)",
                     "style.color.invalid: '\(raw)' resolved to '\(value)', not a hex color — field left unset. componentPath='\(componentPath)'")
            return nil
        }
        return color
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

    /// Universal interaction overrides from this component's content (nil unless declared).
    var interactionProps: DSL.Model.Interaction? { component.interaction }
    /// Universal accessibility metadata from this component's content (nil unless declared).
    var accessibilityProps: DSL.Model.Accessibility? { component.accessibility }
    /// `properties.isHidden` (nil unless declared).
    var hiddenFlag: String? {
        if let name = stateManager.currentStateNameValue,
           let flag = component.states?[name]?.hiddenFlag {
            return flag
        }
        return component.hiddenFlag
    }
    var hiddenAnimation: DSL.Model.Animation.Inline? {
        if let name = stateManager.currentStateNameValue,
           let state = component.states?[name], state.hiddenFlag != nil {
            return state.hiddenAnimation?.inlineOrNil
        }
        return component.hiddenAnimation?.inlineOrNil
    }
    var stateChanged: AnyPublisher<Void, Never> {
        stateManager.currentState.dropFirst().map { _ in () }.eraseToAnyPublisher()
    }
    var declaresStateHiddenFlag: Bool {
        component.states?.values.contains { $0.hiddenFlag != nil } ?? false
    }
    /// `content.contextMenu` (nil unless declared).
    var contextMenuProps: DSL.Model.ContextMenu? { component.contextMenu }
    var componentService: ComponentService? { service }

    /// Context-menu item / preview-tap actions, in this component's scope.
    func executeContextMenuActions(_ actions: [DSL.Model.Action]) {
        for action in actions { executeAction(action) }
    }

    var animation: AnyPublisher<DSL.Model.Animation?, Never> {
        stateManager.animation
    }

    var currentStyle: Component.Style? {
        stateManager.currentEffectiveStyle.map { resolveColorExpressions(in: $0).style }
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
            var datasourceSources: [String: VariableDefinition] = [:]
            for (name, definition) in variables {
                if definition.persist == true {
                    service.context.logger.warning("variable.persist.scope: 'persist' on '\(name)' in '\(componentPath)' is ignored — only app variables persist")
                }
                if definition.hasExternalSource,
                   let resolvedValue = parent.getValue(name: "__datasource_\(name)") {
                    effectiveDefinitions[name] = definition.withResolvedValue(resolvedValue)
                    datasourceSources[name] = definition
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
            // `reloadDatasource` refreshes these later.
            for (name, definition) in datasourceSources {
                guard let source = definition.source else { continue }
                service.registerDatasourceBinding(source: source, name: name, type: definition.type, store: variableStore)
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

    /// Provides this component's current host-view size, set by the component
    /// view once it exists. Lets expressions reference the component's own
    /// geometry via the reserved `view` object: `view.width`, `view.height`,
    /// `view.centerX`, `view.centerY`. Read fresh at every resolve so the value
    /// reflects the latest layout. Note this is the component's *own* measured
    /// size — referencing the same axis you are sizing (a `width` expression
    /// reading `view.width`) is circular and unsupported.
    var geometryProvider: (() -> CGSize)?

    /// Get a variable context for property resolution
    func getVariableContext() -> VariableContext {
        let base = VariableContext(store: variableStore)
        guard let size = geometryProvider?(), size.width > 0 || size.height > 0 else {
            return base
        }
        return base.overlaying("view", value: [
            "width": Double(size.width),
            "height": Double(size.height),
            "centerX": Double(size.width / 2),
            "centerY": Double(size.height / 2)
        ])
    }

    /// Resolve a string property that may contain {{expressions}}
    func resolveProperty(_ value: String, context: VariableContext? = nil) -> Any {
        do {
            return try propertyResolver.resolve(value, context: context ?? getVariableContext())
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
        let number: Double?
        if let num = resolved as? Double {
            number = num
        } else if let num = resolved as? Int {
            number = Double(num)
        } else if let num = resolved as? NSNumber {
            number = num.doubleValue
        } else if let str = resolved as? String {
            number = Double(str)
        } else {
            number = nil
        }
        // NaN / ±infinity (`{{ 1e300 * 1e300 }}`, "NaN") reach frames and
        // layers as invalid geometry, which UIKit and Core Animation throw on:
        // treat them as unresolved so the property keeps its default.
        guard let number, number.isFinite else { return nil }
        return CGFloat(number)
    }

    /// Resolve a string expression to a Bool (for visibility, etc.)
    /// The DSL's boolean coercion (variables.md, "Boolean coercion"); nil
    /// when missing or unresolved (the property keeps its default).
    func resolvePropertyToBool(_ value: String) -> Bool? {
        BoolCoercion.coerce(resolveProperty(value))
    }

    // MARK: - Action Execution

    /// Execute a variable action
    func executeVariableAction(_ action: DSL.Model.Action) {
        executeAction(action)
    }

    // MARK: - Gesture Bindings

    /// Write a pan recognizer's raw quantities into the variables bound under
    /// `content.gestures.pan`. Only declared bindings are written; values are in
    /// the gesture view's own coordinate space (translation/location in points,
    /// velocity in points/sec). This is a continuous *binding*, not an action
    /// trigger — it intentionally does not route through analytics.
    func applyPanGesture(translation: CGPoint, velocity: CGPoint, location: CGPoint) {
        guard let pan = component.gestures?.pan else { return }
        // Coalesce all bound quantities into one store transaction so dependent
        // variables / expressions recompute once per frame, not once per binding.
        var updates: [String: Any?] = [:]
        func bind(_ name: String?, _ value: CGFloat) {
            guard let name, !name.isEmpty else { return }
            updates[name] = Double(value)
        }
        bind(pan.translationX, translation.x)
        bind(pan.translationY, translation.y)
        bind(pan.velocityX, velocity.x)
        bind(pan.velocityY, velocity.y)
        bind(pan.locationX, location.x)
        bind(pan.locationY, location.y)
        guard !updates.isEmpty else { return }
        try? variableStore.setMultipleValues(updates)
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

    /// Fire `onTextChange` for a text input (textField / textView) with a
    /// `$value` overlay holding the new text, routed through `dispatchTrigger`
    /// so author-declared analytics fire too.
    func dispatchTextChange(_ text: String) {
        let context = VariableContext(store: variableStore).overlaying("$value", value: text)
        dispatchTrigger(.onTextChange) { [self] action in
            executeAction(action, context: context)
        }
    }

    /// Run `actions` with extra named values in scope, e.g. `event` for a
    /// native module's events (`{{event.signature.id}}`). The values overlay the
    /// component's scope: variable actions write through to the real
    /// variables, navigation params and `emit` payloads read the overlay.
    /// Same execution split as a collection's `onItemTap`.
    func executeActions(_ actions: [DSL.Model.Action], scope values: [String: Any], label: String) {
        var context = getVariableContext()
        for (name, value) in values {
            context = context.overlaying(name, value: value)
        }
        for action in actions {
            executeAction(action, context: context)
        }
    }

    /// Post an engine-originated event (not an authored `emit`) on the
    /// instance event bus, tagged with this component.
    func dispatchToEventBus(name: String, payload: [String: Any]) {
        service.context.eventBus.dispatch(App8Event(
            name: name,
            screenId: screenIdForEvents,
            componentId: leafComponentId,
            componentType: componentTypeKey,
            locale: currentLocale,
            payload: payload
        ))
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
    fileprivate func resolvePayload(_ raw: [String: AnyCodableValue]?, context: VariableContext? = nil) -> [String: Any] {
        guard let raw else { return [:] }
        var resolved: [String: Any] = [:]
        for (key, codable) in raw {
            if let s = codable.value as? String {
                resolved[key] = resolveProperty(s, context: context)
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
    var screenIdForEvents: String {
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
            fireAnalyticsBinding(binding)
        }
    }

    /// Dispatch one author-declared analytics binding for this component.
    /// `context` is the scope its `properties` resolve in (e.g. a native
    /// event's payload as `event`); defaults to the component's scope.
    func fireAnalyticsBinding(_ binding: DSL.Model.AnalyticsBinding, context: VariableContext? = nil) {
        let resolved = resolvePayload(binding.properties, context: context)
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
            runTimerTick(action)

            if repeats {
                let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
                    guard let self = self else {
                        timer.invalidate()
                        return
                    }
                    Task { @MainActor in
                        self.runTimerTick(action)
                    }
                }
                activeTimers.append(timer)
            }
        } else {
            let timer = Timer.scheduledTimer(withTimeInterval: initialDelay, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.runTimerTick(action)

                    if repeats && !self.activeTimers.isEmpty {
                        let repeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
                            guard let self = self else {
                                timer.invalidate()
                                return
                            }
                            Task { @MainActor in
                                self.runTimerTick(action)
                            }
                        }
                        self.activeTimers.append(repeatTimer)
                    }
                }
            }
            activeTimers.append(timer)
        }
    }

    /// A `timer` tick: refresh `now()` / `today()` readers, then run the action.
    private func runTimerTick(_ action: DSL.Model.Action) {
        service.appVariableStore.pulseClock()
        executeAction(action)
    }

    /// Expand an action's transition reference into its concrete resolved form,
    /// resolving any animation pointer against the app animation registry.
    private func resolveTransition(_ transition: DSL.Model.ScreenTransition?) -> DSL.Model.ScreenTransition.Resolved? {
        guard let transition, let inline = transition.inlineOrNil else { return nil }
        let animationResolver = service.context.animationResolver ?? { _ in nil }
        return DSL.Model.ScreenTransition.resolve(inline, animationResolver: animationResolver)
    }

    /// A string-or-expression key resolved against `context` (the action's
    /// scope, e.g. a tapped cell's) or this component's scope.
    private func resolveKey(_ raw: String, context: VariableContext?) -> String {
        guard raw.contains("{{") else { return raw }
        let value = resolveProperty(raw, context: context)
        if let s = value as? String { return s }
        return "\(value)"
    }

    /// Execute an action directly (for event triggers). `context` overrides
    /// the store navigation params resolve against (e.g. a tapped cell's).
    ///
    /// `store` overrides the store variable actions write to (e.g. a tapped
    /// cell's scoped store); it defaults to this component's store. Nested
    /// action lists (`forEach`, `with`, `request` callbacks) run through here
    /// with the same store and an extended `context`, so every action type
    /// works at every depth.
    func executeAction(_ action: DSL.Model.Action, context: VariableContext? = nil, store: VariableStoreProtocol? = nil) {
        if action.type.isVariableAction {
            let targetStore = store ?? variableStore
            let ctx = context ?? (store.map { VariableContext(store: $0) } ?? getVariableContext())
            do {
                try variableActionHandler.execute(action: action, store: targetStore, context: ctx)
            } catch {
                service.context.logger.error("Failed to execute \(action.type.rawValue) action in '\(componentPath)': \(error)")
            }
            return
        }
        switch action.type {
        case .updateVariable, .incrementVariable, .updateMultipleVariables, .resetVariables, .toggleArrayValue,
             .appendToArray, .incrementArrayItem, .insertArrayItem, .upsertArrayItem, .removeArrayItem:
            break   // handled above

        case .forEach:
            runForEach(action, context: context ?? (store.map { VariableContext(store: $0) } ?? getVariableContext()), store: store)

        case .with:
            let ctx = context ?? (store.map { VariableContext(store: $0) } ?? getVariableContext())
            var scoped = ctx
            for (name, raw) in action.values ?? [:] {
                scoped = scoped.overlaying(name, value: resolveActionValue(raw.value, context: ctx))
            }
            for nested in action.actions?.actions ?? [] {
                executeAction(nested, context: scoped, store: store)
            }

        case .unknown:
            break   // reported when decoded; runs nothing

        case .if:
            // The condition once, then exactly one branch in the current scope.
            let ctx = context ?? (store.map { VariableContext(store: $0) } ?? getVariableContext())
            let raw = action.condition?.value
            let holds = ActionCondition.holds(raw.map { resolveActionValue($0, context: ctx) })
            for nested in (holds ? action.then : action.else)?.actions ?? [] {
                executeAction(nested, context: ctx, store: store)
            }

        case .request:
            runRequest(action, context: context ?? (store.map { VariableContext(store: $0) } ?? getVariableContext()), store: store)

        case .reloadDatasource:
            guard let source = action.source, !source.isEmpty else {
                service.context.logger.warning("reloadDatasource without 'source' — ignored. componentPath='\(componentPath)'")
                return
            }
            let resolved = source.contains("{{") ? "\(resolveProperty(source, context: context))" : source
            let ctx = context ?? (store.map { VariableContext(store: $0) } ?? getVariableContext())
            let onSuccess = action.onSuccess?.actions ?? []
            let onError = action.onError?.actions ?? []
            let screenId = screenIdForEvents
            Task { @MainActor [weak self, service] in
                let ok = await service.reloadDatasource(resolved, screenId: screenId)
                guard let self else { return }
                for child in ok ? onSuccess : onError {
                    self.executeAction(child, context: ctx, store: store)
                }
            }

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
                            resolvedParams[key] = resolveProperty(stringValue, context: context)
                        } else {
                            resolvedParams[key] = value.value
                        }
                    }
                }

                // Resolve the action-level transition. `mode` decides the route
                // when the transition is custom; an explicit `.system` opts out
                // (and suppresses screen/app defaults downstream).
                var actionTransition = resolveTransition(action.transition)

                if var zoomTransition = actionTransition, zoomTransition.kind == .nativeZoom, var zoom = zoomTransition.nativeZoom {
                    // Native zoom: resolve the keys in the action's scope now.
                    zoom.resolvedSourceKey = resolveKey(zoom.sourceKeyExpression, context: context)
                    zoom.resolvedAlignmentKey = zoom.alignmentKeyExpression.map { resolveKey($0, context: context) }
                    zoomTransition.nativeZoom = zoom
                    actionTransition = zoomTransition
                    let wantsModal = (action.presentation != nil && action.presentation != .push) || zoomTransition.mode == .modal
                    let request: NavigationRequest
                    if wantsModal {
                        let style = action.presentation.flatMap { $0 == .push ? nil : $0.toModalPresentationStyle } ?? .fullScreen
                        request = NavigationRequest(
                            type: .presentModal(screenId: nextScreen, params: resolvedParams, style: style, detents: action.detents, grabber: action.grabber),
                            transition: zoomTransition
                        )
                    } else {
                        request = NavigationRequest(type: .push(screenId: nextScreen, params: resolvedParams), transition: zoomTransition)
                    }
                    NotificationCenter.default.post(name: .app8NavigationRequest, object: request)
                } else if let actionTransition, actionTransition.kind != .system, actionTransition.mode == .modal {
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
            // `tabId` may be an expression (`{{item.id}}` in a tab bar template).
            let tabId = action.tabId.map { $0.contains("{{") ? resolvePropertyToString($0) : $0 }
            let request = NavigationRequest(type: .selectTab(index: action.tabIndex, id: tabId))
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
                top.app8PresentInScreenStyle(alert)
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
                let resolved = context.map { "\(resolveProperty(urlString, context: $0))" } ?? resolvePropertyToString(urlString)
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
                            top.app8PresentInScreenStyle(safariVC)
                        }
                    }
                }
            }

        case .emit:
            guard let eventName = action.name, !eventName.isEmpty else {
                service.context.logger.warning("Action .emit missing `name` — dropped. componentPath='\(componentPath)'")
                return
            }
            let resolved = resolvePayload(action.payload, context: context)
            service.context.eventBus.dispatch(App8Event(
                name: eventName,
                screenId: screenIdForEvents,
                componentId: leafComponentId,
                componentType: componentTypeKey,
                locale: currentLocale,
                payload: resolved
            ))

        case .requestNotificationPermission:
            // The rest of the trigger's list has already run (like `request`);
            // onGranted / onDenied run once the user (or the stored status) answers.
            let granted = action.onGranted?.actions ?? []
            let denied = action.onDenied?.actions ?? []
            let ctx = context ?? (store.map { VariableContext(store: $0) } ?? getVariableContext())
            NotificationPermission.request { [weak self] ok in
                guard let self else { return }
                for next in ok ? granted : denied {
                    self.executeAction(next, context: ctx, store: store)
                }
            }

        case .capturePhoto:
            runCapturePhoto(action, context: context ?? (store.map { VariableContext(store: $0) } ?? getVariableContext()), store: store)

        case .deletePhoto:
            runDeletePhoto(action, context: context ?? (store.map { VariableContext(store: $0) } ?? getVariableContext()))

        case .executeFunction, .complete:
            break
        }
    }

    // MARK: - Control flow + request

    /// Resolves `{{…}}` in an action value, also inside objects / arrays.
    func resolveActionValue(_ value: Any, context: VariableContext?) -> Any {
        if let string = value as? String {
            return string.contains("{{") ? resolveProperty(string, context: context) : string
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues { resolveActionValue($0, context: context) }
        }
        if let array = value as? [Any] {
            return array.map { resolveActionValue($0, context: context) }
        }
        return value
    }

    /// `forEach`: runs `actions` once per element of `items`, in order, with
    /// the element bound to `as` (default `item`) and, when set, its position
    /// bound to `index`. A null or non-array `items` runs nothing.
    private func runForEach(_ action: DSL.Model.Action, context: VariableContext, store: VariableStoreProtocol?) {
        guard let raw = action.items?.value,
              let elements = resolveActionValue(raw, context: context) as? [Any] else { return }
        let name = action.as ?? "item"
        let indexName = action.index?.value as? String
        let nested = action.actions?.actions ?? []
        for (position, element) in elements.prefix(EngineLimits.maxArrayVariableCount).enumerated() {
            var scoped = context.overlaying(name, value: element)
            if let indexName, !indexName.isEmpty {
                scoped = scoped.overlaying(indexName, value: position)
            }
            for child in nested {
                executeAction(child, context: scoped, store: store)
            }
        }
    }

    /// `request`: an HTTP call through the host's `prepareRequest` hook. The
    /// rest of the action list does not wait for it. On completion
    /// `resultVariable` is written, then `onSuccess` (2xx) or `onError`
    /// (anything else; status 0 = network failure, timeout or host rejection)
    /// run with `response` (`{ status, body, headers }`) in scope. When this
    /// component is gone by then, the callbacks are dropped; an app-scope
    /// `resultVariable` is still written.
    private func runRequest(_ action: DSL.Model.Action, context: VariableContext, store: VariableStoreProtocol?) {
        guard let rawURL = action.url else {
            service.context.logger.warning("request without 'url' — ignored. componentPath='\(componentPath)'")
            return
        }
        let urlString = "\(resolveActionValue(rawURL, context: context))"
        let headers = (action.headers ?? [:]).mapValues { "\(resolveActionValue($0, context: context))" }
        let body = action.body.map { resolveActionValue($0.value, context: context) }
        let request = ActionHTTPRequest.make(method: action.method, url: urlString, headers: headers, body: body)
        if request == nil {
            service.context.logger.warning("request: '\(urlString)' is not an absolute http(s) URL. componentPath='\(componentPath)'")
        }
        let resultVariable = action.resultVariable.flatMap { $0.isEmpty ? nil : $0 }
        let onSuccess = action.onSuccess?.actions ?? []
        let onError = action.onError?.actions ?? []
        let dataSource = service.dataSource
        let session = service.context.urlSession
        let appStore = service.appVariableStore
        let logger = service.context.logger
        Task { @MainActor [weak self] in
            let response = await ActionHTTPRequest.perform(request, session: session) { try await dataSource.prepareRequest($0) }
            let value = response.dictionary
            guard let self else {
                // The component is gone: drop the callbacks, keep app state.
                if let resultVariable, appStore.hasVariable(name: resultVariable) {
                    try? appStore.setValue(name: resultVariable, value: value)
                }
                return
            }
            if let resultVariable {
                do {
                    try (store ?? self.variableStore).setValue(name: resultVariable, value: value)
                } catch {
                    logger.error("request: could not write resultVariable '\(resultVariable)': \(error)")
                }
            }
            let scoped = context.overlaying("response", value: value)
            for child in response.isSuccess ? onSuccess : onError {
                self.executeAction(child, context: scoped, store: store)
            }
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

/// The DSL's one boolean coercion (variables.md, "Boolean coercion"), for
/// every boolean: `if` conditions, `isHidden`, `isEnabled`, toggles.
enum BoolCoercion {
    /// true, non-zero numbers, "true" / "1", non-empty arrays and objects;
    /// any other string, 0 and null are false. nil: missing, or an expression
    /// that did not resolve (its `{{…}}` text): the property's default.
    static func coerce(_ value: Any?) -> Bool? {
        switch value {
        case nil: return nil
        case is NSNull: return false
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
            return n.doubleValue != 0
        case let b as Bool: return b
        case let i as Int: return i != 0
        case let d as Double: return d != 0
        case let s as String:
            if s.contains("{{") { return nil }
            return s.lowercased() == "true" || s == "1"
        case let a as [Any]: return !a.isEmpty
        case let o as [String: Any]: return !o.isEmpty
        default: return false
        }
    }
}

/// The `if` action's condition: the boolean coercion; an unevaluable condition runs `else`.
enum ActionCondition {
    static func holds(_ value: Any?) -> Bool {
        BoolCoercion.coerce(value) ?? false
    }
}
