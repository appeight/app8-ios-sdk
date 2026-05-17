import UIKit
@preconcurrency import Combine

@MainActor
protocol App8BaseViewProtocol {
    func setup()
}

/// Lets the shared `applyBaseStyle` extension reach the view's `activeStateAnimation`
/// without threading the resolved animation through the legacy `applyStyle` parameters.
@MainActor
protocol HasActiveStateAnimation: AnyObject {
    var activeStateAnimation: DSL.Model.Animation.Inline? { get }
}

@MainActor
class App8BaseView<Content: DSL.Model.Component.EntityContent>: UIView, App8BaseViewProtocol, HasActiveStateAnimation {

    typealias Content = Content

    // MARK: - Reactive plumbing

    private var layoutCancellable: AnyCancellable?
    private var styleCancellable: AnyCancellable?
    private var animationCancellable: AnyCancellable?

    // Last style, kept so it can be reapplied on trait changes.
    private var latestStyle: Content.Style?
    private var latestAnimation: DSL.Model.Animation?

    /// Resolved animation for a state-driven style apply. Set by `applyStyleWithAnimation`
    /// for the duration of the subclass `applyStyle` call; cleared immediately after.
    private(set) var activeStateAnimation: DSL.Model.Animation.Inline?

    @available(iOS 17.0, *)
    private var _styleTraitRegistration: UITraitChangeRegistration? {
        get { objc_getAssociatedObject(self, &_styleRegKey) as? UITraitChangeRegistration }
        set { objc_setAssociatedObject(self, &_styleRegKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    // MARK: - Constraint cache

    /// Constraints installed by the App8 layout engine; only these are ever removed.
    private var installedConstraints: [NSLayoutConstraint] = []

    private weak var viewRegistry: ViewRegistry?
    private var parentComponentPath: String?

    /// Stored layout/superview for `ignoresSafeArea` views so constraints can be
    /// refreshed in `safeAreaInsetsDidChange()` — the safe area insets are often 0
    /// at initial layout time (view not yet in the window) and only become correct
    /// after the first layout pass, so we re-apply once they're known.
    private var safeAreaLayout: DSL.Model.Layout?
    private weak var safeAreaSuperview: UIView?

    /// Optional keyboard service from owning context. Set by subclasses in `configure`
    /// when they need to support `.keyboard` layout target. Nil → keyboard tracking
    /// returns nil, which means the layout system silently skips that target.
    weak var keyboardService: KeyboardHeightServiceProtocol?

    // MARK: - Public API

    /// Subscribe to a reactive layout and apply it to `self` within `superview`.
    /// - Parameters:
    ///   - layoutPublisher: emits new layouts over time (can be nil to clear)
    ///   - superview: container to attach to and resolve fractional sizes / sibling targets
    ///   - viewRegistry: optional registry for sibling constraint resolution (preferred over accessibilityIdentifier)
    ///   - parentComponentPath: parent's path for building full sibling paths (e.g., "card-1" so sibling "name-label" resolves to "card-1.name-label")
    ///   - animated: animate constraint swaps (default true)
    ///   - duration/options: animation tuning
    func bindLayout<P: Publisher>(
        _ layoutPublisher: P,
        in superview: UIView,
        viewRegistry: ViewRegistry? = nil,
        parentComponentPath: String? = nil,
        keyboardService: KeyboardHeightServiceProtocol? = nil,
        animated: Bool = true,
        duration: TimeInterval = 0.25,
        options: UIView.AnimationOptions = [.curveEaseInOut]
    ) where P.Output == DSL.Model.Layout?, P.Failure == Never {

        translatesAutoresizingMaskIntoConstraints = false
        if self.superview !== superview {
            superview.addSubview(self)
        }

        self.viewRegistry = viewRegistry
        self.parentComponentPath = parentComponentPath
        self.keyboardService = keyboardService

        layoutCancellable?.cancel()

        // Capture the first emitted value synchronously (before .receive(on:) defers it).
        // CurrentValueSubject emits immediately on subscription; handleEvents intercepts
        // it inline while .receive(on: .main) would defer to the next run loop.
        // This ensures height/width constraints are installed during renderComponent,
        // which is critical for collection view cell self-sizing.
        var initialLayout: DSL.Model.Layout?
        var didCaptureInitial = false

        layoutCancellable = layoutPublisher
            .handleEvents(receiveOutput: { layout in
                if !didCaptureInitial {
                    didCaptureInitial = true
                    initialLayout = layout
                }
            })
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak superview] layout in
                guard let self, let superview else { return }
                self.applyLayout(layout, in: superview, animated: animated, duration: duration, options: options)
            }

        // Apply first value synchronously — constraints are available immediately
        // for UICollectionView self-sizing (preferredLayoutAttributesFitting).
        // The async sink above will re-apply the same layout (harmless/idempotent).
        if didCaptureInitial {
            applyLayout(initialLayout, in: superview, animated: false)
        }
    }
    
    func bindStyle<P: Publisher>(
        _ stylePublisher: P,
        animated: Bool = true,
        duration: TimeInterval = 0.25,
        options: UIView.AnimationOptions = [.curveEaseInOut]
    ) where P.Output == Content.Style?, P.Failure == Never {

        styleCancellable?.cancel()
        styleCancellable = stylePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] style in
                guard let self else { return }
                self.latestStyle = style
                self.applyStyle(style, animated: animated, duration: duration, options: options)
            }
    }

    /// Binds both style and animation publishers for state-driven transitions.
    /// Animation config from the StateManager determines how style changes are animated.
    func bindStyle<S: Publisher, A: Publisher>(
        _ stylePublisher: S,
        animation animationPublisher: A
    ) where S.Output == Content.Style?, S.Failure == Never, A.Output == DSL.Model.Animation?, A.Failure == Never {

        styleCancellable?.cancel()
        animationCancellable?.cancel()

        // Store latest animation when it changes
        animationCancellable = animationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] animation in
                self?.latestAnimation = animation
            }

        // Apply style using the latest animation config
        styleCancellable = stylePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] style in
                guard let self else { return }
                self.latestStyle = style
                self.applyStyleWithAnimation(style, animation: self.latestAnimation)
            }
    }

    /// Apply style using `DSL.Model.Animation` config. Pointer-form animations
    /// that fail to resolve fall back to instantaneous (the registry only fails
    /// if the named animation isn't declared in `app.animations`).
    ///
    /// Sets `activeStateAnimation` for the duration of the subclass
    /// `applyStyle` call so the shared `applyBaseStyle` extension can run a
    /// single `AnimationRunner` for all view + layer mutations.
    func applyStyleWithAnimation(_ style: Content.Style?, animation: DSL.Model.Animation?) {
        let inline = animation?.inlineOrNil
        let duration = inline?.duration ?? 0.25
        let options = inline?.uiAnimationOptions ?? [.curveEaseInOut]
        let animated = inline != nil
        let useSpring = inline?.isSpring ?? false

        activeStateAnimation = inline
        defer { activeStateAnimation = nil }

        applyStyle(style, animated: animated, duration: duration, options: options, useSpring: useSpring)
    }

    // MARK: - Inits

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        layoutCancellable?.cancel()
        styleCancellable?.cancel()
        animationCancellable?.cancel()
    }

    /// Override in subclasses for custom setup after init.
    func setup() {}

    // MARK: - Intrinsic content size forwarding

    /// Subclasses override to declare the inner element whose intrinsic
    /// content size should be reported by this wrapper. Default is `nil`,
    /// meaning the wrapper has no preferred size of its own (correct for
    /// generic containers like CView, CScrollViewView, CCollectionView).
    ///
    /// When non-nil, hugging / compression-resistance priorities applied
    /// to the wrapper actually defend a real number when an ancestor
    /// stack distributes space.
    var intrinsicContentSource: UIView? { nil }

    override var intrinsicContentSize: CGSize {
        intrinsicContentSource?.intrinsicContentSize ?? super.intrinsicContentSize
    }
    
    // MARK: - Trait change wiring (iOS 17+ registration, ≤16 fallback)

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)

        if #available(iOS 17.0, *) {
            if newWindow != nil, _styleTraitRegistration == nil {
                _styleTraitRegistration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
                    (view: Self, previous) in
                    view._reapplyStyleIfColorAppearanceChanged(since: previous)
                }
            } else if newWindow == nil, let reg = _styleTraitRegistration {
                unregisterForTraitChanges(reg)
                _styleTraitRegistration = nil
            }
        }
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()

        if #available(iOS 17.0, *) {
            if window != nil {
                if _styleTraitRegistration == nil {
                    _styleTraitRegistration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
                        (view: Self, previous) in
                        view._reapplyStyleIfColorAppearanceChanged(since: previous)
                    }
                }
            } else {
                if let reg = _styleTraitRegistration {
                    unregisterForTraitChanges(reg)
                    _styleTraitRegistration = nil
                }
            }
        }

        // Re-apply style when gaining a window so CALayer colors (set as static CGColors
        // in MaterialView) are resolved against the actual window traitCollection, not the
        // default .unspecified that may have been active when bindStyle's async sink first fired.
        if window != nil, let style = latestStyle {
            applyStyle(style, animated: false)
        }
    }
    
    /// iOS ≤ 16 fallback
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if #available(iOS 17.0, *) {
            // no-op; registration handles it
        } else {
            _reapplyStyleIfColorAppearanceChanged(since: previous)
        }
    }

    private func _reapplyStyleIfColorAppearanceChanged(since previous: UITraitCollection?) {
        guard previous?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
        // Re-apply last known style so CALayer-backed colors are re-resolved.
        applyStyle(latestStyle, animated: false)
    }

    // MARK: - Core apply

    /// Apply a layout immediately (used by binder above and can be used directly).
    func applyLayout(
        _ layout: DSL.Model.Layout?,
        in superview: UIView,
        animated: Bool = true,
        duration: TimeInterval = 0.25,
        options: UIView.AnimationOptions = [.curveEaseInOut]
    ) {
        translatesAutoresizingMaskIntoConstraints = false
        if self.superview !== superview {
            superview.addSubview(self)
        }

        // Apply content hugging / compression priorities from the original layout
        // (before the .fillSuperview fallback) so a layout that only sets priorities
        // still takes effect. Only specified axes are written — unspecified axes
        // preserve UIKit defaults.
        applyContentPriorities(from: layout)

        // Establish current layout before swapping constraints, for smooth animation.
        superview.layoutIfNeeded()

        NSLayoutConstraint.deactivate(installedConstraints)
        installedConstraints.removeAll()

        let newConstraints = makeConstraints(from: layout, in: superview)
        NSLayoutConstraint.activate(newConstraints)
        installedConstraints = newConstraints

        if animated {
            UIView.animate(withDuration: duration, delay: 0, options: options) {
                superview.layoutIfNeeded()
            }
        } else {
            superview.layoutIfNeeded()
        }

        if layout?.ignoresSafeArea == true {
            safeAreaLayout = layout
            safeAreaSuperview = superview
        } else {
            safeAreaLayout = nil
            safeAreaSuperview = nil
        }
    }

    /// Sets content hugging and compression-resistance priorities for the axes
    /// that the DSL specifies. Unspecified axes are left untouched so UIKit
    /// defaults (e.g. UILabel's vertical hugging) remain intact.
    private func applyContentPriorities(from layout: DSL.Model.Layout?) {
        if let hugging = layout?.contentHuggingPriority {
            if let h = hugging.h {
                setContentHuggingPriority(h.ui, for: .horizontal)
            }
            if let v = hugging.v {
                setContentHuggingPriority(v.ui, for: .vertical)
            }
        }
        if let resistance = layout?.contentCompressionResistancePriority {
            if let h = resistance.h {
                setContentCompressionResistancePriority(h.ui, for: .horizontal)
            }
            if let v = resistance.v {
                setContentCompressionResistancePriority(v.ui, for: .vertical)
            }
        }
    }

    /// Re-apply the layout once real safe area insets are known.
    /// `safeAreaInsets` is 0 during the initial synchronous render (view not yet in the window);
    /// this fires after the first layout pass and corrects the top constraint constant.
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        guard let layout = safeAreaLayout, let superview = safeAreaSuperview else { return }
        applyLayout(layout, in: superview, animated: false)
    }

    // MARK: - Constraint builder (shared by all subclasses)

    /// Produces constraints for the supplied layout.
    open func makeConstraints(from layout: DSL.Model.Layout?, in superview: UIView) -> [NSLayoutConstraint] {
        // UIStackView manages position for arranged subviews; position constraints conflict with it.
        // Only apply size constraints (width/height) when the superview is a UIStackView.
        if superview is UIStackView {
            var constraints: [NSLayoutConstraint] = []
            if let w = layout?.width { constraints += makeWidthConstraints(w, in: superview) }
            if let h = layout?.height { constraints += makeHeightConstraints(h, in: superview) }
            // Also honor explicit width/height constraints from the constraints array
            // (self-dimension clamps and sibling-dimension equalities). Edge / center
            // constraints to superview are still skipped here because they would conflict
            // with UIStackView's internal arrangement.
            for c in layout?.constraints ?? [] {
                guard c.type == .width || c.type == .height else { continue }
                let constant = CGFloat(c.constant ?? 0)
                let relation = c.op ?? .equal

                if c.target == nil {
                    if let made = makeSelfDimension(attr: c.type, constant: constant, relation: relation) {
                        applyPriority(c.priority, to: made)
                        constraints.append(made)
                    }
                    continue
                }

                if let target = c.target,
                   let targetView = resolveTarget(target, in: superview) {
                    let to = c.attribute ?? c.type
                    let made = makeRelation(from: c.type, to: to, target: targetView, constant: constant, relation: relation)
                    applyPriority(c.priority, to: made)
                    constraints.append(made)
                }
            }
            return constraints
        }

        let layout = layout.flatMap { $0.isEmpty ? nil : $0 } ?? .fillSuperview

        var constraints: [NSLayoutConstraint] = []

        if let w = layout.width {
            constraints += makeWidthConstraints(w, in: superview)
        }
        if let h = layout.height {
            constraints += makeHeightConstraints(h, in: superview)
        }

        let safeAreaTopOffset: CGFloat = layout.ignoresSafeArea == true ? -superview.safeAreaInsets.top : 0

        // Fixed edge insets to superview (fractional edges are not supported).
        if let leading = layout.leading { constraints += makeEdge(.leading, dim: leading, to: superview) }
        if let trailing = layout.trailing { constraints += makeEdge(.trailing, dim: trailing, to: superview) }
        if let top = layout.top { constraints += makeEdge(.top, dim: top, to: superview, additionalOffset: safeAreaTopOffset) }
        if let bottom = layout.bottom { constraints += makeEdge(.bottom, dim: bottom, to: superview) }

        let ignoresSafeArea = layout.ignoresSafeArea == true
        for c in layout.constraints ?? [] {
            let from = c.type
            let to = c.attribute ?? c.type
            let constant = CGFloat(c.constant ?? 0)
            let relation = c.op ?? .equal

            // Self-dimension constraint (no target): width/height clamp on self.
            // Enables spacer-style two-priority idioms, e.g. height >= 20 @ required
            // plus height = 50 @ low.
            if c.target == nil {
                if let made = makeSelfDimension(attr: from, constant: constant, relation: relation) {
                    applyPriority(c.priority, to: made)
                    constraints.append(made)
                }
                continue
            }

            // Layout guide targets (e.g. safeArea).
            if let target = c.target, let guide = resolveLayoutGuide(target, in: superview) {
                let made = makeRelationToGuide(from: from, to: to, guide: guide, constant: constant, relation: relation)
                applyPriority(c.priority, to: made)
                constraints.append(made)
                continue
            }

            guard let target = c.target,
                  let targetView = resolveTarget(target, in: superview, ignoresSafeArea: ignoresSafeArea) else { continue }
            var adjustedConstant = constant
            if ignoresSafeArea && from == .top && targetView === superview {
                adjustedConstant += safeAreaTopOffset
            }
            let made = makeRelation(from: from, to: to, target: targetView, constant: adjustedConstant, relation: relation)
            applyPriority(c.priority, to: made)
            constraints.append(made)
        }

        return constraints
    }

    private func applyPriority(_ priority: DSL.Model.Layout.PriorityValue?, to constraint: NSLayoutConstraint) {
        if let priority = priority {
            constraint.priority = priority.ui
        }
    }

    /// Build a self-dimension constraint (e.g. `height >= 20`) when no target is given.
    /// Only `.width` / `.height` attributes are valid here.
    private func makeSelfDimension(
        attr: DSL.Model.Layout.Constraint.Attribute,
        constant: CGFloat,
        relation: DSL.Model.Layout.Constraint.Relation
    ) -> NSLayoutConstraint? {
        switch attr {
        case .width:
            switch relation {
            case .equal:              return widthAnchor.constraint(equalToConstant: constant)
            case .greaterThanOrEqual: return widthAnchor.constraint(greaterThanOrEqualToConstant: constant)
            case .lessThanOrEqual:    return widthAnchor.constraint(lessThanOrEqualToConstant: constant)
            }
        case .height:
            switch relation {
            case .equal:              return heightAnchor.constraint(equalToConstant: constant)
            case .greaterThanOrEqual: return heightAnchor.constraint(greaterThanOrEqualToConstant: constant)
            case .lessThanOrEqual:    return heightAnchor.constraint(lessThanOrEqualToConstant: constant)
            }
        default:
            // Self-targeted leading/trailing/top/bottom/center are nonsense without a target.
            assertionFailure("Constraint without target requires width or height attribute, got \(attr)")
            return nil
        }
    }
    
    // MARK: - Style hook for subclasses
    /// When setting CGColors for CALayers, Subclasses should resolve dynamic UIColors with `resolvedColor(with: traitCollection)`
    func applyStyle(
        _ style: Content.Style?,
        animated: Bool = true,
        duration: TimeInterval = 0.25,
        options: UIView.AnimationOptions = [.curveEaseInOut],
        useSpring: Bool = false
    ) {
        // Intentionally empty; override in subclasses.
        // Example in a subclass:
        // CATransaction.begin(); CATransaction.setDisableActions(!animated)
        // shape.fillColor = UIColor.systemBackground.resolvedColor(with: traitCollection).cgColor
        // CATransaction.commit()
    }

    // MARK: - Helpers

    private func makeWidthConstraints(_ dim: DSL.Model.Layout.Dimension, in superview: UIView) -> [NSLayoutConstraint] {
        switch dim {
        case .fixed(let value):
            return [widthAnchor.constraint(equalToConstant: CGFloat(value))]
        case .fraction(let fraction):
            return [widthAnchor.constraint(equalTo: superview.widthAnchor, multiplier: CGFloat(fraction))]
        case .expression:
            // Expression dimensions are not supported in layout - use transform for dynamic sizing
            return []
        }
    }

    private func makeHeightConstraints(_ dim: DSL.Model.Layout.Dimension, in superview: UIView) -> [NSLayoutConstraint] {
        switch dim {
        case .fixed(let value):
            return [heightAnchor.constraint(equalToConstant: CGFloat(value))]
        case .fraction(let fraction):
            return [heightAnchor.constraint(equalTo: superview.heightAnchor, multiplier: CGFloat(fraction))]
        case .expression:
            // Expression dimensions are not supported in layout - use transform for dynamic sizing
            return []
        }
    }

    /// Only fixed inset values are supported on edges.
    private func makeEdge(_ attr: DSL.Model.Layout.Constraint.Attribute,
                          dim: DSL.Model.Layout.Dimension,
                          to superview: UIView,
                          additionalOffset: CGFloat = 0) -> [NSLayoutConstraint] {
        guard case .fixed(let value) = dim else { return [] }
        let c = CGFloat(value) + additionalOffset
        switch attr {
        case .leading:
            return [leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: c)]
        case .trailing:
            return [trailingAnchor.constraint(equalTo: superview.trailingAnchor, constant: c)]
        case .top:
            return [topAnchor.constraint(equalTo: superview.topAnchor, constant: c)]
        case .bottom:
            return [bottomAnchor.constraint(equalTo: superview.bottomAnchor, constant: c)]
        case .centerX:
            return [centerXAnchor.constraint(equalTo: superview.centerXAnchor, constant: c)]
        case .centerY:
            return [centerYAnchor.constraint(equalTo: superview.centerYAnchor, constant: c)]
        case .width, .height:
            // makeEdge is only invoked for the top-level edge shorthand fields
            // (leading/trailing/top/bottom). width/height live on Layout itself
            // and are handled by makeWidthConstraints / makeHeightConstraints.
            return []
        }
    }

    private func resolveLayoutGuide(_ target: DSL.Model.Layout.Constraint.Target, in container: UIView) -> UILayoutGuide? {
        switch target {
        case .safeArea: return container.safeAreaLayoutGuide
        default: return nil
        }
    }

    private func makeRelationToGuide(
        from: DSL.Model.Layout.Constraint.Attribute,
        to: DSL.Model.Layout.Constraint.Attribute,
        guide: UILayoutGuide,
        constant: CGFloat,
        relation: DSL.Model.Layout.Constraint.Relation = .equal
    ) -> NSLayoutConstraint {
        switch (from, to) {
        case (.top,      .top):      return relate(topAnchor,      guide.topAnchor,      relation, constant)
        case (.top,      .bottom):   return relate(topAnchor,      guide.bottomAnchor,   relation, constant)
        case (.bottom,   .bottom):   return relate(bottomAnchor,   guide.bottomAnchor,   relation, constant)
        case (.bottom,   .top):      return relate(bottomAnchor,   guide.topAnchor,      relation, constant)
        case (.leading,  .leading):  return relate(leadingAnchor,  guide.leadingAnchor,  relation, constant)
        case (.leading,  .trailing): return relate(leadingAnchor,  guide.trailingAnchor, relation, constant)
        case (.trailing, .trailing): return relate(trailingAnchor, guide.trailingAnchor, relation, constant)
        case (.trailing, .leading):  return relate(trailingAnchor, guide.leadingAnchor,  relation, constant)
        case (.centerX,  .centerX):  return relate(centerXAnchor,  guide.centerXAnchor,  relation, constant)
        case (.centerY,  .centerY):  return relate(centerYAnchor,  guide.centerYAnchor,  relation, constant)
        case (.width,    .width):    return relateDim(widthAnchor,  guide.widthAnchor,  relation, constant)
        case (.height,   .height):   return relateDim(heightAnchor, guide.heightAnchor, relation, constant)
        default:
            assertionFailure("Unsupported guide constraint combination: \(from) → \(to)")
            return bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: constant)
        }
    }

    /// Build an NSLayoutConstraint between two compatible anchors using the given relation.
    private func relate<A: AnyObject>(
        _ from: NSLayoutAnchor<A>,
        _ to: NSLayoutAnchor<A>,
        _ relation: DSL.Model.Layout.Constraint.Relation,
        _ constant: CGFloat
    ) -> NSLayoutConstraint {
        switch relation {
        case .equal:              return from.constraint(equalTo: to, constant: constant)
        case .greaterThanOrEqual: return from.constraint(greaterThanOrEqualTo: to, constant: constant)
        case .lessThanOrEqual:    return from.constraint(lessThanOrEqualTo: to, constant: constant)
        }
    }

    /// Dimension-anchor variant — needed because NSLayoutDimension does not
    /// share `NSLayoutAnchor<NSLayoutDimension>` overload signatures with
    /// the x/y axis anchors when we want the `equalTo` form to retain
    /// dimension-specific helpers (multiplier).
    private func relateDim(
        _ from: NSLayoutDimension,
        _ to: NSLayoutDimension,
        _ relation: DSL.Model.Layout.Constraint.Relation,
        _ constant: CGFloat
    ) -> NSLayoutConstraint {
        switch relation {
        case .equal:              return from.constraint(equalTo: to, constant: constant)
        case .greaterThanOrEqual: return from.constraint(greaterThanOrEqualTo: to, constant: constant)
        case .lessThanOrEqual:    return from.constraint(lessThanOrEqualTo: to, constant: constant)
        }
    }

    private func resolveTarget(_ target: DSL.Model.Layout.Constraint.Target, in container: UIView, ignoresSafeArea: Bool = false) -> UIView? {
        switch target {
        case .superview:
            return container
        case .sibling(let name):
            // Prefer ViewRegistry for sibling resolution (decoupled from accessibilityIdentifier)
            if let registry = viewRegistry {
                // Build full sibling path: e.g., "card-1" + "name-label" -> "card-1.name-label"
                let siblingPath = parentComponentPath.map { "\($0).\(name)" } ?? name
                if let view = registry.sibling(id: siblingPath, excludingView: self),
                   view.isDescendant(of: container) {
                    return view
                }
            }
            // Fallback to accessibilityIdentifier for backward compatibility
            return container.subviews.first(where: { $0 !== self && $0.accessibilityIdentifier == name })
        case .keyboard:
            // Return keyboard tracking view - its top anchor tracks keyboard top.
            // Requires `keyboardService` to be set by the subclass during configure.
            return keyboardService?.keyboardTrackingView(for: container, ignoresSafeArea: ignoresSafeArea)
        case .safeArea:
            // Handled via resolveLayoutGuide; should not reach here
            return nil
        }
    }

    private func makeRelation(from: DSL.Model.Layout.Constraint.Attribute,
                              to: DSL.Model.Layout.Constraint.Attribute,
                              target: UIView,
                              constant: CGFloat,
                              relation: DSL.Model.Layout.Constraint.Relation = .equal) -> NSLayoutConstraint {
        switch (from, to) {
        case (.leading,  .leading):  return relate(leadingAnchor,  target.leadingAnchor,  relation, constant)
        case (.leading,  .trailing): return relate(leadingAnchor,  target.trailingAnchor, relation, constant)
        case (.trailing, .trailing): return relate(trailingAnchor, target.trailingAnchor, relation, constant)
        case (.trailing, .leading):  return relate(trailingAnchor, target.leadingAnchor,  relation, constant)

        case (.top,      .top):      return relate(topAnchor,      target.topAnchor,      relation, constant)
        case (.top,      .bottom):   return relate(topAnchor,      target.bottomAnchor,   relation, constant)
        case (.bottom,   .bottom):   return relate(bottomAnchor,   target.bottomAnchor,   relation, constant)
        case (.bottom,   .top):      return relate(bottomAnchor,   target.topAnchor,      relation, constant)

        case (.centerX,  .centerX):  return relate(centerXAnchor,  target.centerXAnchor,  relation, constant)
        case (.centerX,  .leading):  return relate(centerXAnchor,  target.leadingAnchor,  relation, constant)
        case (.centerX,  .trailing): return relate(centerXAnchor,  target.trailingAnchor, relation, constant)

        case (.centerY,  .centerY):  return relate(centerYAnchor,  target.centerYAnchor,  relation, constant)
        case (.centerY,  .top):      return relate(centerYAnchor,  target.topAnchor,      relation, constant)
        case (.centerY,  .bottom):   return relate(centerYAnchor,  target.bottomAnchor,   relation, constant)

        case (.width,    .width):    return relateDim(widthAnchor,  target.widthAnchor,  relation, constant)
        case (.height,   .height):   return relateDim(heightAnchor, target.heightAnchor, relation, constant)

        default:
            // Fallback: align like-to-like for the from-attribute.
            switch from {
            case .leading:  return relate(leadingAnchor,  target.leadingAnchor,  relation, constant)
            case .trailing: return relate(trailingAnchor, target.trailingAnchor, relation, constant)
            case .top:      return relate(topAnchor,      target.topAnchor,      relation, constant)
            case .bottom:   return relate(bottomAnchor,   target.bottomAnchor,   relation, constant)
            case .centerX:  return relate(centerXAnchor,  target.centerXAnchor,  relation, constant)
            case .centerY:  return relate(centerYAnchor,  target.centerYAnchor,  relation, constant)
            case .width:    return relateDim(widthAnchor,  target.widthAnchor,  relation, constant)
            case .height:   return relateDim(heightAnchor, target.heightAnchor, relation, constant)
            }
        }
    }
}

// MARK: - Associated key for registration storage
@MainActor private var _styleRegKey: UInt8 = 0
