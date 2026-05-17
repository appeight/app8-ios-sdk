import Foundation
import UIKit

/// Protocol for ViewModels that can be registered and receive state changes
@MainActor
protocol StateControllable: AnyObject {
    func setState(_ stateName: String?, animated: Bool)
}

/// Weak wrapper for AnyObject references
private final class WeakRef<T: AnyObject> {
    weak var value: T?
    init(_ value: T) {
        self.value = value
    }
}

/// Registry for component ViewModels, enabling cross-component state propagation.
@MainActor
final class ComponentRegistry {

    private var viewModels: [String: WeakRef<AnyObject>] = [:]

    /// Registry for UIViews by component ID, used for sibling constraint resolution.
    /// Separate from ViewModel registry to decouple layout from accessibility identifiers.
    private(set) var viewRegistry = ViewRegistry()

    /// Optional logger from owning context.
    weak var logger: A8Log?

    /// Register a ViewModel with its component ID
    func register(id: String, viewModel: AnyObject) {
        viewModels[id] = WeakRef(viewModel)
    }

    /// Unregister a ViewModel by ID
    func unregister(id: String) {
        viewModels.removeValue(forKey: id)
    }

    /// Lookup a ViewModel by ID
    func viewModel(forId id: String) -> AnyObject? {
        guard let ref = viewModels[id] else { return nil }
        if ref.value == nil {
            viewModels.removeValue(forKey: id)
            return nil
        }
        return ref.value
    }

    /// Set state on a component by ID (if it implements StateControllable)
    func setState(_ stateName: String?, forComponentId id: String, animated: Bool = true) {
        guard let vm = viewModel(forId: id) as? StateControllable else {
            // Children may not be registered yet during initial state setup.
            // CView.configureContent calls forceReapplyState after children render.
            return
        }
        vm.setState(stateName, animated: animated)
    }

    /// Set states on multiple components
    func setStates(_ childStates: [String: String], animated: Bool = true) {
        logger?.debug("setStates called with: \(childStates)")
        for (id, stateName) in childStates {
            setState(stateName, forComponentId: id, animated: animated)
        }
    }

    /// Clean up dead references
    func cleanUp() {
        viewModels = viewModels.filter { $0.value.value != nil }
        viewRegistry.cleanUp()
    }
}

// MARK: - View Registry

/// Registry for UIViews by component ID, used for sibling constraint resolution.
/// This separates layout concerns from accessibility identifiers.
@MainActor
final class ViewRegistry {

    private var views: [String: WeakRef<UIView>] = [:]

    /// Register a view with its component ID
    func register(id: String, view: UIView) {
        views[id] = WeakRef(view)
    }

    /// Unregister a view by ID
    func unregister(id: String) {
        views.removeValue(forKey: id)
    }

    /// Lookup a view by component ID
    func view(forId id: String) -> UIView? {
        guard let ref = views[id] else { return nil }
        if ref.value == nil {
            views.removeValue(forKey: id)
            return nil
        }
        return ref.value
    }

    /// Find a sibling view by ID within the same container
    /// - Parameters:
    ///   - siblingId: The component ID of the sibling to find
    ///   - excludingView: The view making the request (to exclude self from results)
    /// - Returns: The sibling view if found
    func sibling(id siblingId: String, excludingView: UIView?) -> UIView? {
        guard let view = view(forId: siblingId) else { return nil }
        if let excludingView, view === excludingView { return nil }
        return view
    }

    /// Clean up dead references
    func cleanUp() {
        views = views.filter { $0.value.value != nil }
    }
}
