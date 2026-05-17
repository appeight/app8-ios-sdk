//
//  CSliderView.swift
//  App8Engine
//

import UIKit
import Combine

class CSliderView: App8BaseView<DSL.Model.Component.Slider.C>, CViewProtocol {

    weak var materialView: MaterialView?
    let contentView = UIView()
    private let slider = UISlider()
    private var viewModel: CSliderViewModel?
    private var propertiesCancellable: AnyCancellable?
    private var externalUpdateCancellable: AnyCancellable?

    // MARK: - Setup

    override func setup() {
        super.setup()

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()

        contentView.addSubview(slider)
        slider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            slider.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: slider.intrinsicContentSize.height)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if slider.frame.contains(point) { return true }
        return super.point(inside: point, with: event)
    }

    // MARK: - Configure

    func configure(viewModel: CSliderViewModel, superview: UIView? = nil, animated: Bool = true) {
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

        let props = viewModel.currentProperties
        slider.minimumValue = props.minimumValue ?? 0
        slider.maximumValue = props.maximumValue ?? 1
        slider.value = viewModel.currentValue

        externalUpdateCancellable = viewModel.externalSliderUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.slider.setValue(value, animated: true)
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
            slider.isEnabled = vm.resolvePropertyToBool(enabledExpr) ?? true
        }
    }

    // MARK: - Interaction

    @objc private func sliderValueChanged() {
        viewModel?.sliderChanged.send(slider.value)
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

        if let hex = style?.minimumTrackTintColor, let color = UIColor(withHexString: hex) {
            slider.minimumTrackTintColor = color
        }
        if let hex = style?.maximumTrackTintColor, let color = UIColor(withHexString: hex) {
            slider.maximumTrackTintColor = color
        }
        if let hex = style?.thumbTintColor, let color = UIColor(withHexString: hex) {
            slider.thumbTintColor = color
        }
    }
}

// MARK: - StreamingUpdatable

extension CSliderView: StreamingUpdatable {

    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CSliderViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }

        self.viewModel = vm
        let props = vm.currentProperties
        slider.minimumValue = props.minimumValue ?? 0
        slider.maximumValue = props.maximumValue ?? 1
        slider.value = vm.currentValue
        bindStyle(vm.style, animation: vm.animation)

        externalUpdateCancellable = vm.externalSliderUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.slider.setValue(value, animated: true)
            }
        propertiesCancellable = vm.propertiesWithVariables
            .receive(on: DispatchQueue.main)
            .sink { [weak self] properties in
                self?.applyProperties(properties)
            }
        return vm
    }
}
