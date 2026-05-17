//
//  CStackViewView.swift
//  App8Engine
//

import UIKit
import Combine

class CStackViewView: App8BaseView<DSL.Model.Component.StackView.C>, CViewProtocol {

    private var viewModel: CStackViewViewModel?
    var layoutModeContext: App8LayoutMode? { viewModel?.service.context.layoutMode }
    weak var materialView: MaterialView?
    let contentView = UIView()

    private let stackView = UIStackView()

    override var intrinsicContentSource: UIView? { stackView }

    private lazy var dynamicBackgroundView: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }()

    private var cancellables = Set<AnyCancellable>()

    override func setup() {
        super.setup()
        addSubview(contentView)
        contentView.cMakeEqualToSuperview()
        contentView.addSubview(stackView)
        stackView.cMakeEqualToSuperview()
    }

    func configure(viewModel: CStackViewViewModel, superview: UIView? = nil, animated: Bool = true) {
        self.viewModel = viewModel

        guard let superview = superview ?? self.superview else {
            return
        }

        bindLayout(
            viewModel.layout,
            in: superview,
            viewRegistry: viewModel.service.componentRegistry.viewRegistry,
            parentComponentPath: viewModel.parentPath,
            keyboardService: viewModel.service.context.keyboardService,
            animated: animated
        )
        bindStyle(viewModel.style, animation: viewModel.animation)
        bindDynamicBackgroundColor(viewModel: viewModel)
        bindProperties(viewModel.propertiesWithVariables)
        configureContent(viewModel: viewModel, animated: animated)
        // Re-layout after children are added so centerY resolves against actual content height.
        superview.layoutIfNeeded()
        setupTapGestureIfNeeded()
        viewModel.startEventTriggers()
    }

    override func removeFromSuperview() {
        viewModel?.cancelEventTriggers()
        super.removeFromSuperview()
    }

    // MARK: - Dynamic Background Color

    private func bindDynamicBackgroundColor(viewModel: CStackViewViewModel) {
        viewModel.resolvedBackgroundColor
            .receive(on: DispatchQueue.main)
            .sink { [weak self] color in
                self?.applyDynamicBackgroundColor(color, cornerRadius: viewModel.cornerRadius)
            }
            .store(in: &cancellables)
    }

    private func applyDynamicBackgroundColor(_ color: UIColor?, cornerRadius: CGFloat?) {
        guard let color = color, !(viewModel?.service.context.layoutMode.isEnabled == true) else {
            dynamicBackgroundView.removeFromSuperview()
            return
        }
        if dynamicBackgroundView.superview == nil {
            insertSubview(dynamicBackgroundView, at: 0)
            dynamicBackgroundView.cMakeEqualToSuperview()
        }
        dynamicBackgroundView.backgroundColor = color
        if let radius = cornerRadius {
            dynamicBackgroundView.layer.cornerRadius = radius
            dynamicBackgroundView.layer.cornerCurve = .continuous
            dynamicBackgroundView.clipsToBounds = true
            // Don't set self.clipsToBounds — allows MaterialView shadow to render
            // beyond bounds. Children are clipped by contentView.layer.masksToBounds.
        }
    }

    // MARK: - Properties Binding

    private func bindProperties(_ propertiesPublisher: some Publisher<DSL.Model.Component.StackView.Properties, Never>) {
        propertiesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyStackProperties()
            }
            .store(in: &cancellables)
        applyStackProperties()
    }

    private func applyStackProperties() {
        guard let viewModel = viewModel else { return }
        stackView.axis = viewModel.stackAxis
        stackView.alignment = viewModel.stackAlignment
        stackView.distribution = viewModel.stackDistribution
        stackView.spacing = viewModel.currentProperties.spacing ?? 0
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
    }

    private func configureContent(viewModel: CStackViewViewModel, animated: Bool = false) {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        viewModel.component.children.forEach { child in
            let result = viewModel.service.renderComponent(
                child,
                superview: stackView,
                parentPath: viewModel.componentPath,
                parentVariableStore: viewModel.variableStore
            )
            stackView.addArrangedSubview(result.view)
        }

        // Re-apply current state to propagate childStates now that children exist.
        if let currentState = viewModel.currentStateName {
            viewModel.forceReapplyState(currentState)
        }
    }

    // MARK: - Touch Triggers

    private var tapGesture: UITapGestureRecognizer?

    private var shouldHandleTouches: Bool {
        guard let viewModel = viewModel else { return false }
        let hasTriggers = viewModel.component.triggers != nil
        let hasActions = viewModel.component.actions != nil
        return hasTriggers || hasActions
    }

    private func setupTapGestureIfNeeded() {
        guard shouldHandleTouches, tapGesture == nil else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        addGestureRecognizer(tap)
        tapGesture = tap
    }

    @objc private func handleTapGesture(_ gesture: UITapGestureRecognizer) {
        viewModel?.service.context.logger.debug("CStackViewView.handleTapGesture: \(viewModel?.componentPath ?? "unknown")")
        viewModel?.executeAction(for: .tap)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard shouldHandleTouches else { return }
        viewModel?.service.context.logger.debug("CStackViewView.touchesBegan: \(viewModel?.componentPath ?? "unknown")")
        viewModel?.fireTrigger(.touchDown)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard shouldHandleTouches else { return }
        viewModel?.service.context.logger.debug("CStackViewView.touchesEnded: \(viewModel?.componentPath ?? "unknown")")
        viewModel?.fireTrigger(.touchUp)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        guard shouldHandleTouches else { return }
        viewModel?.service.context.logger.debug("CStackViewView.touchesCancelled: \(viewModel?.componentPath ?? "unknown")")
        viewModel?.fireTrigger(.touchUp)
    }

    // MARK: - Helpers

    private func typeName(for ctype: DSL.Model.Component.CType) -> String {
        switch ctype {
        case .key(let key): return key.rawValue
        case .custom(let name): return name
        }
    }
}

// MARK: - StreamingUpdatable

extension CStackViewView: StreamingUpdatable {

    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CStackViewViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }

        self.viewModel?.cancelEventTriggers()
        self.viewModel = vm

        bindStyle(vm.style, animation: vm.animation)
        bindDynamicBackgroundColor(viewModel: vm)
        bindProperties(vm.propertiesWithVariables)

        // Diff children against existing arranged subviews.
        let newChildren = vm.component.children
        let existingViews = stackView.arrangedSubviews

        for (index, child) in newChildren.enumerated() {
            let childPath = vm.componentPath + "." + child.id
            if index < existingViews.count,
               let updatable = existingViews[index] as? StreamingUpdatable {
                updatable.streamingUpdate(
                    component: child, service: service,
                    parentVariableStore: vm.variableStore,
                    componentPath: childPath, animated: animated
                )
            } else if index < existingViews.count {
                // Type mismatch or non-updatable — replace.
                let old = existingViews[index]
                stackView.removeArrangedSubview(old)
                old.removeFromSuperview()
                let result = service.renderComponent(
                    child, superview: stackView,
                    parentPath: vm.componentPath,
                    parentVariableStore: vm.variableStore
                )
                stackView.insertArrangedSubview(result.view, at: index)
            } else {
                let result = service.renderComponent(
                    child, superview: stackView,
                    parentPath: vm.componentPath,
                    parentVariableStore: vm.variableStore
                )
                stackView.addArrangedSubview(result.view)
            }
        }

        while stackView.arrangedSubviews.count > newChildren.count {
            if let last = stackView.arrangedSubviews.last {
                stackView.removeArrangedSubview(last)
                last.removeFromSuperview()
            }
        }

        // Re-apply current state to propagate childStates now that children exist.
        if let currentState = vm.currentStateName {
            vm.forceReapplyState(currentState)
        }

        setupTapGestureIfNeeded()
        vm.startEventTriggers()
        return vm
    }
}
