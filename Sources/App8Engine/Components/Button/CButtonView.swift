import UIKit
import Combine

class CButtonView: App8BaseView<DSL.Model.Component.Button.C>, CViewProtocol {

    weak var materialView: MaterialView?
    let contentView = UIView()
    private let button = UIButton(type: .system)
    private var viewModel: CButtonViewModel?  // strong ref keeps viewModel alive
    private var propertiesCancellable: AnyCancellable?

    override var intrinsicContentSource: UIView? { button }

    override func setup() {
        super.setup()

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()

        contentView.addSubview(button)
        button.cMakeEqualToSuperview()

        button.addTarget(self, action: #selector(handleTouchDown), for: [.touchDown, .touchDragInside])
        button.addTarget(self, action: #selector(handleTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragOutside])
        button.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    func configure(viewModel: CButtonViewModel, superview: UIView? = nil, animated: Bool = true) {
        guard let superview = superview ?? self.superview else {
            return
        }
        self.viewModel = viewModel
        bindLayout(viewModel.layout, in: superview, viewRegistry: viewModel.service.componentRegistry.viewRegistry, parentComponentPath: viewModel.parentPath, keyboardService: viewModel.service.context.keyboardService, animated: animated)
        bindStyle(viewModel.style, animation: viewModel.animation)
        bindProperties(viewModel.propertiesWithVariables)
    }

    private func bindProperties(_ publisher: AnyPublisher<Content.Properties, Never>) {
        propertiesCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] properties in
                self?.applyProperties(properties)
            }
    }

    private func applyProperties(_ properties: Content.Properties) {
        if let viewModel = viewModel {
            button.setTitle(viewModel.resolvePropertyToString(properties.text), for: .normal)
        } else {
            button.setTitle(properties.text, for: .normal)
        }
    }

    // MARK: - Touch Triggers

    /// Whether this button has custom press states defined in DSL
    private var hasCustomPressStates: Bool {
        viewModel?.component.triggers != nil
    }

    @objc private func handleTouchDown() {
        viewModel?.fireTrigger(.touchDown)
        // Default press feedback when no custom states are declared in DSL.
        // Routed through AnimationRunner so it picks up the same defaults
        // (Reduce Motion, .beginFromCurrentState) as state-driven transitions.
        if !hasCustomPressStates {
            AnimationRunner.run(
                animation: .defaultPressFeedback,
                additionalOptions: [.beginFromCurrentState, .allowUserInteraction],
                viewBlock: { [self] in self.alpha = 0.6 }
            )
        }
    }

    @objc private func handleTouchUp() {
        viewModel?.fireTrigger(.touchUp)
        if !hasCustomPressStates {
            AnimationRunner.run(
                animation: .defaultPressFeedback,
                additionalOptions: [.beginFromCurrentState, .allowUserInteraction],
                viewBlock: { [self] in self.alpha = 1.0 }
            )
        }
    }

    @objc private func handleTap() {
        viewModel?.executeAction(for: .tap)
    }

    override func applyStyle(
        _ style: Content.Style?,
        animated: Bool = true,
        duration: TimeInterval = 0.25,
        options: UIView.AnimationOptions = [.curveEaseInOut],
        useSpring: Bool = false
    ) {
        super.applyStyle(style, animated: animated, duration: duration, options: options, useSpring: useSpring)
        applyBaseStyle(style, animated: animated, duration: duration, options: options, useSpring: useSpring)

        if let textModel = style?.text {
            applyTextModel(textModel)
        }
    }

    private func applyTextModel(_ textModel: DSL.Model.Style.TextModel) {
        if let alignment = textModel.alignment {
            button.titleLabel?.textAlignment = alignment.ui
        }
        if let themedColor = textModel.color {
            button.setTitleColor(themedColor.ui, for: .normal)
        }
        button.titleLabel?.font = textModel.resolveUIFont()
    }
}

// MARK: - StreamingUpdatable

extension CButtonView: StreamingUpdatable {

    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CButtonViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }

        self.viewModel = vm
        bindStyle(vm.style, animation: vm.animation)
        bindProperties(vm.propertiesWithVariables)
        return vm
    }
}
