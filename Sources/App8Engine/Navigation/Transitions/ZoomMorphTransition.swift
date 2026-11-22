//
//  ZoomMorphTransition.swift
//  App8Engine
//
//  The native zoom from a source that fills (≥ 80%) the presenting screen —
//  a full-screen pager page — drawn by the engine (transitions.md, "Native
//  zoom", iOS row; since 0.7.11). UIKit's zoom shrinks and dims the whole
//  presenting screen and shows the incoming one at once when the source is the
//  screen itself: it read as a broken modal. This is the pose and morph of
//  Android and the web:
//
//  - the presenting screen stays still;
//  - the incoming screen is posed so its `alignmentKey` element covers the
//    source rect (uniform scale), clipped to the source, and eases to identity;
//  - a box travels from the source into the alignment element (hidden until it
//    lands), showing the source's image and cross-dissolving into the
//    alignment element's image, both aspect-filled;
//  - cubic ease-out, 0.36 s in and 0.32 s out; the pop runs it in reverse, the
//    back swipe and `dismissGesture` scrub the reverse interactively.
//
//  Invariants (as `SharedElementTransitionAnimator`): the hidden alignment
//  element, the mask and the incoming transform are restored and the box is
//  removed on every completion path; `completeTransition` always runs.
//

import ObjectiveC
import UIKit

@MainActor
final class ZoomMorphTransition: NSObject {

    private static var key: UInt8 = 0

    static let forwardDuration: TimeInterval = 0.36
    static let reverseDuration: TimeInterval = 0.32

    private weak var presentingScreen: ScreenViewController?
    private let zoom: DSL.Model.ScreenTransition.NativeZoom
    private let initialSourceKey: String
    /// Drives an interactive pop (back swipe, `dismissGesture`) while a pan runs.
    private(set) var interaction: ZoomMorphInteraction?

    private init(zoom: DSL.Model.ScreenTransition.NativeZoom, presentingScreen: ScreenViewController, initialSourceKey: String) {
        self.zoom = zoom
        self.presentingScreen = presentingScreen
        self.initialSourceKey = initialSourceKey
        super.init()
    }

    /// The pose-and-morph transition that pushed `viewController`, if any.
    static func of(_ viewController: UIViewController) -> ZoomMorphTransition? {
        objc_getAssociatedObject(viewController, &key) as? ZoomMorphTransition
    }

    /// Attaches the transition to `viewController` when the source element
    /// covers at least `SourceProxy.fillsScreen` of the presenting screen.
    /// Returns false for smaller sources (they keep UIKit's zoom).
    @discardableResult
    static func attachIfFullScreenSource(
        to viewController: UIViewController,
        zoom: DSL.Model.ScreenTransition.NativeZoom,
        presentingScreen: ScreenViewController?
    ) -> Bool {
        guard let presentingScreen, presentingScreen.isViewLoaded else { return false }
        let key = zoom.resolvedSourceKey ?? zoom.sourceKeyExpression
        guard let source = TransitionKeyLocator.view(forKey: key, in: presentingScreen.view),
              SourceProxy.covers(source, presentingScreen.view) else { return false }
        let transition = ZoomMorphTransition(zoom: zoom, presentingScreen: presentingScreen, initialSourceKey: key)
        objc_setAssociatedObject(viewController, &Self.key, transition, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return true
    }

    // MARK: - Navigation delegate hooks

    /// The animator for a push of / pop from a screen this transition belongs to.
    static func animator(for operation: UINavigationController.Operation, from: UIViewController, to: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        switch operation {
        case .push:
            guard let transition = of(to) else { return nil }
            return ZoomMorphAnimator(transition: transition, direction: .forward)
        case .pop:
            guard let transition = of(from) else { return nil }
            return ZoomMorphAnimator(transition: transition, direction: .reverse)
        default:
            return nil
        }
    }

    static func interactionController(for animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        guard let animator = animator as? ZoomMorphAnimator, animator.direction == .reverse,
              let interaction = animator.transition.interaction, interaction.isInteracting else { return nil }
        return interaction
    }

    /// Installs the back swipe and `dismissGesture` on the pushed screen once
    /// it is shown (the system back swipe is off for it: see
    /// `blocksSystemPopGesture`).
    func installInteraction(on viewController: UIViewController) {
        guard interaction == nil, let nav = viewController.navigationController else { return }
        interaction = ZoomMorphInteraction(viewController: viewController, navigationController: nav, gesture: zoom.dismissGesture)
    }

    /// Whether the top screen of `nav` runs its own interactive pop.
    static func blocksSystemPopGesture(in nav: UINavigationController) -> Bool {
        nav.topViewController.map { of($0) != nil } ?? false
    }

    // MARK: - Elements

    /// The source element on the presenting screen: the key re-evaluated in
    /// its scope (a pager may be on another page by now), then the one the
    /// action resolved.
    func sourceView() -> UIView? {
        guard let screen = presentingScreen, screen.isViewLoaded else { return nil }
        var candidates: [String] = []
        if let key = Self.reevaluate(zoom.sourceKeyExpression, in: screen) { candidates.append(key) }
        candidates.append(initialSourceKey)
        for key in candidates {
            if let view = TransitionKeyLocator.view(forKey: key, in: screen.view) { return view }
        }
        return nil
    }

    func alignmentView(in root: UIView) -> UIView? {
        let candidates = [zoom.resolvedAlignmentKey, zoom.alignmentKeyExpression].compactMap { $0 }
        for key in candidates where !key.contains("{{") {
            if let view = TransitionKeyLocator.view(forKey: key, in: root) { return view }
        }
        return nil
    }

    private static func reevaluate(_ expression: String, in screen: ScreenViewController) -> String? {
        guard expression.contains("{{") else { return expression }
        guard let store = screen.screenVariableStore else { return nil }
        guard let value = try? PropertyResolver().resolveToString(expression, context: VariableContext(store: store)),
              !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Geometry

    /// The pose of the incoming screen: a uniform scale (about its centre,
    /// `center` in container coordinates) and a translation that make the
    /// alignment rect `alignment` (in the screen's own coordinates) cover the
    /// source rect `source` (container coordinates), centred on it.
    nonisolated static func pose(source: CGRect, alignment: CGRect, bounds: CGSize, center: CGPoint) -> CGAffineTransform {
        guard alignment.width > 0.5, alignment.height > 0.5, source.width > 0.5, source.height > 0.5 else { return .identity }
        let scale = max(source.width / alignment.width, source.height / alignment.height)
        let bc = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let tx = source.midX - center.x - scale * (alignment.midX - bc.x)
        let ty = source.midY - center.y - scale * (alignment.midY - bc.y)
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: tx, ty: ty)
    }

    /// `rect` (container coordinates) in the posed screen's own coordinates:
    /// the inverse of `pose` (a uniform scale plus a translation).
    nonisolated static func localRect(_ rect: CGRect, pose: CGAffineTransform, bounds: CGSize, center: CGPoint) -> CGRect {
        let scale = pose.a
        guard scale > 0.0001 else { return CGRect(origin: .zero, size: bounds) }
        let bc = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        func local(_ q: CGPoint) -> CGPoint {
            CGPoint(x: bc.x + (q.x - center.x - pose.tx) / scale, y: bc.y + (q.y - center.y - pose.ty) / scale)
        }
        let a = local(CGPoint(x: rect.minX, y: rect.minY))
        let b = local(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    /// The image a view shows (itself or its largest image descendant).
    static func image(in view: UIView) -> UIImage? {
        var best: (UIImage, CGFloat)?
        var stack: [UIView] = [view]
        while let current = stack.popLast() {
            if current.isHidden || current.alpha < 0.01 { continue }
            if let imageView = current as? UIImageView, let image = imageView.image {
                let area = imageView.bounds.width * imageView.bounds.height
                if best == nil || area > best!.1 { best = (image, area) }
            }
            stack.append(contentsOf: current.subviews)
        }
        return best?.0
    }
}

// MARK: - Animator

@MainActor
final class ZoomMorphAnimator: NSObject, UIViewControllerAnimatedTransitioning {

    let transition: ZoomMorphTransition
    let direction: TransitionDirection
    private var cachedAnimator: UIViewPropertyAnimator?

    init(transition: ZoomMorphTransition, direction: TransitionDirection) {
        self.transition = transition
        self.direction = direction
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        direction == .forward ? ZoomMorphTransition.forwardDuration : ZoomMorphTransition.reverseDuration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        interruptibleAnimator(using: transitionContext).startAnimation()
    }

    /// Cubic ease-out (0.33, 1, 0.68, 1); linear while a finger scrubs it.
    private func timing(interactive: Bool) -> UITimingCurveProvider {
        interactive ? UICubicTimingParameters(animationCurve: .linear)
            : UICubicTimingParameters(controlPoint1: CGPoint(x: 0.33, y: 1), controlPoint2: CGPoint(x: 0.68, y: 1))
    }

    func interruptibleAnimator(using ctx: UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
        if let cachedAnimator { return cachedAnimator }
        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: ctx), timingParameters: timing(interactive: ctx.isInteractive))
        cachedAnimator = animator

        let container = ctx.containerView
        guard let fromVC = ctx.viewController(forKey: .from), let toVC = ctx.viewController(forKey: .to) else {
            animator.addCompletion { _ in ctx.completeTransition(!ctx.transitionWasCancelled) }
            return animator
        }
        let fromView = ctx.view(forKey: .from) ?? fromVC.view!
        let toView = ctx.view(forKey: .to) ?? toVC.view!
        let forward = direction == .forward

        // The zoomed screen (incoming on push, leaving on pop) and the presenting one.
        let zoomed = forward ? toView : fromView
        let zoomedFrame = forward ? ctx.finalFrame(for: toVC) : ctx.initialFrame(for: fromVC)
        if forward {
            container.addSubview(toView)
            toView.frame = zoomedFrame
            toView.layoutIfNeeded()
        } else {
            container.insertSubview(toView, belowSubview: fromView)
            toView.frame = ctx.finalFrame(for: toVC)
            toView.layoutIfNeeded()
        }

        guard let source = transition.sourceView() else {
            return crossDissolve(animator, ctx: ctx, zoomed: zoomed, forward: forward, presenting: forward ? fromView : toView)
        }
        let sourceRect = source.convert(source.bounds, to: container)
        let alignment = transition.alignmentView(in: zoomed)
        let alignmentLocal = alignment.map { $0.convert($0.bounds, to: zoomed) } ?? zoomed.bounds
        let bounds = zoomedFrame.size
        let center = CGPoint(x: zoomedFrame.midX, y: zoomedFrame.midY)
        let pose = ZoomMorphTransition.pose(source: sourceRect, alignment: alignmentLocal, bounds: bounds, center: center)
        let maskPosed = ZoomMorphTransition.localRect(sourceRect, pose: pose, bounds: bounds, center: center)
        let sourceRadius = source.layer.cornerRadius

        // Clip of the zoomed screen: the source's shape at the pose, the whole screen at rest.
        let mask = UIView(frame: forward ? maskPosed : CGRect(origin: .zero, size: bounds))
        mask.backgroundColor = .black
        mask.layer.cornerCurve = .continuous
        mask.layer.cornerRadius = forward ? sourceRadius / max(pose.a, 0.001) : 0
        zoomed.mask = mask
        zoomed.transform = forward ? pose : .identity

        // The box: source image → alignment image.
        let alignmentRect = CGRect(x: zoomedFrame.minX + alignmentLocal.minX, y: zoomedFrame.minY + alignmentLocal.minY,
                                   width: alignmentLocal.width, height: alignmentLocal.height)
        let box = UIView(frame: forward ? sourceRect : alignmentRect)
        box.clipsToBounds = true
        box.isUserInteractionEnabled = false
        box.layer.cornerCurve = .continuous
        box.layer.cornerRadius = forward ? sourceRadius : 0
        let sourceImage = ZoomMorphTransition.image(in: source)
        let alignmentImage = alignment.flatMap(ZoomMorphTransition.image(in:))
        let fromLayer = makeImageView(sourceImage, in: box)
        let toLayer = makeImageView(alignmentImage, in: box)
        if fromLayer == nil && toLayer == nil {
            box.isHidden = true
        }
        toLayer?.alpha = forward ? 0 : 1
        // Without an alignment image the box fades away into the screen
        // (and back in on the way out) instead of covering it until the end.
        let fadesBox = toLayer == nil
        if fadesBox, !forward { box.alpha = 0 }
        container.addSubview(box)
        let alignmentAlpha = alignment?.alpha ?? 1
        alignment?.alpha = 0

        animator.addAnimations {
            zoomed.transform = forward ? .identity : pose
            mask.frame = forward ? CGRect(origin: .zero, size: bounds) : maskPosed
            mask.layer.cornerRadius = forward ? 0 : sourceRadius / max(pose.a, 0.001)
            box.frame = forward ? alignmentRect : sourceRect
            box.layer.cornerRadius = forward ? 0 : sourceRadius
            toLayer?.alpha = forward ? 1 : 0
            if fadesBox { box.alpha = forward ? 0 : 1 }
        }
        animator.addCompletion { position in
            let cancelled = ctx.transitionWasCancelled || position == .start
            zoomed.transform = .identity
            zoomed.mask = nil
            box.removeFromSuperview()
            alignment?.alpha = alignmentAlpha
            if cancelled { toView.removeFromSuperview() }
            ctx.completeTransition(!cancelled)
            if !cancelled, forward { self.transition.installInteraction(on: toVC) }
        }
        return animator
    }

    private func makeImageView(_ image: UIImage?, in box: UIView) -> UIImageView? {
        guard let image else { return nil }
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.frame = box.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        box.addSubview(imageView)
        return imageView
    }

    /// No source on screen (the page was scrolled away): the zoomed screen
    /// fades in or out over the still presenting one.
    private func crossDissolve(_ animator: UIViewPropertyAnimator, ctx: UIViewControllerContextTransitioning,
                               zoomed: UIView, forward: Bool, presenting: UIView) -> UIViewPropertyAnimator {
        zoomed.alpha = forward ? 0 : 1
        animator.addAnimations { zoomed.alpha = forward ? 1 : 0 }
        animator.addCompletion { position in
            let cancelled = ctx.transitionWasCancelled || position == .start
            zoomed.alpha = 1
            if cancelled, let to = ctx.view(forKey: .to) { to.removeFromSuperview() }
            ctx.completeTransition(!cancelled)
            if !cancelled, forward, let toVC = ctx.viewController(forKey: .to) { self.transition.installInteraction(on: toVC) }
        }
        return animator
    }
}

// MARK: - Interactive pop

/// The back swipe (leading edge) and `dismissGesture` on a screen pushed with
/// the pose and morph: a pan pops it and scrubs the reverse; it completes past
/// 25% or with a fling, and runs back otherwise.
@MainActor
final class ZoomMorphInteraction: UIPercentDrivenInteractiveTransition, UIGestureRecognizerDelegate {

    private(set) var isInteracting = false
    private weak var viewController: UIViewController?
    private weak var navigationController: UINavigationController?
    private let gesture: DSL.Model.ScreenTransition.DismissGesture
    private var edgePan: UIScreenEdgePanGestureRecognizer?
    private var dismissPan: UIPanGestureRecognizer?

    init(viewController: UIViewController, navigationController: UINavigationController, gesture: DSL.Model.ScreenTransition.DismissGesture) {
        self.viewController = viewController
        self.navigationController = navigationController
        self.gesture = gesture
        super.init()
        guard let view = viewController.view else { return }
        let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handle(_:)))
        edge.edges = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        edge.delegate = self
        view.addGestureRecognizer(edge)
        edgePan = edge
        if gesture != .none {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            pan.delegate = self
            pan.require(toFail: edge)
            view.addGestureRecognizer(pan)
            dismissPan = pan
        }
    }

    /// Progress of a drag: along x for the back swipe; for the dismiss pan the
    /// distance in its direction (`down`: downward only) against 60% of the
    /// screen height (or the width for a sideways drag).
    nonisolated static func progress(translation t: CGPoint, size: CGSize, edgeSwipe: Bool, downOnly: Bool, rtl: Bool) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 0 }
        if edgeSwipe { return min(1, max(0, (rtl ? -t.x : t.x) / size.width)) }
        if downOnly { return min(1, max(0, t.y / (size.height * 0.6))) }
        let horizontal = abs(t.x) / size.width
        let vertical = max(0, t.y) / (size.height * 0.6)
        return min(1, max(horizontal, vertical))
    }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let view = viewController?.view, let nav = navigationController,
              nav.topViewController === viewController, nav.viewControllers.count > 1,
              nav.transitionCoordinator == nil,
              (viewController as? ScreenViewController)?.allowsSwipeBack ?? true else { return false }
        if recognizer === edgePan { return true }
        guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
        let begins = NativeZoomTransition.shouldBeginDismiss(
            gesture: gesture,
            location: pan.location(in: view),
            velocity: pan.velocity(in: view),
            willBegin: true,
            zoomedView: view
        )
        if begins { NativeZoomTransition.releaseHorizontalScrollers(at: pan.location(in: view), in: view) }
        return begins
    }

    @objc private func handle(_ pan: UIPanGestureRecognizer) {
        guard let view = viewController?.view else { return }
        let rtl = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let p = Self.progress(translation: pan.translation(in: view), size: view.bounds.size,
                              edgeSwipe: pan === edgePan, downOnly: gesture == .down, rtl: rtl)
        switch pan.state {
        case .began:
            isInteracting = true
            navigationController?.popViewController(animated: true)
        case .changed:
            update(p)
        case .ended:
            isInteracting = false
            let v = pan.velocity(in: view)
            let fling = pan === edgePan ? (rtl ? -v.x : v.x) : max(gesture == .down ? v.y : max(abs(v.x), v.y), 0)
            completionSpeed = 1
            if p > 0.25 || fling > 800 { finish() } else { cancel() }
        case .cancelled, .failed:
            isInteracting = false
            cancel()
        default:
            break
        }
    }
}
