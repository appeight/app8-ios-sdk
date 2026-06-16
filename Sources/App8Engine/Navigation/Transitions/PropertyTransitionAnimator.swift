// Generic property-keyframe animator. Drives both push/pop and present/dismiss
// by animating each screen's view from a `begin` keyframe to an `end` keyframe
// under a single `UIViewPropertyAnimator`, so the engine never needs a bespoke
// animator per transition style.
//
// Correctness invariants (this is a public SDK — see plan §2.10):
//   • The view that remains on screen is always reset to identity transform and
//     full opacity on completion (success AND cancel) — no leaked transforms.
//   • `completeTransition(!transitionWasCancelled)` runs on every path.
//   • Reduce Motion collapses any transition to a short cross-dissolve.

import UIKit

/// Direction a transition runs. `forward` = present/push; `reverse` = dismiss/pop.
/// Shared by `PropertyTransitionAnimator` and `SharedElementTransitionAnimator`.
enum TransitionDirection { case forward, reverse }

@MainActor
final class PropertyTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {

    typealias Direction = TransitionDirection

    private let resolved: DSL.Model.ScreenTransition.Resolved
    private let direction: Direction

    /// Cached so the interactive driver scrubs a single, stable animator.
    private var cachedAnimator: UIViewPropertyAnimator?

    /// Invoked once the transition settles, with `true` when it completed (not
    /// cancelled). Lets owners run bookkeeping uniformly across button,
    /// backdrop-tap, and interactive dismissals.
    var onFinished: ((Bool) -> Void)?

    init(resolved: DSL.Model.ScreenTransition.Resolved, direction: Direction) {
        // `.system` / `.none` are handled at the call site (no custom animator),
        // so a constructed animator is always `.custom`.
        self.resolved = resolved
        self.direction = direction
        super.init()
    }

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// True for the gesture-scrubbable side of an interactive transition (the
    /// dismiss / pop). Such transitions settle with a single, monotonic ease
    /// rather than a spring so the release reads as one motion.
    private var isInteractive: Bool {
        direction == .reverse && (resolved.interactive?.enabled == true)
    }

    /// Timing for the property animation. Interactive transitions use a cubic
    /// **ease-in-out** so the settle is a single, overshoot-free release; paired
    /// with `scrubsLinearly` the finger-tracking phase stays perfectly linear
    /// (the view follows the finger 1:1). Non-interactive transitions keep the
    /// authored animation (which may be a spring).
    private func timingParameters() -> UITimingCurveProvider {
        isInteractive
            ? UICubicTimingParameters(animationCurve: .easeInOut)
            : resolved.animation.timingParameters()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        reduceMotion ? min(resolved.animation.duration, 0.25) : resolved.animation.duration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let animator = interruptibleAnimator(using: transitionContext)
        animator.startAnimation()
    }

    func interruptibleAnimator(using transitionContext: UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
        if let cachedAnimator { return cachedAnimator }

        let container = transitionContext.containerView

        guard
            let fromVC = transitionContext.viewController(forKey: .from),
            let toVC = transitionContext.viewController(forKey: .to)
        else {
            // Degenerate context: finish immediately so navigation never stalls.
            let empty = UIViewPropertyAnimator(duration: 0, curve: .linear) {}
            empty.addCompletion { _ in transitionContext.completeTransition(!transitionContext.transitionWasCancelled) }
            cachedAnimator = empty
            return empty
        }

        let fromView = transitionContext.view(forKey: .from) ?? fromVC.view
        let toView = transitionContext.view(forKey: .to) ?? toVC.view

        // Map context views → keyframes for this direction. `incoming` is the
        // view becoming visible; `outgoing` is the one leaving / going under.
        let plan = resolvePlan()

        // Insert views into the container and set the z-order. `raise` is defined
        // in forward terms (which of incoming/outgoing draws on top); the reverse
        // direction mirrors it so a pop/dismiss reads as the exact inverse.
        //
        // Roles per direction:
        //   forward — context `.to` is incoming (entering), `.from` is outgoing.
        //   reverse — context `.from` is the forward-incoming screen (now leaving),
        //             context `.to` is the forward-outgoing screen (being revealed).
        let raiseIncoming = resolved.raise == .incoming
        if let toView {
            toView.frame = transitionContext.finalFrame(for: toVC)
        }
        switch direction {
        case .forward:
            // forward-incoming == toView, forward-outgoing == fromView.
            guard let toView else { break }
            if raiseIncoming {
                container.addSubview(toView)                  // incoming on top
            } else {
                container.insertSubview(toView, at: 0)        // incoming underneath
                if let fromView { container.bringSubviewToFront(fromView) }
            }
        case .reverse:
            // forward-incoming == fromView, forward-outgoing == toView.
            guard let toView else { break }
            if raiseIncoming {
                // forward-incoming (fromView) stays on top → revealed toView below.
                if toView.superview == nil { container.insertSubview(toView, at: 0) }
            } else {
                // forward-outgoing (toView) on top.
                if toView.superview == nil { container.addSubview(toView) }
                else { container.bringSubviewToFront(toView) }
            }
        }

        // The view that remains visible at the end (must be reset to identity).
        // forward: the entering `toView`. reverse: the revealed `toView`.
        let persistentView = toView

        // Apply BEGIN states.
        apply(plan.outgoing.begin, to: fromView, container: container)
        apply(plan.incoming.begin, to: toView, container: container)

        // Force layout so begin transforms are on screen before animating.
        container.layoutIfNeeded()

        let animator = UIViewPropertyAnimator(
            duration: transitionDuration(using: transitionContext),
            timingParameters: timingParameters()
        )
        // While a percent-driven gesture scrubs a *paused* animator, track the
        // finger 1:1 regardless of the release curve.
        animator.scrubsLinearly = true
        animator.addAnimations { [weak self] in
            guard let self else { return }
            self.apply(plan.outgoing.end, to: fromView, container: container)
            self.apply(plan.incoming.end, to: toView, container: container)
        }
        animator.addCompletion { [weak self] _ in
            // Reset BOTH views — the persistent one must rest at identity; the
            // removed one is harmless to reset. This is the key guard against
            // leaked transforms on the screen that stays in the stack.
            for view in [fromView, persistentView] {
                view?.transform = .identity
                view?.alpha = 1
            }
            let completed = !transitionContext.transitionWasCancelled
            transitionContext.completeTransition(completed)
            self?.onFinished?(completed)
        }
        cachedAnimator = animator
        return animator
    }

    // MARK: - Planning

    private struct Plan {
        /// Keyframes for the leaving / underneath view (context `.from`).
        var outgoing: DSL.Model.ScreenTransition.Participant
        /// Keyframes for the entering / revealed view (context `.to`).
        var incoming: DSL.Model.ScreenTransition.Participant
    }

    private func resolvePlan() -> Plan {
        if reduceMotion {
            // Cross-dissolve regardless of authored keyframes.
            let fadeIn = DSL.Model.ScreenTransition.Participant(begin: .opacity(0), end: .opacity(1))
            let stay = DSL.Model.ScreenTransition.Participant(begin: .identity, end: .identity)
            switch direction {
            case .forward: return Plan(outgoing: stay, incoming: fadeIn)
            case .reverse:
                // The dismissing view fades out; revealed view stays.
                let fadeOut = DSL.Model.ScreenTransition.Participant(begin: .opacity(1), end: .opacity(0))
                return Plan(outgoing: fadeOut, incoming: stay)
            }
        }

        switch direction {
        case .forward:
            return Plan(outgoing: resolved.from, incoming: resolved.to)

        case .reverse:
            // Explicit reverse keyframes win; otherwise auto-invert the forward pair.
            // context `.from` = the screen being dismissed/popped (was the entered one).
            // context `.to`   = the screen being revealed (was underneath).
            let outgoing = resolved.reverseFrom ?? invert(resolved.to)
            let incoming = resolved.reverseTo ?? invert(resolved.from)
            return Plan(outgoing: outgoing, incoming: incoming)
        }
    }

    private func invert(_ p: DSL.Model.ScreenTransition.Participant) -> DSL.Model.ScreenTransition.Participant {
        .init(begin: p.end, end: p.begin)
    }

    // MARK: - Applying a keyframe to a view

    private func apply(_ state: DSL.Model.ScreenTransition.TransitionState, to view: UIView?, container: UIView) {
        guard let view else { return }
        view.transform = affineTransform(for: state, viewSize: view.bounds.size, containerSize: container.bounds.size)
        // A keyframe's opacity is absolute: an omitted `opacity` is the natural,
        // fully-opaque resting state (1) — NOT "leave alpha untouched". Otherwise
        // a `begin` that fades a screen out would never fade it back in at `end`.
        view.alpha = CGFloat(state.opacity ?? 1)
    }

    /// Builds the affine transform for a keyframe: an anchored scale+rotate
    /// followed by a translate (resolved against the container's dimensions).
    private func affineTransform(
        for state: DSL.Model.ScreenTransition.TransitionState,
        viewSize: CGSize,
        containerSize: CGSize
    ) -> CGAffineTransform {
        let tx = state.translate.x.resolved(against: containerSize.width)
        let ty = state.translate.y.resolved(against: containerSize.height)

        let isIdentityScaleRotate = state.scale.x == 1 && state.scale.y == 1 && state.rotate == 0
        if isIdentityScaleRotate {
            return CGAffineTransform(translationX: tx, y: ty)
        }

        // Offset of the anchor from the view's centre (UIView transforms about centre).
        let anchorOffset = CGPoint(
            x: (state.anchor.x - 0.5) * viewSize.width,
            y: (state.anchor.y - 0.5) * viewSize.height
        )
        let radians = CGFloat(state.rotate) * .pi / 180

        let anchored = CGAffineTransform.identity
            .translatedBy(x: anchorOffset.x, y: anchorOffset.y)
            .rotated(by: radians)
            .scaledBy(x: CGFloat(state.scale.x), y: CGFloat(state.scale.y))
            .translatedBy(x: -anchorOffset.x, y: -anchorOffset.y)

        // Anchored scale/rotate first, then the overall translate.
        return anchored.concatenating(CGAffineTransform(translationX: tx, y: ty))
    }
}

// MARK: - Keyframe conveniences

private extension DSL.Model.ScreenTransition.TransitionState {
    static func opacity(_ value: Double) -> Self {
        .init(opacity: value, translate: .zero, scale: .identity, rotate: 0, anchor: .center)
    }
}
