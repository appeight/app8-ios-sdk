import UIKit
import Combine

class CButtonView: App8BaseView<DSL.Model.Component.Button.C>, CViewProtocol {

    weak var materialView: MaterialView?
    let contentView = UIView()
    private let button = UIButton(type: .system)
    private var viewModel: CButtonViewModel?  // strong ref keeps viewModel alive
    private var propertiesCancellable: AnyCancellable?

    /// `true` while a `style.system` configuration owns the button's appearance.
    /// Title/subtitle are then injected into `button.configuration` rather than via
    /// `setTitle(_:for:)`, so content survives independent style/property updates.
    private var usesSystemConfig = false
    private var currentTitle: String = ""
    private var currentSubtitle: String?

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
        currentTitle = viewModel?.resolvePropertyToString(properties.text) ?? properties.text

        let isEnabled = properties.isEnabled.flatMap { viewModel?.resolvePropertyToBool($0) } ?? true
        let isSelected = properties.isSelected.flatMap { viewModel?.resolvePropertyToBool($0) } ?? false
        button.isEnabled = isEnabled
        button.isSelected = isSelected
        // System configs dim themselves when disabled; the Material path doesn't, so
        // reflect the disabled state by dimming the button's own content.
        button.alpha = (usesSystemConfig || isEnabled) ? 1.0 : 0.4

        refreshButtonContent()
    }

    /// Applies the current title/subtitle to whichever rendering path is active.
    /// Ordering-independent: works whether style or properties were applied first.
    private func refreshButtonContent() {
        if usesSystemConfig, button.configuration != nil {
            button.configuration?.title = currentTitle
            button.configuration?.subtitle = currentSubtitle
        } else {
            button.setTitle(currentTitle, for: .normal)
        }
    }

    // MARK: - Touch Triggers

    /// Whether this button has custom press states defined in DSL, or a system
    /// configuration that supplies its own highlighted/disabled appearance. In
    /// either case the built-in alpha press feedback is suppressed.
    private var hasCustomPressStates: Bool {
        viewModel?.component.triggers != nil || usesSystemConfig
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

        if let system = style?.system {
            applySystemConfiguration(system, textModel: style?.text)
        } else if usesSystemConfig {
            // Reverted to the Material path (e.g. via a streaming update).
            usesSystemConfig = false
            button.configuration = nil
        }

        // Material background layers are ignored in the system path (the configuration
        // owns the background/corner), but alpha/transform/shadow still apply.
        applyBaseStyle(style, animated: animated, duration: duration, options: options, useSpring: useSpring)

        if !usesSystemConfig, let textModel = style?.text {
            applyTextModel(textModel)
        }
    }

    /// Renders the button via `UIButton.Configuration`, giving it the native system
    /// look (filled / tinted / bordered / the iOS 26 glassy capsule, …) plus the
    /// system's automatic highlighted/disabled appearance.
    private func applySystemConfiguration(
        _ system: DSL.Model.Style.SystemButton,
        textModel: DSL.Model.Style.TextModel?
    ) {
        usesSystemConfig = true
        var configuration = system.makeConfiguration()
        configuration.image = system.image?.resolved()

        if let subtitleExpr = system.subtitle {
            currentSubtitle = viewModel?.resolvePropertyToString(subtitleExpr) ?? subtitleExpr
        } else {
            currentSubtitle = nil
        }
        if let indicatorExpr = system.showsActivityIndicator,
           let shows = viewModel?.resolvePropertyToBool(indicatorExpr) {
            configuration.showsActivityIndicator = shows
        }

        // Honour an explicit `style.text` font/colour on top of the configuration.
        if let textModel {
            let font = textModel.resolveUIFont()
            let color = textModel.color?.ui
            configuration.titleTextAttributesTransformer = .init { incoming in
                var outgoing = incoming
                outgoing.font = font
                if let color { outgoing.foregroundColor = color }
                return outgoing
            }
        }

        button.configuration = configuration
        if #available(iOS 26.0, *), let role = system.uiRole {
            button.role = role
        }
        refreshButtonContent()
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
