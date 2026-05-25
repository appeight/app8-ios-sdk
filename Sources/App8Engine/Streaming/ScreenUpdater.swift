import UIKit

/// Handles structural screen updates (Phase 1: full re-render with state preservation).
///
/// When the server pushes a new component definition for a streaming screen,
/// ScreenUpdater snapshots the current variable store, re-renders the new component
/// into the container with a cross-dissolve animation, and restores variable values
/// that still exist in the new definition.
@MainActor
final class ScreenUpdater {

    private let container: UIView
    private let service: App8Service
    private let context: App8Context
    /// Alias the host requested when first rendering this screen (i.e. the
    /// value passed to `App8.Instance.renderScreen(screenId:)` or
    /// `App8Cloud.Instance.screen(id:)`). Used as the path root on every
    /// streaming re-render so `event.screenId` stays stable across server
    /// pushes — even when the DSL document's internal `"id"` changes.
    /// `nil` only when streaming was started without a known request alias.
    private let requestedScreenId: String?
    private weak var currentView: UIView?
    private weak var rootCView: CView?

    init(container: UIView, initialView: UIView, service: App8Service, context: App8Context, requestedScreenId: String? = nil) {
        self.container = container
        self.service = service
        self.context = context
        self.requestedScreenId = requestedScreenId
        self.currentView = initialView
        self.rootCView = initialView as? CView
    }

    /// Re-renders the screen with a new component definition, preserving variable state.
    ///
    /// - Parameters:
    ///   - newComponent: The new screen component definition from the server
    ///   - preservedState: Variable values to restore in the new store (snapshot from old store)
    ///   - animated: Whether to fade between old and new content
    /// - Returns: The new ScopedVariableStore created for the new component, or nil on failure
    func update(
        newComponent: DSL.Model.Component.`Any`,
        preservedState: [String: Any?],
        animated: Bool
    ) async -> ScopedVariableStore? {
        guard
            case .key(.screen) = newComponent.type,
            let entity: DSL.Model.Component.View.Entity = newComponent.asConcreteEntity()
        else {
            context.logger.error("ScreenUpdater: received non-screen component")
            return nil
        }

        // Build new variable store with preserved state
        let newStore = ScopedVariableStore(parent: service.appVariableStore)

        if let variables = entity.content.variables {
            do {
                try newStore.defineVariables(variables)
            } catch {
                context.logger.warning("ScreenUpdater: failed to define variables: \(error)")
            }
        }

        // Restore preserved values that still exist in the new definition
        for (name, value) in preservedState {
            guard newStore.hasVariable(name: name), let value else { continue }
            do {
                try newStore.setValue(name: name, value: value)
            } catch {
                context.logger.warning("ScreenUpdater: failed to restore '\(name)': \(error)")
            }
        }

        // Preserve the host's requested alias as the path root across streaming
        // re-renders — same rule as `App8Service.renderScreenSync`. The DSL
        // document's internal `"id"` is irrelevant to the host.
        let screenRootId = requestedScreenId ?? newComponent.id

        // Create new CViewModel for the new component
        guard let viewModel = CViewModel(
            component: entity,
            service: service,
            componentPath: screenRootId,
            parentVariableStore: newStore
        ) else {
            context.logger.error("ScreenUpdater: failed to create CViewModel for '\(newComponent.id)'")
            return nil
        }

        service.componentRegistry.register(id: screenRootId, viewModel: viewModel)

        // Resolve new screen background color
        let newBgColor: UIColor?
        if let bgString = entity.content.properties.backgroundColor?.value {
            let resolved = viewModel.resolvePropertyToString(bgString)
            newBgColor = UIColor(withHexString: resolved)
        } else {
            newBgColor = nil
        }

        if let rootCView {
            // Fast path: reconfigure the existing root CView in-place (diff-based)
            rootCView.reconfigure(viewModel: viewModel, animated: animated)

            if !context.layoutMode.isEnabled {
                if animated, let color = newBgColor {
                    UIView.animate(withDuration: 0.3) { [self] in
                        self.container.backgroundColor = color
                    }
                } else if let color = newBgColor {
                    container.backgroundColor = color
                }
            }
        } else {
            // Fallback: full-screen swap (rootCView not available)
            let newView = CView()
            newView.alpha = 0
            newView.configure(viewModel: viewModel, superview: container, animated: false)

            let outgoingView = currentView
            currentView = newView

            if animated {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) { [self] in
                        newView.alpha = 1
                        if let color = newBgColor, !context.layoutMode.isEnabled {
                            self.container.backgroundColor = color
                        }
                    } completion: { _ in
                        outgoingView?.removeFromSuperview()
                        continuation.resume()
                    }
                }
            } else {
                outgoingView?.removeFromSuperview()
                newView.alpha = 1
                if let color = newBgColor, !context.layoutMode.isEnabled {
                    container.backgroundColor = color
                }
            }
        }

        // Return CViewModel's variableStore (not newStore) — screen variables are defined
        // inside CViewModel's own ScopedVariableStore, so StreamingSession must hold a
        // reference to that store for setExternalValue to find and update variables.
        return viewModel.variableStore
    }
}
