//
//  CToggleView.swift
//  App8Engine
//

import UIKit
import Combine

class CToggleView: App8BaseView<DSL.Model.Component.Toggle.C>, CViewProtocol {

    weak var materialView: MaterialView?
    let contentView = UIView()
    private let toggle = UISwitch()

    override var intrinsicContentSource: UIView? { toggle }

    private var viewModel: CToggleViewModel?
    private var propertiesCancellable: AnyCancellable?
    private var variablesCancellable: AnyCancellable?
    private var externalUpdateCancellable: AnyCancellable?

    // MARK: - Setup

    override func setup() {
        super.setup()

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()

        contentView.addSubview(toggle)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toggle.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        toggle.addTarget(self, action: #selector(switchValueChanged), for: .valueChanged)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if toggle.frame.contains(point) { return true }
        return super.point(inside: point, with: event)
    }

    // MARK: - Configure

    func configure(viewModel: CToggleViewModel, superview: UIView? = nil, animated: Bool = true) {
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

        toggle.isOn = viewModel.currentIsOn

        externalUpdateCancellable = viewModel.externalToggleUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.toggle.setOn(value, animated: true)
            }

        propertiesCancellable = viewModel.propertiesWithVariables
            .receive(on: DispatchQueue.main)
            .sink { [weak self] properties in
                self?.applyProperties(properties)
            }
    }

    // MARK: - Properties

    private func applyProperties(_ properties: Content.Properties) {
        guard let vm = viewModel else { return }
        if let enabledExpr = properties.isEnabled {
            toggle.isEnabled = vm.resolvePropertyToBool(enabledExpr) ?? true
        }
    }

    // MARK: - Interaction

    @objc private func switchValueChanged() {
        viewModel?.toggleChanged.send(toggle.isOn)
        viewModel?.executeAction(for: .tap)
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

        if let hex = style?.onTintColor, let color = UIColor(withHexString: hex) {
            toggle.onTintColor = color
        }
        if let hex = style?.thumbTintColor, let color = UIColor(withHexString: hex) {
            toggle.thumbTintColor = color
        }
    }
}

// MARK: - StreamingUpdatable

extension CToggleView: StreamingUpdatable {

    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CToggleViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }

        self.viewModel = vm
        toggle.isOn = vm.currentIsOn
        bindStyle(vm.style, animation: vm.animation)

        externalUpdateCancellable = vm.externalToggleUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.toggle.setOn(value, animated: true)
            }
        propertiesCancellable = vm.propertiesWithVariables
            .receive(on: DispatchQueue.main)
            .sink { [weak self] properties in
                self?.applyProperties(properties)
            }
        return vm
    }
}
