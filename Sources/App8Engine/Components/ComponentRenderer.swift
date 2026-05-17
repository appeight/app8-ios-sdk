import UIKit

struct ComponentRenderResult {
    let view: UIView
    let type: DSL.Model.Component.CType
    let viewModel: ComponentViewModelAbstract?

    init(view: UIView, type: DSL.Model.Component.CType, viewModel: ComponentViewModelAbstract? = nil) {
        self.view = view
        self.type = type
        self.viewModel = viewModel
    }
}

protocol ComponentRenderer {
    @MainActor
    func renderScreen(_ component: DSL.Model.Component.`Any`, params: [String: Any]?) -> UIViewController

    @MainActor
    @discardableResult
    func renderComponent(_ component: DSL.Model.Component.`Any`, superview: UIView, parentPath: String?, parentVariableStore: VariableStoreProtocol?, reuseViewModel: ComponentViewModelAbstract?) -> ComponentRenderResult

    @MainActor
    func renderErrorScreen(errorText: String) -> UIViewController

    @MainActor
    func renderErrorView() -> UIView
}

/// Convenience extension providing default parameters
extension ComponentRenderer {
    @MainActor
    func renderScreen(_ component: DSL.Model.Component.`Any`) -> UIViewController {
        renderScreen(component, params: nil)
    }

    @MainActor
    @discardableResult
    func renderComponent(_ component: DSL.Model.Component.`Any`, superview: UIView) -> ComponentRenderResult {
        renderComponent(component, superview: superview, parentPath: nil, parentVariableStore: nil, reuseViewModel: nil)
    }

    @MainActor
    @discardableResult
    func renderComponent(_ component: DSL.Model.Component.`Any`, superview: UIView, parentPath: String?) -> ComponentRenderResult {
        renderComponent(component, superview: superview, parentPath: parentPath, parentVariableStore: nil, reuseViewModel: nil)
    }

    @MainActor
    @discardableResult
    func renderComponent(_ component: DSL.Model.Component.`Any`, superview: UIView, parentPath: String?, parentVariableStore: VariableStoreProtocol?) -> ComponentRenderResult {
        renderComponent(component, superview: superview, parentPath: parentPath, parentVariableStore: parentVariableStore, reuseViewModel: nil)
    }
}
