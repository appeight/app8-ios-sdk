//
//  CPickerView.swift
//  App8Engine
//

import UIKit
import Combine

class CPickerView: App8BaseView<DSL.Model.Component.Picker.C>, CViewProtocol {

    weak var materialView: MaterialView?
    let contentView = UIView()

    private var menuButton: UIButton?
    private var segmentedControl: UISegmentedControl?

    override var intrinsicContentSource: UIView? { menuButton ?? segmentedControl }

    private var viewModel: CPickerViewModel?
    private var propertiesCancellable: AnyCancellable?
    private var variablesCancellable: AnyCancellable?
    private var externalUpdateCancellable: AnyCancellable?

    // MARK: - Setup

    override func setup() {
        super.setup()

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if let button = menuButton, button.frame.contains(point) { return true }
        if let sc = segmentedControl, sc.frame.contains(point) { return true }
        return super.point(inside: point, with: event)
    }

    // MARK: - Configure

    func configure(viewModel: CPickerViewModel, superview: UIView? = nil, animated: Bool = true) {
        guard let superview = superview ?? self.superview else { return }

        menuButton?.removeFromSuperview()
        segmentedControl?.removeFromSuperview()
        menuButton = nil
        segmentedControl = nil

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

        let mode = viewModel.currentProperties.displayMode ?? .menu
        switch mode {
        case .menu:
            setupMenuMode(viewModel: viewModel)
        case .segmented:
            setupSegmentedMode(viewModel: viewModel)
        }

        externalUpdateCancellable = viewModel.externalSelectionUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.updateSelection(value)
            }

        propertiesCancellable = viewModel.propertiesWithVariables
            .receive(on: DispatchQueue.main)
            .sink { [weak self] properties in
                self?.applyProperties(properties)
            }
    }

    // MARK: - Menu Mode

    private func setupMenuMode(viewModel: CPickerViewModel) {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = true

        let options = viewModel.currentProperties.options ?? []
        let actions = options.map { option in
            let action = UIAction(title: option.label) { [weak self] _ in
                self?.viewModel?.selectionChanged.send(option.value)
            }
            if option.value == viewModel.currentSelection {
                action.state = .on
            }
            if let iconName = option.icon {
                action.image = UIImage(systemName: iconName)
            }
            return action
        }

        button.menu = UIMenu(children: actions)

        let selectedLabel = options.first(where: { $0.value == viewModel.currentSelection })?.label
        button.setTitle(selectedLabel ?? viewModel.currentProperties.placeholder ?? "Select", for: .normal)

        contentView.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            button.topAnchor.constraint(equalTo: contentView.topAnchor),
            button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        self.menuButton = button
    }

    // MARK: - Segmented Mode

    private func setupSegmentedMode(viewModel: CPickerViewModel) {
        let options = viewModel.currentProperties.options ?? []
        let sc = UISegmentedControl(items: options.map { $0.label })

        if let selectedIndex = options.firstIndex(where: { $0.value == viewModel.currentSelection }) {
            sc.selectedSegmentIndex = selectedIndex
        }

        sc.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)

        contentView.addSubview(sc)
        sc.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sc.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sc.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            sc.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        self.segmentedControl = sc
    }

    @objc private func segmentChanged() {
        guard let sc = segmentedControl,
              let options = viewModel?.currentProperties.options,
              sc.selectedSegmentIndex < options.count else { return }
        viewModel?.selectionChanged.send(options[sc.selectedSegmentIndex].value)
    }

    // MARK: - Update Selection

    private func updateSelection(_ value: String) {
        guard let options = viewModel?.currentProperties.options else { return }

        if let button = menuButton {
            let label = options.first(where: { $0.value == value })?.label ?? value
            button.setTitle(label, for: .normal)
        }

        if let sc = segmentedControl,
           let index = options.firstIndex(where: { $0.value == value }) {
            sc.selectedSegmentIndex = index
        }
    }

    // MARK: - Properties

    private func applyProperties(_ properties: Content.Properties) {
        guard let vm = viewModel else { return }
        if let enabledExpr = properties.isEnabled {
            let enabled = vm.resolvePropertyToBool(enabledExpr) ?? true
            menuButton?.isEnabled = enabled
            segmentedControl?.isEnabled = enabled
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

        if let textModel = style?.text, let button = menuButton {
            button.titleLabel?.font = textModel.resolveUIFont()
            if let color = textModel.color {
                button.setTitleColor(color.ui, for: .normal)
            }
        }

        if let hex = style?.selectedSegmentTintColor, let color = UIColor(withHexString: hex) {
            segmentedControl?.selectedSegmentTintColor = color
        }
    }
}

// MARK: - StreamingUpdatable

extension CPickerView: StreamingUpdatable {

    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CPickerViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }

        menuButton?.removeFromSuperview()
        segmentedControl?.removeFromSuperview()
        menuButton = nil
        segmentedControl = nil

        self.viewModel = vm
        bindStyle(vm.style, animation: vm.animation)

        let mode = vm.currentProperties.displayMode ?? .menu
        switch mode {
        case .menu: setupMenuMode(viewModel: vm)
        case .segmented: setupSegmentedMode(viewModel: vm)
        }

        externalUpdateCancellable = vm.externalSelectionUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.updateSelection(value)
            }
        propertiesCancellable = vm.propertiesWithVariables
            .receive(on: DispatchQueue.main)
            .sink { [weak self] properties in
                self?.applyProperties(properties)
            }
        return vm
    }
}
