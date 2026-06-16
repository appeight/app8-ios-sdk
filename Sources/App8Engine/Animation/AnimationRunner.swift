// Single entry point that runs UIView-level and CALayer-level animations under one
// shared `DSL.Model.Animation.Inline` descriptor, so a split `viewBlock`/`layerBlock`
// reads as a single synchronized visual transition.

import UIKit
import QuartzCore

@MainActor
enum AnimationRunner {

    /// Runs `viewBlock` and `layerBlock` under the supplied animation descriptor.
    /// `nil` animation or Reduce Motion runs both instantaneously. Otherwise the layer
    /// block runs in a CATransaction and the view block uses the matching UIView
    /// primitive (spring API / `UIViewPropertyAnimator` / `UIView.animate`), all sharing
    /// `duration` so view + layer stay aligned.
    ///
    /// `additionalOptions` is merged on top of `animation.options`; state-driven callers
    /// pass `[.beginFromCurrentState, .allowUserInteraction]` so re-presses during a
    /// release catch the in-flight values.
    static func run(
        animation: DSL.Model.Animation.Inline?,
        additionalOptions: UIView.AnimationOptions = [],
        layerBlock: () -> Void = {},
        viewBlock: @escaping () -> Void = {}
    ) {
        guard let animation, !UIAccessibility.isReduceMotionEnabled else {
            instantaneous(layerBlock: layerBlock, viewBlock: viewBlock)
            return
        }

        // CATransaction publishes our duration/timing to implicit CALayer animations.
        CATransaction.begin()
        CATransaction.setAnimationDuration(animation.duration)
        if let tf = animation.caTimingFunction {
            CATransaction.setAnimationTimingFunction(tf)
        }
        layerBlock()
        CATransaction.commit()

        let options = animation.uiAnimationOptions.union(additionalOptions)
        switch animation.timing {
        case .spring(let spring):
            if spring.mass != nil || spring.stiffness != nil {
                runWithPropertyAnimator(animation: animation, viewBlock: viewBlock)
            } else {
                UIView.animate(
                    withDuration: animation.duration,
                    delay: animation.delay,
                    usingSpringWithDamping: CGFloat(spring.damping),
                    initialSpringVelocity: CGFloat(spring.velocity),
                    options: options,
                    animations: viewBlock
                )
            }

        case .cubicBezier:
            runWithPropertyAnimator(animation: animation, viewBlock: viewBlock)

        case .curve:
            UIView.animate(
                withDuration: animation.duration,
                delay: animation.delay,
                options: options,
                animations: viewBlock
            )
        }
    }

    /// Runs both blocks synchronously with no animation. Disables implicit
    /// CALayer actions for the layer block.
    static func instantaneous(
        layerBlock: () -> Void = {},
        viewBlock: () -> Void = {}
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layerBlock()
        CATransaction.commit()
        viewBlock()
    }

    // MARK: - UIViewPropertyAnimator path

    private static func runWithPropertyAnimator(
        animation: DSL.Model.Animation.Inline,
        viewBlock: @escaping () -> Void
    ) {
        let animator = UIViewPropertyAnimator(
            duration: animation.duration,
            timingParameters: animation.timingParameters()
        )
        animator.addAnimations(viewBlock)
        animator.startAnimation(afterDelay: animation.delay)
    }

    // MARK: - Explicit keypath animations (used by Shadow / Outline)

    /// Builds a `CABasicAnimation` from the descriptor. The animation is **not** added
    /// to any layer — the caller attaches it. For properties the implicit CATransaction
    /// misses (e.g. set on a sublayer, or model value not yet touched).
    static func makeBasicAnimation(
        keyPath: String,
        from fromValue: Any?,
        to toValue: Any?,
        animation: DSL.Model.Animation.Inline
    ) -> CABasicAnimation {
        let anim = CABasicAnimation(keyPath: keyPath)
        anim.fromValue = fromValue
        anim.toValue = toValue
        anim.duration = animation.duration
        anim.beginTime = animation.delay > 0 ? CACurrentMediaTime() + animation.delay : 0
        if let tf = animation.caTimingFunction {
            anim.timingFunction = tf
        }
        anim.fillMode = .both
        return anim
    }
}
