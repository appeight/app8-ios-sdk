import UIKit
import Combine

class CDatePickerView: App8BaseView<DSL.Model.Component.DatePicker.C>, CViewProtocol {

    weak var materialView: MaterialView?
    let contentView = UIView()
    private let datePicker = UIDatePicker()

    override var intrinsicContentSource: UIView? { datePicker }

    private var viewModel: CDatePickerViewModel?
    private var propertiesCancellable: AnyCancellable?
    private var externalUpdateCancellable: AnyCancellable?

    // MARK: - Setup

    override func setup() {
        super.setup()

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()

        contentView.addSubview(datePicker)
        datePicker.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            datePicker.topAnchor.constraint(equalTo: contentView.topAnchor),
            datePicker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            datePicker.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            datePicker.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        datePicker.addTarget(self, action: #selector(dateValueChanged), for: .valueChanged)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if datePicker.frame.contains(point) { return true }
        return super.point(inside: point, with: event)
    }

    // MARK: - Configure

    func configure(viewModel: CDatePickerViewModel, superview: UIView? = nil, animated: Bool = true) {
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

        switch props.datePickerMode ?? .date {
        case .date: datePicker.datePickerMode = .date
        case .time: datePicker.datePickerMode = .time
        case .dateAndTime: datePicker.datePickerMode = .dateAndTime
        case .countdownTimer: datePicker.datePickerMode = .countDownTimer
        }

        switch props.displayStyle ?? .compact {
        case .compact: datePicker.preferredDatePickerStyle = .compact
        case .inline: datePicker.preferredDatePickerStyle = .inline
        case .wheels: datePicker.preferredDatePickerStyle = .wheels
        }

        if let minStr = props.minimumDate, let min = viewModel.parseDate(minStr) {
            datePicker.minimumDate = min
        }
        if let maxStr = props.maximumDate, let max = viewModel.parseDate(maxStr) {
            datePicker.maximumDate = max
        }

        datePicker.date = viewModel.currentDate

        externalUpdateCancellable = viewModel.externalDateUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] date in
                self?.datePicker.setDate(date, animated: true)
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
            datePicker.isEnabled = vm.resolvePropertyToBool(enabledExpr) ?? true
        }
    }

    // MARK: - Interaction

    @objc private func dateValueChanged() {
        viewModel?.dateChanged.send(datePicker.date)
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

        if let hex = style?.tintColor, let color = UIColor(withHexString: hex) {
            datePicker.tintColor = color
        }
    }
}

// MARK: - StreamingUpdatable

extension CDatePickerView: StreamingUpdatable {

    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CDatePickerViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }

        self.viewModel = vm
        datePicker.date = vm.currentDate
        bindStyle(vm.style, animation: vm.animation)

        externalUpdateCancellable = vm.externalDateUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] date in
                self?.datePicker.setDate(date, animated: true)
            }
        propertiesCancellable = vm.propertiesWithVariables
            .receive(on: DispatchQueue.main)
            .sink { [weak self] properties in
                self?.applyProperties(properties)
            }
        return vm
    }
}
