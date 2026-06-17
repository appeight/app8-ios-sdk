import UIKit
import Combine

class CView: App8BaseView<DSL.Model.Component.View.C>, CViewProtocol, StreamingUpdatable {

    private var viewModel: CViewModel?
    var layoutModeId: String? { viewModel?.componentPath.split(separator: ".").last.map(String.init) }
    var layoutModeContext: App8LayoutMode? { viewModel?.service.context.layoutMode }
    weak var materialView: MaterialView?
    let contentView = UIView()

    /// Rendered children by component id → (view, type name), used for diffing.
    private var trackedChildren: [String: (view: UIView, typeName: String)] = [:]

    private lazy var dynamicBackgroundView: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }()

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Transform Expressions

    private var transformScaleExpression: String?
    private var transformTranslateXExpression: String?
    private var transformTranslateYExpression: String?

    /// Per-property animation descriptors. The three transform expressions share
    /// one `updateTransform()` call, so the first non-nil descriptor drives them
    /// all. When all are nil, the update falls back to `.legacyTransformVariableUpdate`.
    private var transformScaleAnimation: DSL.Model.Animation.Inline?
    private var transformTranslateXAnimation: DSL.Model.Animation.Inline?
    private var transformTranslateYAnimation: DSL.Model.Animation.Inline?

    private var lastTransformScale: CGFloat?
    private var lastTranslateX: CGFloat?
    private var lastTranslateY: CGFloat?

    // MARK: - isHidden Expression

    private var isHiddenExpression: String?
    private var lastIsHidden: Bool?

    // MARK: - Alpha Expression

    private var alphaExpression: String?

    /// Nil → legacy fallback (`.legacyAlphaVariableUpdate`).
    private var alphaAnimation: DSL.Model.Animation.Inline?

    private var lastAlpha: CGFloat?

    // MARK: - Background Color (dynamic / expression-driven)

    /// Nil → instantaneous, matching the historic behavior of `applyDynamicBackgroundColor`.
    private var backgroundColorAnimation: DSL.Model.Animation.Inline?

    // MARK: - Dynamic Dimensions

    private var dynamicWidthExpression: String?
    private var dynamicHeightExpression: String?
    /// True when a dimension expression references its own axis geometry
    /// (`view.width` in a width expr) — excluded from layout-triggered
    /// re-resolution to avoid an infinite layout loop.
    private var widthExprSelfReferential = false
    private var heightExprSelfReferential = false

    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    private var lastDynamicWidth: CGFloat?
    private var lastDynamicHeight: CGFloat?

    override func setup() {
        super.setup()
        addSubview(contentView)
        contentView.cMakeEqualToSuperview()
    }

    func configure(viewModel: CViewModel, superview: UIView? = nil, animated: Bool = true) {
        self.viewModel = viewModel
        viewModel.geometryProvider = { [weak self] in self?.bounds.size ?? .zero }

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
        bindTransformExpression(viewModel: viewModel)
        bindIsHiddenExpression(viewModel: viewModel)
        bindAlphaExpression(viewModel: viewModel)
        bindDynamicDimensions(viewModel: viewModel)
        configureContent(viewModel: viewModel, animated: animated)
        setupTapGestureIfNeeded()
        setupGestureBindingsIfNeeded()
        viewModel.startEventTriggers()
    }

    override func removeFromSuperview() {
        viewModel?.cancelEventTriggers()
        super.removeFromSuperview()
    }

    // MARK: - Dynamic Background Color

    private func bindDynamicBackgroundColor(viewModel: CViewModel) {
        // Cache the per-property animation descriptor (if any) so subsequent
        // variable-driven color updates animate via AnimationRunner. First-time
        // application (when the dynamic background view is added) is forced
        // instantaneous regardless — there's no meaningful "from" color.
        backgroundColorAnimation = viewModel.component.properties.backgroundColor?.animation?.inlineOrNil

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

        let isFirstApply = dynamicBackgroundView.superview == nil

        if isFirstApply {
            insertSubview(dynamicBackgroundView, at: 0)
            dynamicBackgroundView.cMakeEqualToSuperview()
        }

        if let radius = cornerRadius {
            dynamicBackgroundView.layer.cornerRadius = radius
            dynamicBackgroundView.layer.cornerCurve = .continuous
            dynamicBackgroundView.clipsToBounds = true
            // Don't set self.clipsToBounds — contentView.layer.masksToBounds handles
            // child clipping via cornerStyle, and MaterialView's shadow sublayers
            // need to extend beyond self.bounds to render properly.
        }

        // First apply (or no descriptor) is instantaneous; subsequent variable
        // changes animate when an `animation` was supplied in the JSON.
        let animation = isFirstApply ? nil : backgroundColorAnimation
        AnimationRunner.run(
            animation: animation,
            additionalOptions: [.allowUserInteraction],
            viewBlock: { [self] in
                self.dynamicBackgroundView.backgroundColor = color
            }
        )
    }

    // MARK: - Transform Expressions

    private func bindTransformExpression(viewModel: CViewModel) {
        let props = viewModel.component.properties

        transformScaleExpression = props.transformScale?.value.contains("{{") == true ? props.transformScale?.value : nil
        transformTranslateXExpression = props.transformTranslateX?.value.contains("{{") == true ? props.transformTranslateX?.value : nil
        transformTranslateYExpression = props.transformTranslateY?.value.contains("{{") == true ? props.transformTranslateY?.value : nil

        transformScaleAnimation = props.transformScale?.animation?.inlineOrNil
        transformTranslateXAnimation = props.transformTranslateX?.animation?.inlineOrNil
        transformTranslateYAnimation = props.transformTranslateY?.animation?.inlineOrNil

        guard transformScaleExpression != nil ||
              transformTranslateXExpression != nil ||
              transformTranslateYExpression != nil else {
            return
        }

        // .prepend forces an initial evaluation.
        viewModel.variablesChanged
            .prepend("")
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTransform()
            }
            .store(in: &cancellables)
    }

    private func updateTransform() {
        guard let viewModel = viewModel else { return }

        let scale = transformScaleExpression.flatMap { viewModel.resolvePropertyToFloat($0) } ?? 1.0
        let translateX = transformTranslateXExpression.flatMap { viewModel.resolvePropertyToFloat($0) } ?? 0.0
        let translateY = transformTranslateYExpression.flatMap { viewModel.resolvePropertyToFloat($0) } ?? 0.0

        if lastTransformScale == scale && lastTranslateX == translateX && lastTranslateY == translateY {
            return
        }

        // Nil last values = first apply after bind (or after reset); don't animate.
        let isInitial = lastTransformScale == nil && lastTranslateX == nil && lastTranslateY == nil

        lastTransformScale = scale
        lastTranslateX = translateX
        lastTranslateY = translateY

        // Translate first, then scale — order matters.
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: translateX, y: translateY)
        transform = transform.scaledBy(x: scale, y: scale)

        if isInitial {
            self.transform = transform
            return
        }

        // Per-property animation precedence: scale > translateX > translateY.
        // Falls back to the legacy 0.3s spring (damping 0.75, velocity 0.3) so
        // existing screens animate identically to before.
        let animation = transformScaleAnimation
            ?? transformTranslateXAnimation
            ?? transformTranslateYAnimation
            ?? .legacyTransformVariableUpdate
        AnimationRunner.run(
            animation: animation,
            additionalOptions: [.allowUserInteraction],
            viewBlock: { [self] in
                self.transform = transform
            }
        )
    }

    // MARK: - isHidden Expression

    private func bindIsHiddenExpression(viewModel: CViewModel) {
        let props = viewModel.component.properties

        isHiddenExpression = props.isHidden?.contains("{{") == true ? props.isHidden : nil

        guard isHiddenExpression != nil else { return }

        viewModel.variablesChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIsHidden()
            }
            .store(in: &cancellables)

        updateIsHidden()
    }

    private func updateIsHidden() {
        guard let viewModel = viewModel,
              let expression = isHiddenExpression else { return }

        let hidden = viewModel.resolvePropertyToBool(expression) ?? false

        if lastIsHidden == hidden { return }
        lastIsHidden = hidden

        self.isHidden = hidden
    }

    // MARK: - Alpha Expression

    private func bindAlphaExpression(viewModel: CViewModel) {
        let props = viewModel.component.properties

        alphaExpression = props.alpha?.value.contains("{{") == true ? props.alpha?.value : nil
        alphaAnimation = props.alpha?.animation?.inlineOrNil

        guard alphaExpression != nil else { return }

        // .prepend forces an initial evaluation.
        viewModel.variablesChanged
            .prepend("")
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAlpha()
            }
            .store(in: &cancellables)
    }

    private func updateAlpha() {
        guard let viewModel = viewModel,
              let expression = alphaExpression else { return }

        let alphaValue = viewModel.resolvePropertyToFloat(expression) ?? 1.0

        if lastAlpha == alphaValue { return }
        // Nil lastAlpha = first apply after bind (or after reset); don't animate.
        let isInitial = lastAlpha == nil
        lastAlpha = alphaValue

        if isInitial {
            self.alpha = alphaValue
            return
        }

        // Per-property `animation` wins; otherwise fall back to the historic
        // 0.25s easeOut so existing screens animate identically.
        let animation = alphaAnimation ?? .legacyAlphaVariableUpdate
        AnimationRunner.run(
            animation: animation,
            additionalOptions: [.allowUserInteraction],
            viewBlock: { [self] in
                self.alpha = alphaValue
            }
        )
    }

    // MARK: - Dynamic Dimensions

    private var lastLaidOutSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        // When the view resizes, re-resolve dimension expressions that may
        // reference the component's own geometry (`view.width` / `view.height`).
        // `updateDynamicDimensions` is cached, so a stable size is a no-op.
        if bounds.size != lastLaidOutSize {
            lastLaidOutSize = bounds.size
            if dynamicWidthExpression != nil || dynamicHeightExpression != nil {
                updateDynamicDimensions(fromLayout: true)
            }
        }
    }

    private func bindDynamicDimensions(viewModel: CViewModel) {
        let layout = viewModel.component.layout

        if case .expression(let expr) = layout?.width {
            dynamicWidthExpression = expr
        }

        if case .expression(let expr) = layout?.height {
            dynamicHeightExpression = expr
        }

        guard dynamicWidthExpression != nil || dynamicHeightExpression != nil else { return }

        // A dimension expression that references its OWN axis geometry
        // (`width` reading `view.width`) is circular: re-resolving it from
        // layoutSubviews would set the constraint, trigger layout, and re-resolve
        // forever. Such axes resolve once + on variable changes only, never from
        // the layout pass.
        widthExprSelfReferential = dynamicWidthExpression?.contains("view.width") ?? false
        heightExprSelfReferential = dynamicHeightExpression?.contains("view.height") ?? false

        viewModel.variablesChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDynamicDimensions()
            }
            .store(in: &cancellables)

        updateDynamicDimensions()
    }

    private func updateDynamicDimensions(fromLayout: Bool = false) {
        guard let viewModel = viewModel else { return }

        if let widthExpr = dynamicWidthExpression, !(fromLayout && widthExprSelfReferential),
           let width = viewModel.resolvePropertyToFloat(widthExpr) {
            if lastDynamicWidth != width {
                lastDynamicWidth = width
                updateWidthConstraint(width)
            }
        }

        if let heightExpr = dynamicHeightExpression, !(fromLayout && heightExprSelfReferential),
           let height = viewModel.resolvePropertyToFloat(heightExpr) {
            if lastDynamicHeight != height {
                lastDynamicHeight = height
                updateHeightConstraint(height)
            }
        }
    }

    private func updateWidthConstraint(_ width: CGFloat) {
        if let existing = widthConstraint {
            existing.constant = width
        } else {
            widthConstraint = widthAnchor.constraint(equalToConstant: width)
            widthConstraint?.isActive = true
        }
    }

    private func updateHeightConstraint(_ height: CGFloat) {
        if let existing = heightConstraint {
            existing.constant = height
        } else {
            heightConstraint = heightAnchor.constraint(equalToConstant: height)
            heightConstraint?.isActive = true
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
        // applyBaseStyle reset self.alpha/transform to defaults; the caches still hold
        // the old expression values, so reset them first or the "no change" guard skips.
        if alphaExpression != nil {
            lastAlpha = nil
            updateAlpha()
        }
        if transformScaleExpression != nil || transformTranslateXExpression != nil || transformTranslateYExpression != nil {
            lastTransformScale = nil
            lastTranslateX = nil
            lastTranslateY = nil
            updateTransform()
        }
    }
    
    // MARK: - Content Diffing

    private func configureContent(viewModel: CViewModel, animated: Bool = false) {
        let newChildren = viewModel.component.children

        // Remove children that are gone or whose type changed.
        var toRemove: [String] = []
        for (id, tracked) in trackedChildren {
            if let newChild = newChildren.first(where: { $0.id == id }) {
                if typeName(for: newChild.type) != tracked.typeName {
                    toRemove.append(id)
                }
            } else {
                toRemove.append(id)
            }
        }
        for id in toRemove {
            if let tracked = trackedChildren.removeValue(forKey: id) {
                if animated {
                    animateOutAndRemove(tracked.view)
                } else {
                    tracked.view.removeFromSuperview()
                }
            }
        }

        for child in newChildren {
            if let tracked = trackedChildren[child.id] {
                // Same id — update in-place if same type and the view supports it.
                if typeName(for: child.type) == tracked.typeName,
                   let updatable = tracked.view as? StreamingUpdatable {
                    let childPath = viewModel.componentPath + "." + child.id
                    updatable.streamingUpdate(
                        component: child,
                        service: viewModel.service,
                        parentVariableStore: viewModel.variableStore,
                        componentPath: childPath,
                        animated: animated
                    )
                }
                continue
            }
            let result = viewModel.service.renderComponent(
                child,
                superview: contentView,
                parentPath: viewModel.componentPath,
                parentVariableStore: viewModel.variableStore
            )
            trackedChildren[child.id] = (result.view, typeName(for: result.type))
            if animated {
                animateIn(result.view)
            }
        }

        // Re-apply current state to propagate childStates now that children exist.
        if let currentState = viewModel.currentStateName {
            viewModel.forceReapplyState(currentState)
        }
    }

    private func typeName(for ctype: DSL.Model.Component.CType) -> String {
        switch ctype {
        case .key(let key): return key.rawValue
        case .custom(let name): return name
        }
    }

    private func animateIn(_ view: UIView) {
        view.alpha = 0
        view.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0) {
            view.alpha = 1
            view.transform = .identity
        }
    }

    private func animateOutAndRemove(_ view: UIView) {
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            view.alpha = 0
            view.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        } completion: { _ in
            view.removeFromSuperview()
        }
    }

    /// Re-diffs children against the new viewModel and re-applies the root style.
    /// Used by ScreenUpdater to apply streaming structural and style updates to the existing root view.
    func reconfigure(viewModel: CViewModel, animated: Bool) {
        self.viewModel?.cancelEventTriggers()
        // Cancel stale subscriptions from the previous VM to prevent leaked work.
        cancellables.removeAll()
        self.viewModel = viewModel
        bindStyle(viewModel.style, animation: viewModel.animation)
        bindDynamicBackgroundColor(viewModel: viewModel)
        configureContent(viewModel: viewModel, animated: animated)
        setupTapGestureIfNeeded()
        setupGestureBindingsIfNeeded()
        viewModel.startEventTriggers()
    }

    // MARK: - StreamingUpdatable

    /// Allows this CView to be updated in-place when a parent CView's diff finds it
    /// as a stable (same-id, same-type) child. Delegates to reconfigure().
    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }
        reconfigure(viewModel: vm, animated: animated)
        return vm
    }

    // MARK: - Touch Triggers

    private var tapGesture: UITapGestureRecognizer?
    private var longPressGesture: UILongPressGestureRecognizer?

    private var shouldHandleTouches: Bool {
        guard let viewModel = viewModel else { return false }
        let hasTriggers = viewModel.component.triggers != nil
        let hasActions = viewModel.component.actions != nil
        return hasTriggers || hasActions
    }

    private func setupTapGestureIfNeeded() {
        guard shouldHandleTouches else { return }
        if tapGesture == nil {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
            addGestureRecognizer(tap)
            tapGesture = tap
        }
        // Only attach a long press recognizer if a .longPress action is configured,
        // to avoid interfering with scrolling or other gestures on views that don't need it.
        if longPressGesture == nil, viewModel?.component.actions?[.longPress] != nil {
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressGesture(_:)))
            lp.minimumPressDuration = 0.5
            addGestureRecognizer(lp)
            longPressGesture = lp
        }
    }

    @objc private func handleTapGesture(_ gesture: UITapGestureRecognizer) {
        viewModel?.service.context.logger.debug("CView.handleTapGesture: \(viewModel?.componentPath ?? "unknown")")
        viewModel?.executeAction(for: .tap)
    }

    @objc private func handleLongPressGesture(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        viewModel?.service.context.logger.debug("CView.handleLongPressGesture: \(viewModel?.componentPath ?? "unknown")")
        viewModel?.executeAction(for: .longPress)
    }

    // MARK: - Gesture Bindings (continuous → variables)

    private var panBindingGesture: UIPanGestureRecognizer?
    private var panTapBindingGesture: UITapGestureRecognizer?

    /// Install recognizers for `content.gestures.pan` when present. Separate
    /// from `setupTapGestureIfNeeded` (which drives `actions.tap`): these
    /// recognizers stream raw quantities into variables and coexist with the
    /// action tap via simultaneous recognition.
    private func setupGestureBindingsIfNeeded() {
        guard let pan = viewModel?.component.gestures?.pan, pan.hasBindings else { return }
        if panBindingGesture == nil {
            let g = UIPanGestureRecognizer(target: self, action: #selector(handlePanBinding(_:)))
            g.delegate = self
            addGestureRecognizer(g)
            panBindingGesture = g
        }
        // A stationary tap is a zero-distance drag; let it set location bindings
        // too (tap-to-set), without disturbing translation/velocity.
        if panTapBindingGesture == nil, pan.locationX != nil || pan.locationY != nil {
            let t = UITapGestureRecognizer(target: self, action: #selector(handleTapBinding(_:)))
            t.delegate = self
            addGestureRecognizer(t)
            panTapBindingGesture = t
        }
    }

    @objc private func handlePanBinding(_ g: UIPanGestureRecognizer) {
        viewModel?.applyPanGesture(
            translation: g.translation(in: self),
            velocity: g.velocity(in: self),
            location: g.location(in: self)
        )
    }

    @objc private func handleTapBinding(_ g: UITapGestureRecognizer) {
        viewModel?.applyPanGesture(translation: .zero, velocity: .zero, location: g.location(in: self))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard shouldHandleTouches else { return }
        viewModel?.service.context.logger.debug("CView.touchesBegan: \(viewModel?.componentPath ?? "unknown")")
        viewModel?.fireTrigger(.touchDown)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard shouldHandleTouches else { return }
        viewModel?.service.context.logger.debug("CView.touchesEnded: \(viewModel?.componentPath ?? "unknown")")
        viewModel?.fireTrigger(.touchUp)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        guard shouldHandleTouches else { return }
        viewModel?.service.context.logger.debug("CView.touchesCancelled: \(viewModel?.componentPath ?? "unknown")")
        viewModel?.fireTrigger(.touchUp)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension CView: UIGestureRecognizerDelegate {
    /// Only the `gestures.pan` binding recognizers set `self` as delegate, so
    /// this applies to them alone: let them recognize alongside the action tap,
    /// long-press, and any ancestor gestures.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }
}
