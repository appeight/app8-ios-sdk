// Presentation controller for custom modal transitions.
//
// Two responsibilities beyond UIKit's default:
//   • An optional backdrop **dimming** view, faded in/out alongside the
//     transition, with configurable colour, peak opacity, and tap-to-dismiss.
//   • An optional **sized container** (`ResolvedModalPresentation`): a popup /
//     sheet laid out relatively or absolutely within the safe area, with corner
//     clipping, a drop shadow, and keyboard avoidance. Without it the modal
//     covers the whole container (and the presenter stays in the hierarchy so
//     partial-cover transitions reveal it).

import UIKit

@MainActor
final class App8DimmingPresentationController: UIPresentationController {

    private let dimming: DSL.Model.ScreenTransition.ResolvedDimming?
    private let presentation: DSL.Model.ScreenTransition.ResolvedModalPresentation?
    private let interactive: DSL.Model.ScreenTransition.InteractiveConfig?

    /// Invoked when the backdrop is tapped (only when dimming is present and
    /// `dismissOnTap` is set). Wired to dismiss the modal through the engine.
    var onBackdropTap: (() -> Void)?

    /// Invoked once the engine-owned interactive sheet dismissal has fully played
    /// out, so the presenter can tear the modal down and clear its bookkeeping.
    var onInteractiveDismiss: (() -> Void)?

    /// Bottom overlap of the keyboard with the container, tracked for avoidance.
    private var keyboardOverlap: CGFloat = 0

    // Frame-driven sheet interaction state (bottom/top sized sheets only).
    private var sheetRestingFrame: CGRect = .zero
    private var isInteractingSheet = false
    private weak var sheetPan: UIPanGestureRecognizer?

    private lazy var dimmingView: UIView = {
        let view = UIView()
        view.backgroundColor = dimming?.color ?? .black
        view.alpha = 0
        if dimming?.dismissOnTap == true {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackdropTap))
            view.addGestureRecognizer(tap)
        }
        return view
    }()

    /// Renders the container's drop shadow. Kept separate from the presented view
    /// because corner clipping (`masksToBounds`) would otherwise clip the shadow.
    private lazy var shadowView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }()

    init(
        presentedViewController: UIViewController,
        presenting presentingViewController: UIViewController?,
        dimming: DSL.Model.ScreenTransition.ResolvedDimming?,
        presentation: DSL.Model.ScreenTransition.ResolvedModalPresentation?,
        interactive: DSL.Model.ScreenTransition.InteractiveConfig?
    ) {
        self.dimming = dimming
        self.presentation = presentation
        self.interactive = interactive
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
    }

    /// A bottom/top sized sheet drives its interactive dismiss/stretch from the
    /// frame here (not the generic percent-driven driver), so the rubber-band can
    /// genuinely *grow* the sheet and the drag tracks the finger 1:1.
    var usesSheetInteraction: Bool {
        guard let presentation, let interactive, interactive.enabled else { return false }
        return presentation.align == .bottom || presentation.align == .top
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Frame

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else { return .zero }
        guard let presentation else { return containerView.bounds }
        return presentation.frame(
            in: containerView.bounds,
            safeArea: containerView.safeAreaInsets,
            keyboardHeight: keyboardOverlap
        )
    }

    // MARK: - Presentation lifecycle

    override func presentationTransitionWillBegin() {
        super.presentationTransitionWillBegin()
        guard let containerView else { return }

        if dimming != nil {
            dimmingView.frame = containerView.bounds
            dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            containerView.insertSubview(dimmingView, at: 0)
        }

        if presentation?.shadow != nil {
            // Above the dimming, below the presented view.
            containerView.insertSubview(shadowView, aboveSubview: dimmingView)
            applyShadowChrome()
        }
        applyContainerChrome()

        if presentation?.avoidsKeyboard == true {
            observeKeyboard()
        }

        guard let dimming else { return }
        let target = CGFloat(dimming.opacity)
        guard let coordinator = presentedViewController.transitionCoordinator else {
            dimmingView.alpha = target
            return
        }
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.dimmingView.alpha = target
        })
    }

    override func presentationTransitionDidEnd(_ completed: Bool) {
        super.presentationTransitionDidEnd(completed)
        guard completed, usesSheetInteraction, let containerView, sheetPan == nil else { return }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSheetPan(_:)))
        containerView.addGestureRecognizer(pan)
        sheetPan = pan
    }

    override func dismissalTransitionWillBegin() {
        super.dismissalTransitionWillBegin()
        guard dimming != nil else { return }
        guard let coordinator = presentedViewController.transitionCoordinator else {
            dimmingView.alpha = 0
            return
        }
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.dimmingView.alpha = 0
        })
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        if let containerView { dimmingView.frame = containerView.bounds }
        layoutPresentedAndShadow()
    }

    // MARK: - Chrome

    /// Corner clipping on the presented view (rounded only on the edge the card
    /// hugs, for a clean sheet).
    private func applyContainerChrome() {
        guard let presentation, let presentedView else { return }
        presentedView.layer.maskedCorners = maskedCorners(for: presentation.align)
        if let corner = presentation.corner {
            presentedView.layer.cornerCurve = corner.curve.ca
            presentedView.layer.cornerRadius = corner.resolvedRadius(in: presentedView.bounds.size)
            presentedView.layer.masksToBounds = true
        }
    }

    private func applyShadowChrome() {
        guard let presentation, let layer = presentation.shadow?.layers.first else { return }
        shadowView.layer.shadowColor = layer.color.ui.cgColor
        shadowView.layer.shadowRadius = layer.radius
        shadowView.layer.shadowOffset = layer.offset.cgSize
        shadowView.layer.shadowOpacity = Float(layer.opacity)
    }

    /// Reposition the presented view + shadow to the resolved resting frame —
    /// unless an interaction currently owns the card's geometry:
    ///   • A frame-driven sheet pan/animation (`isInteractingSheet`) sets the card
    ///     frame itself; re-assigning it here would fight the drag, so we bail.
    ///   • A `transform`-driven generic dismiss leaves the resting frame intact but
    ///     moves the card via transform; we only keep the shadow glued to it
    ///     (re-assigning `frame` under a non-identity transform cancels it).
    private func layoutPresentedAndShadow() {
        if isInteractingSheet { return }

        let cardTransform = presentedView?.transform ?? .identity
        if !cardTransform.isIdentity {
            if presentation?.shadow != nil { shadowView.transform = cardTransform }
            return
        }

        let frame = frameOfPresentedViewInContainerView
        presentedView?.frame = frame
        if let corner = presentation?.corner {
            // Keep the card's clip radius correct under resize / keyboard.
            presentedView?.layer.cornerRadius = corner.resolvedRadius(in: frame.size)
        }
        syncShadow(to: frame)
    }

    /// Pin the shadow view to a frame (identity transform), retracing its path.
    private func syncShadow(to frame: CGRect) {
        guard let presentation, presentation.shadow != nil else { return }
        shadowView.transform = .identity
        shadowView.frame = frame
        let radius = presentation.corner?.resolvedRadius(in: frame.size) ?? 0
        shadowView.layer.shadowPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: frame.size), cornerRadius: radius
        ).cgPath
    }

    private func maskedCorners(for align: DSL.Model.ScreenTransition.ModalAlign) -> CACornerMask {
        switch align {
        case .bottom: return [.layerMinXMinYCorner, .layerMaxXMinYCorner]   // top corners only
        case .top:    return [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]   // bottom corners only
        case .center, .leading, .trailing:
            return [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
    }

    // MARK: - Keyboard avoidance

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
    }

    @objc private func keyboardWillChangeFrame(_ note: Notification) {
        guard let containerView,
              let info = note.userInfo,
              let endFrame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }

        let endInContainer = containerView.convert(endFrame, from: nil)
        keyboardOverlap = max(0, containerView.bounds.maxY - endInContainer.minY)

        let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        UIView.animate(withDuration: duration) { [weak self] in
            self?.layoutPresentedAndShadow()
        }
    }

    // MARK: - Frame-driven sheet interaction

    @objc private func handleSheetPan(_ gesture: UIPanGestureRecognizer) {
        guard let containerView, let card = presentedView,
              let presentation, let interactive else { return }
        let ty = gesture.translation(in: containerView).y
        // Signed so that *positive* always means "toward dismissal", whichever
        // edge the sheet hugs (down for a bottom sheet, up for a top sheet).
        let towardDismiss = (presentation.align == .top) ? -ty : ty

        switch gesture.state {
        case .began:
            sheetRestingFrame = frameOfPresentedViewInContainerView
            isInteractingSheet = true

        case .changed:
            let frame = sheetFrame(towardDismiss: towardDismiss, align: presentation.align)
            card.frame = frame
            syncShadow(to: frame)

        case .ended, .cancelled, .failed:
            let velocity = (presentation.align == .top)
                ? -gesture.velocity(in: containerView).y
                : gesture.velocity(in: containerView).y
            let travel = dismissTravel(align: presentation.align)
            let progress = travel > 0 ? max(0, towardDismiss) / travel : 0
            let dismiss = towardDismiss > 0
                && (progress >= CGFloat(interactive.threshold) || velocity >= CGFloat(interactive.velocity))
            if dismiss {
                animateSheetDismiss(align: presentation.align)
            } else {
                animateSheetSettle()
            }

        default:
            break
        }
    }

    /// The card frame for a given drag. Toward dismissal the sheet slides 1:1
    /// (linear finger tracking); away from it the sheet **stretches** with elastic
    /// resistance, its far edge anchored, so the background fills and bottom-pinned
    /// content stays put.
    private func sheetFrame(towardDismiss drag: CGFloat, align: DSL.Model.ScreenTransition.ModalAlign) -> CGRect {
        let rest = sheetRestingFrame
        if drag >= 0 {
            let dy = (align == .top) ? -drag : drag      // slide off-edge, 1:1
            return CGRect(x: rest.minX, y: rest.minY + dy, width: rest.width, height: rest.height)
        }
        let stretch = rubberBand(-drag, dimension: rest.height)
        switch align {
        case .top:   return CGRect(x: rest.minX, y: rest.minY, width: rest.width, height: rest.height + stretch)
        default:     return CGRect(x: rest.minX, y: rest.minY - stretch, width: rest.width, height: rest.height + stretch)
        }
    }

    /// Distance the card travels from rest until it's fully off the hugged edge.
    private func dismissTravel(align: DSL.Model.ScreenTransition.ModalAlign) -> CGFloat {
        guard let containerView else { return sheetRestingFrame.height }
        switch align {
        case .top: return sheetRestingFrame.maxY
        default:   return containerView.bounds.maxY - sheetRestingFrame.minY
        }
    }

    /// Classic diminishing-returns rubber-band curve.
    private func rubberBand(_ distance: CGFloat, dimension: CGFloat) -> CGFloat {
        let d = max(dimension, 1)
        return (1 - 1 / (abs(distance) * 0.55 / d + 1)) * d
    }

    private func animateSheetSettle() {
        UIView.animate(withDuration: 0.3, delay: 0,
                       options: [.curveEaseInOut, .beginFromCurrentState]) { [weak self] in
            guard let self else { return }
            presentedView?.frame = sheetRestingFrame
            // The sheet's content is pinned with Auto Layout, so changing the
            // card's frame alone won't animate the constraint-driven subviews
            // (background, bottom-pinned buttons) — they'd snap to the resting
            // layout. Force a layout pass *inside* the animation so the whole
            // hierarchy resizes together.
            presentedView?.layoutIfNeeded()
            syncShadow(to: sheetRestingFrame)
        } completion: { [weak self] _ in
            self?.isInteractingSheet = false
        }
    }

    private func animateSheetDismiss(align: DSL.Model.ScreenTransition.ModalAlign) {
        guard let containerView, let card = presentedView else { return }
        let rest = sheetRestingFrame
        let offY = (align == .top) ? -rest.height : containerView.bounds.maxY
        let target = CGRect(x: rest.minX, y: offY, width: rest.width, height: rest.height)
        UIView.animate(withDuration: 0.25, delay: 0,
                       options: [.curveEaseInOut, .beginFromCurrentState]) { [weak self] in
            card.frame = target
            self?.dimmingView.alpha = 0
            self?.syncShadow(to: target)
        } completion: { [weak self] _ in
            guard let self else { return }
            presentedViewController.dismiss(animated: false)
            onInteractiveDismiss?()
        }
    }

    // MARK: - Actions

    @objc private func handleBackdropTap() {
        onBackdropTap?()
    }
}
