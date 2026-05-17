import UIKit
import Combine

class CLabelView: App8BaseView<DSL.Model.Component.Label.C>, CViewProtocol {

    private var viewModel: CLabelViewModel?
    var layoutModeId: String? { viewModel?.componentPath.split(separator: ".").last.map(String.init) }
    var layoutModeContext: App8LayoutMode? { viewModel?.service.context.layoutMode }
    private var propertiesCancellable: AnyCancellable?
    private var variablesCancellable: AnyCancellable?
    weak var materialView: MaterialView?
    let contentView = UIView()
    private let label = UILabel()

    override var intrinsicContentSource: UIView? { label }

    // MARK: - isHidden Expression
    private var isHiddenExpression: String?
    private var lastIsHidden: Bool?

    // MARK: - Background Color (per-property animation)
    private var backgroundColorAnimation: DSL.Model.Animation.Inline?
    private var lastBackgroundColor: UIColor??
    private var hasAppliedBackgroundColorOnce = false

    // MARK: - Text Attributes (letter-spacing / line-height)
    private var textAttributes: [NSAttributedString.Key: Any] = [:]

    // MARK: - Inline span overrides (per-character-range style)
    private var currentSpans: [DSL.Model.Component.Label.Properties.Span]?

    // MARK: - Touch handling
    private var tapGesture: UITapGestureRecognizer?

    override func setup() {
        super.setup()

        // Labels default to non-interactive; enabled below if actions/triggers exist
        isUserInteractionEnabled = false

        // Don't clip — swashed/calligraphic glyphs and pronounced descenders
        // can extend beyond the label's typographic bounds, and we want them
        // visible rather than chopped at the bounding rect.
        clipsToBounds = false
        contentView.clipsToBounds = false
        label.clipsToBounds = false

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()

        contentView.addSubview(label)
        label.cMakeEqualToSuperview()
    }

    func configure(viewModel: CLabelViewModel, superview: UIView? = nil, animated: Bool = true) {
        self.viewModel = viewModel

        guard let superview = superview ?? self.superview else {
            return
        }
        bindLayout(viewModel.layout, in: superview, viewRegistry: viewModel.service.componentRegistry.viewRegistry, parentComponentPath: viewModel.parentPath, keyboardService: viewModel.service.context.keyboardService, animated: animated)
        bindStyle(viewModel.style, animation: viewModel.animation)
        bindProperties(viewModel.propertiesWithVariables)
        bindIsHidden(viewModel: viewModel)
        setupTouchHandlingIfNeeded()
    }

    // MARK: - isHidden Expression

    private func bindIsHidden(viewModel: CLabelViewModel) {
        let props = viewModel.currentProperties
        isHiddenExpression = props.isHidden?.contains("{{") == true ? props.isHidden : nil
        guard isHiddenExpression != nil else { return }

        variablesCancellable = viewModel.variablesChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIsHidden()
            }
        updateIsHidden()
    }

    private func updateIsHidden() {
        guard let viewModel = viewModel,
              let expression = isHiddenExpression else { return }
        let hidden = viewModel.resolvePropertyToBool(expression) ?? false
        guard lastIsHidden != hidden else { return }
        lastIsHidden = hidden
        self.isHidden = hidden
    }

    // MARK: - Touch Handling

    private var shouldHandleTouches: Bool {
        guard let viewModel = viewModel else { return false }
        return viewModel.component.triggers != nil || viewModel.component.actions != nil
    }

    private func setupTouchHandlingIfNeeded() {
        guard shouldHandleTouches, tapGesture == nil else { return }
        isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        tapGesture = tap
    }

    @objc private func handleTap() {
        viewModel?.executeAction(for: .tap)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard shouldHandleTouches else { return }
        viewModel?.fireTrigger(.touchDown)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard shouldHandleTouches else { return }
        viewModel?.fireTrigger(.touchUp)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        guard shouldHandleTouches else { return }
        viewModel?.fireTrigger(.touchUp)
    }

    /// Subscribe to properties changes for text updates (re-resolves when variables change)
    private func bindProperties(_ propertiesPublisher: AnyPublisher<DSL.Model.Component.Label.Properties, Never>) {
        propertiesCancellable?.cancel()
        propertiesCancellable = propertiesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] properties in
                self?.applyProperties(properties)
            }
    }

    /// Apply properties to UI, resolving any {{expressions}} in text
    private func applyProperties(_ properties: DSL.Model.Component.Label.Properties) {
        // Capture spans before setLabelText so it can apply per-range overrides.
        currentSpans = properties.spans
        // Cache the per-property animation descriptor (if supplied via the
        // wrapped form) once per properties update.
        backgroundColorAnimation = properties.backgroundColor?.animation?.inlineOrNil
        guard !(viewModel?.service.context.layoutMode.isEnabled == true) else {
            // Show text at reduced opacity so layout structure is visible.
            // Setting text = nil collapses UILabel.intrinsicContentSize to zero,
            // which makes the label invisible in layout mode.
            // If resolved is empty (e.g. unresolvable {{item.label}} template var),
            // fall back to the raw DSL string so the label keeps non-zero intrinsic width.
            let resolved = viewModel?.resolvePropertyToString(properties.text) ?? properties.text
            setLabelText(resolved.isEmpty ? properties.text : resolved)
            label.textColor = UIColor.label.withAlphaComponent(0.4)
            return
        }
        let resolved = viewModel?.resolvePropertyToString(properties.text) ?? properties.text
        setLabelText(resolved)
        applyBackgroundColor(properties.backgroundColor?.value)
    }

    /// Resolve and apply the background color expression. First apply is
    /// instantaneous; subsequent variable-driven changes route through
    /// `AnimationRunner` using the per-property animation descriptor (or
    /// no animation when none was supplied — matches historic behavior).
    private func applyBackgroundColor(_ expression: String?) {
        let color = expression.flatMap { resolvedExpr -> UIColor? in
            guard let resolved = viewModel?.resolvePropertyToString(resolvedExpr) else { return nil }
            return UIColor(withHexString: resolved)
        }
        // Skip when nothing changed to avoid an unnecessary animation pass.
        if let last = lastBackgroundColor, last == color { return }
        lastBackgroundColor = .some(color)
        let isFirstApply = !hasAppliedBackgroundColorOnce
        hasAppliedBackgroundColorOnce = true
        let animation = isFirstApply ? nil : backgroundColorAnimation
        AnimationRunner.run(
            animation: animation,
            additionalOptions: [.allowUserInteraction],
            viewBlock: { [self] in
                self.backgroundColor = color
            }
        )
    }

    /// Apply text to the label, using attributed string when letter-spacing,
    /// line-height, or per-range span overrides are set.
    private func setLabelText(_ text: String) {
        let hasSpans = (currentSpans?.isEmpty == false)
        if textAttributes.isEmpty && !hasSpans {
            label.attributedText = nil
            label.text = text
        } else {
            let attributed = NSMutableAttributedString(string: text, attributes: textAttributes)
            if let spans = currentSpans, !spans.isEmpty {
                applySpanOverrides(spans, to: attributed)
            }
            label.attributedText = attributed
        }
    }

    /// Apply each span's overrides on top of the base attributes. Out-of-range
    /// indices clamp silently. Spans win over base in their range — last span
    /// in the array wins on overlap.
    private func applySpanOverrides(
        _ spans: [DSL.Model.Component.Label.Properties.Span],
        to attributed: NSMutableAttributedString
    ) {
        let totalLength = attributed.length
        let baseSize = label.font?.pointSize ?? 17
        for span in spans {
            let from = max(0, min(span.from, totalLength))
            let to = max(from, min(span.to, totalLength))
            guard to > from else { continue }
            let range = NSRange(location: from, length: to - from)
            if let family = span.fontFamily, let font = UIFont(name: family, size: baseSize) {
                attributed.addAttribute(.font, value: font, range: range)
            }
            if let hex = span.color, let color = UIColor(withHexString: hex) {
                attributed.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
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

        // Applied always, so font/size/numberOfLines are correct in layout mode too.
        if let textModel = style?.text {
            applyTextModel(textModel)
        }
    }

    private func applyTextModel(_ textModel: DSL.Model.Style.TextModel) {
        if let alignment = textModel.alignment {
            label.textAlignment = alignment.ui
        }

        // Color is skipped in layout mode; applyProperties sets a semi-transparent color instead.
        if !(viewModel?.service.context.layoutMode.isEnabled == true), let themedColor = textModel.color {
            label.textColor = themedColor.ui
        }

        label.font = textModel.resolveUIFont()
        label.numberOfLines = textModel.numberOfLines ?? 0
        textAttributes = buildTextAttributes(for: textModel)

        if let currentText = label.attributedText?.string ?? label.text {
            setLabelText(currentText)
        }
    }

    /// Compute NSAttributedString attributes for letter-spacing and line-height.
    /// Returns empty when neither is configured (caller then uses plain text).
    private func buildTextAttributes(for textModel: DSL.Model.Style.TextModel) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [:]

        if let letterSpacing = textModel.letterSpacing, letterSpacing.type == .fixed {
            attrs[.kern] = letterSpacing.value
        }

        if let lineHeight = textModel.lineHeight {
            let paragraphStyle = NSMutableParagraphStyle()
            switch lineHeight.type {
            case .fixed:
                paragraphStyle.minimumLineHeight = lineHeight.value
                paragraphStyle.maximumLineHeight = lineHeight.value
            case .multiplier:
                paragraphStyle.lineHeightMultiple = lineHeight.value
            case .interLineSpacing:
                paragraphStyle.lineSpacing = lineHeight.value
            case .fontSizeFraction:
                paragraphStyle.lineSpacing = textModel.fontSize * lineHeight.value
            case .auto:
                // No paragraph style needed
                return attrs
            }
            if let alignment = textModel.alignment {
                paragraphStyle.alignment = alignment.ui
            }
            attrs[.paragraphStyle] = paragraphStyle
        }

        return attrs
    }

}

// MARK: - StreamingUpdatable

extension CLabelView: StreamingUpdatable {

    /// Updates text and style in-place for a streaming diff hit (same id, same type).
    /// Does NOT rebind layout — constraints are preserved as-is.
    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CLabelViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }

        self.viewModel = vm
        bindStyle(vm.style, animation: vm.animation)

        let currentProps = vm.currentProperties
        if animated {
            UIView.transition(with: self, duration: 0.2, options: [.transitionCrossDissolve]) {
                self.applyProperties(currentProps)
            }
        } else {
            applyProperties(currentProps)
        }
        bindProperties(vm.propertiesWithVariables)
        return vm
    }
}

extension DSL.Model.Style.TextModel.Alignment {

    var ui: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .justified: return .justified
        case .natural: return .natural
        }
    }
}
