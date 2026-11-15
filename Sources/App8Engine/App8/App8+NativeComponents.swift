//
//  App8+NativeComponents.swift
//  App8Engine
//
//  Host registration for the DSL `native` component.
//

import UIKit

extension App8 {

    /// Factory for a `native` component module. Called once per rendered
    /// component; the returned view is laid out with the component's DSL layout.
    public typealias NativeComponentFactory = @MainActor (App8NativeContext) -> UIView

    /// Registers the native view for `module`. Every `native` component whose
    /// `properties.module` equals `module` renders the view this factory returns.
    /// Register before the screen that uses it is rendered; a later
    /// registration replaces the earlier one for screens rendered afterwards.
    ///
    /// ```swift
    /// App8.registerNativeComponent("signaturePad") { context in
    ///     SignaturePadView(context: context)
    /// }
    /// ```
    @MainActor
    public static func registerNativeComponent(_ module: String, factory: @escaping NativeComponentFactory) {
        NativeComponentRegistry.shared.register(module, factory: factory)
    }

    /// Removes the factory for `module`. Screens rendered afterwards show the
    /// component's `fallback`.
    @MainActor
    public static func unregisterNativeComponent(_ module: String) {
        NativeComponentRegistry.shared.unregister(module)
    }
}

/// What a native component's view gets from the engine.
@MainActor
public final class App8NativeContext {

    /// The registered module name (`properties.module`).
    public let module: String

    /// `app.id` of the running DSL app, when the app declares one.
    public let appId: String?

    /// Screen id the component renders in, as the host requested it.
    public let screenId: String

    /// Resolved `properties.props`: expressions evaluated, numbers as `Double`,
    /// `null` as `NSNull`. Updated before `onPropsChange` is called.
    public internal(set) var props: [String: Any]

    /// Set by the view to receive new props when the variables they read change.
    public var onPropsChange: (([String: Any]) -> Void)?

    private let emitHandler: @MainActor (String, [String: Any]) -> Void

    init(
        module: String,
        appId: String?,
        screenId: String,
        props: [String: Any],
        emit: @escaping @MainActor (String, [String: Any]) -> Void
    ) {
        self.module = module
        self.appId = appId
        self.screenId = screenId
        self.props = props
        self.emitHandler = emit
    }

    /// Sends a module event. Runs the component's `actions[event]` with
    /// `payload` in scope as `event`, and posts `native.<module>.<event>` on
    /// the instance event bus.
    public func emit(_ event: String, _ payload: [String: Any] = [:]) {
        emitHandler(event, payload)
    }

    /// Called by the engine when resolved props changed.
    func updateProps(_ newProps: [String: Any]) {
        props = newProps
        onPropsChange?(newProps)
    }
}

/// Process-wide module → factory table behind `App8.registerNativeComponent`.
@MainActor
final class NativeComponentRegistry {
    static let shared = NativeComponentRegistry()

    private var factories: [String: App8.NativeComponentFactory] = [:]

    func register(_ module: String, factory: @escaping App8.NativeComponentFactory) {
        factories[module] = factory
    }

    func unregister(_ module: String) {
        factories[module] = nil
    }

    func factory(for module: String) -> App8.NativeComponentFactory? {
        factories[module]
    }
}
