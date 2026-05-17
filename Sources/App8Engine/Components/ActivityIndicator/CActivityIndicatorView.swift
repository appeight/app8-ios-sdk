import UIKit
import Combine

class CActivityIndicatorView: App8BaseView<DSL.Model.Component.ActivityIndicator.C>, CViewProtocol {

    weak var materialView: MaterialView?
    let contentView = UIView()
    private let indicator = UIActivityIndicatorView(style: .medium)

    override var intrinsicContentSource: UIView? { indicator }

    private var viewModel: CActivityIndicatorViewModel?
    private var propertiesCancellable: AnyCancellable?
    private var variablesCancellable: AnyCancellable?

    // MARK: - Setup

    override func setup() {
        super.setup()

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()

        contentView.addSubview(indicator)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        indicator.hidesWhenStopped = true
    }

    // MARK: - Configure

    func configure(viewModel: CActivityIndicatorViewModel, superview: UIView? = nil, animated: Bool = true) {
        guard let superview = superview ?? self.superview else { return }
        self.viewModel = viewModel

        bindLayout(
            viewModel.layout,
            in: superview,
            viewRegistry: viewModel.service.componentRegistry.viewRegistry,
            parentComponentPath: viewModel.parentPath,
            keyboardService: viewModel.service.context.keyboardService,
            animated: animated
        )
        bindStyle(viewModel.style, animation: viewModel.animation)
        applyCurrentProperties()

        propertiesCancellable = viewModel.properties
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentProperties()
            }

        variablesCancellable = viewModel.variablesChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentProperties()
            }
    }

    // MARK: - Properties

    private func applyCurrentProperties() {
        guard let vm = viewModel else { return }
        let props = vm.currentProperties

        let hidesWhenStopped = props.hidesWhenStopped ?? true
        indicator.hidesWhenStopped = hidesWhenStopped

        let isAnimating: Bool
        if let expr = props.isAnimating {
            isAnimating = vm.resolvePropertyToBool(expr) ?? true
        } else {
            isAnimating = true
        }

        if isAnimating {
            indicator.startAnimating()
        } else {
            indicator.stopAnimating()
        }
    }

    // MARK: - Style

    override func applyStyle(
        _ style: Content.Style?,
        animated: Bool = true,
        duration: TimeInterval = 0.25,
        options: UIView.AnimationOptions = [.curveEaseInOut],
        useSpring: Bool = false
    ) {
        super.applyStyle(style, animated: animated, duration: duration, options: options, useSpring: useSpring)
        applyBaseStyle(style, animated: animated, duration: duration, options: options, useSpring: useSpring)

        if let indicatorStyle = style?.indicatorStyle {
            indicator.style = indicatorStyle.ui
        }
        if let hex = style?.color, let color = UIColor(withHexString: hex) {
            indicator.color = color
        }
    }
}

// MARK: - StreamingUpdatable

extension CActivityIndicatorView: StreamingUpdatable {

    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CActivityIndicatorViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }

        self.viewModel = vm
        bindStyle(vm.style, animation: vm.animation)
        applyCurrentProperties()

        propertiesCancellable = vm.properties
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentProperties()
            }
        variablesCancellable = vm.variablesChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentProperties()
            }
        return vm
    }
}
