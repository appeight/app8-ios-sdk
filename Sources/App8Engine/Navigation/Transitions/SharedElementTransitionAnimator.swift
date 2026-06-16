// Shared-element ("hero" / composite) transition animator.
//
// Where `PropertyTransitionAnimator` animates whole screens, this animator morphs
// individually *matched* elements between the two screens. Each participating
// component declares a transition `key` on its `content.transition`; the engine
// snapshots each screen's `[key: view]` map (see `App8Service.renderScreen` →
// `ScreenViewController.transitionParticipants`). At transition time the keys
// present on BOTH screens are intersected, and each matched pair is morphed from
// the outgoing element's frame to the incoming element's frame, cross-dissolving
// their snapshots. One matched key reads as a SwiftUI-style zoom; several
// matched keys (optionally staggered) read as a composite.
//
// The screen-level `from`/`to` keyframes still drive the *backdrop* (the
// non-matched content) underneath the morphing elements.
//
// Correctness invariants (public SDK):
//   • The real matched views are hidden only for the duration of the morph and
//     unhidden on completion (success AND cancel) — never left hidden.
//   • All proxy/snapshot views are removed and the screen views reset to identity
//     transform + full opacity on every completion path.
//   • `completeTransition(!wasCancelled)` runs on every path.
//   • Reduce Motion collapses the whole thing to a plain cross-dissolve.

import UIKit

@MainActor
final class SharedElementTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {

    typealias Direction = TransitionDirection

    private let resolved: DSL.Model.ScreenTransition.Resolved
    private let direction: Direction
    private var cachedAnimator: UIViewPropertyAnimator?

    /// Invoked once the transition settles, `true` when completed (not cancelled).
    var onFinished: ((Bool) -> Void)?

    init(resolved: DSL.Model.ScreenTransition.Resolved, direction: Direction) {
        self.resolved = resolved
        self.direction = direction
        super.init()
    }

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        reduceMotion ? min(resolved.animation.duration, 0.25) : resolved.animation.duration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        interruptibleAnimator(using: transitionContext).startAnimation()
    }

    func interruptibleAnimator(using transitionContext: UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
        if let cachedAnimator { return cachedAnimator }

        let container = transitionContext.containerView

        guard
            let fromVC = transitionContext.viewController(forKey: .from),
            let toVC = transitionContext.viewController(forKey: .to)
        else {
            let empty = UIViewPropertyAnimator(duration: 0, curve: .linear) {}
            empty.addCompletion { _ in transitionContext.completeTransition(!transitionContext.transitionWasCancelled) }
            cachedAnimator = empty
            return empty
        }

        let fromView = transitionContext.view(forKey: .from) ?? fromVC.view
        let toView = transitionContext.view(forKey: .to) ?? toVC.view

        // Place the incoming screen and set z-order. The morphing proxies are
        // added last, so they always draw above both screens.
        if let toView {
            toView.frame = transitionContext.finalFrame(for: toVC)
            switch direction {
            case .forward:
                container.addSubview(toView)                       // incoming above outgoing
            case .reverse:
                if toView.superview == nil { container.insertSubview(toView, at: 0) }  // revealed below
            }
        }

        // Destination frames must be final before we read element positions. The
        // incoming screen need not have *painted* — the morph uses the real
        // destination view (not a snapshot of it), so there is no capture-timing
        // dependency on the incoming screen's display pass.
        container.layoutIfNeeded()
        toView?.layoutIfNeeded()

        // Build the matched-element morphers (skipped under Reduce Motion). The
        // morph always runs from the `.from` screen's element to the `.to`
        // screen's element, so a forward push zooms small→large and a reverse pop
        // zooms large→small automatically.
        let fromParticipants = screenViewController(for: fromVC)?.transitionParticipants ?? [:]
        let toParticipants = screenViewController(for: toVC)?.transitionParticipants ?? [:]

        var morphers: [ElementMorpher] = []
        var fallbacks: [ElementFallback] = []
        if !reduceMotion {
            (morphers, fallbacks) = buildElementAnimations(
                from: fromParticipants, to: toParticipants, container: container
            )
        }

        // Master timing: a lone hero may carry its own `animation`; otherwise the
        // transition-level animation drives and per-element `stagger` orders them.
        let master = masterAnimation(for: morphers)
        let duration = reduceMotion ? min(master.duration, 0.25) : master.duration
        let animator = UIViewPropertyAnimator(duration: duration, timingParameters: master.timingParameters())

        // Backdrop (screen-level keyframes) on the non-matched content.
        let plan = backdropPlan()
        apply(plan.outgoing.begin, to: fromView, container: container)
        apply(plan.incoming.begin, to: toView, container: container)
        animator.addAnimations { [weak self] in
            guard let self else { return }
            self.apply(plan.outgoing.end, to: fromView, container: container)
            self.apply(plan.incoming.end, to: toView, container: container)
        }

        // Install + animate each matched element. `delayFactor` realizes stagger.
        for morpher in morphers {
            morpher.installBegin()
            animator.addAnimations({ morpher.applyEnd() }, delayFactor: morpher.delayFactor(forDuration: duration))
        }
        // Unmatched keyed elements fade / slide on their own.
        for fallback in fallbacks {
            fallback.installBegin()
            animator.addAnimations { fallback.applyEnd() }
        }

        animator.addCompletion { [weak self] _ in
            morphers.forEach { $0.cleanup() }
            fallbacks.forEach { $0.cleanup() }
            for view in [fromView, toView] {
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

    // MARK: - Element animation construction

    private func buildElementAnimations(
        from fromParticipants: [String: TransitionParticipant],
        to toParticipants: [String: TransitionParticipant],
        container: UIView
    ) -> (morphers: [ElementMorpher], fallbacks: [ElementFallback]) {

        var morphers: [ElementMorpher] = []
        var fallbacks: [ElementFallback] = []

        let fromKeys = Set(fromParticipants.keys)
        let toKeys = Set(toParticipants.keys)

        // Matched pairs → morph.
        for key in fromKeys.intersection(toKeys).sorted() {
            guard
                let fromP = fromParticipants[key], let fromReal = fromP.view,
                let toP = toParticipants[key], let toReal = toP.view,
                let morpher = ElementMorpher(
                    container: container,
                    fromReal: fromReal,
                    toReal: toReal,
                    // The morph's own settings come from the *incoming* element so
                    // the destination authors the look; fall back to the outgoing.
                    config: toP.config,
                    direction: direction
                )
            else { continue }
            morphers.append(morpher)
        }

        // Outgoing-only keyed elements fade/slide out; incoming-only fade/slide in.
        for key in fromKeys.subtracting(toKeys) {
            if let p = fromParticipants[key], let view = p.view {
                ElementFallback(view: view, config: p.config, appearing: false).map { fallbacks.append($0) }
            }
        }
        for key in toKeys.subtracting(fromKeys) {
            if let p = toParticipants[key], let view = p.view {
                ElementFallback(view: view, config: p.config, appearing: true).map { fallbacks.append($0) }
            }
        }

        return (morphers, fallbacks)
    }

    /// A lone matched element may carry its own timing (per-element custom curve);
    /// otherwise use the transition-level animation.
    private func masterAnimation(for morphers: [ElementMorpher]) -> DSL.Model.Animation.Inline {
        if morphers.count == 1,
           let override = morphers[0].config.animation?.inline(resolveBy: { _ in nil }) {
            return override
        }
        return resolved.animation
    }

    // MARK: - Screen-view-controller resolution

    /// Dig the participating `ScreenViewController` out of a transition context
    /// VC, which may be the screen itself, a modal container, or a flow container.
    private func screenViewController(for vc: UIViewController) -> ScreenViewController? {
        if let screen = vc as? ScreenViewController { return screen }
        if let modal = vc as? ModalViewController { return modal.topScreenViewController }
        if let flow = vc as? FlowViewController { return flow.visibleScreenViewController }
        for child in vc.children {
            if let found = screenViewController(for: child) { return found }
        }
        return nil
    }

    // MARK: - Backdrop keyframes

    private struct Plan {
        var outgoing: DSL.Model.ScreenTransition.Participant
        var incoming: DSL.Model.ScreenTransition.Participant
    }

    private func backdropPlan() -> Plan {
        if reduceMotion {
            let fadeIn = DSL.Model.ScreenTransition.Participant(begin: .opacity(0), end: .opacity(1))
            let stay = DSL.Model.ScreenTransition.Participant(begin: .identity, end: .identity)
            switch direction {
            case .forward: return Plan(outgoing: stay, incoming: fadeIn)
            case .reverse:
                let fadeOut = DSL.Model.ScreenTransition.Participant(begin: .opacity(1), end: .opacity(0))
                return Plan(outgoing: fadeOut, incoming: stay)
            }
        }
        switch direction {
        case .forward:
            return Plan(outgoing: resolved.from, incoming: resolved.to)
        case .reverse:
            let outgoing = resolved.reverseFrom ?? invert(resolved.to)
            let incoming = resolved.reverseTo ?? invert(resolved.from)
            return Plan(outgoing: outgoing, incoming: incoming)
        }
    }

    private func invert(_ p: DSL.Model.ScreenTransition.Participant) -> DSL.Model.ScreenTransition.Participant {
        .init(begin: p.end, end: p.begin)
    }

    private func apply(_ state: DSL.Model.ScreenTransition.TransitionState, to view: UIView?, container: UIView) {
        guard let view else { return }
        view.transform = TransitionMath.affineTransform(
            for: state, viewSize: view.bounds.size, containerSize: container.bounds.size
        )
        view.alpha = CGFloat(state.opacity ?? 1)
    }
}

// MARK: - Element morpher

/// Drives one matched element from its outgoing frame to its incoming frame.
///
/// The asymmetry is the whole trick — and it is what makes this robust:
///
///   • **Source = a snapshot.** The outgoing element is always fully painted on
///     screen, so its snapshot is faithful and cheap. It is lifted into the
///     container *above* the incoming screen and fades/moves out on top.
///   • **Destination = the real view.** The incoming element is the *actual*
///     `toReal` view, given a transform that places it at the source frame and
///     animates back to identity. It is never snapshotted, so there is **no
///     dependency on the incoming screen having painted** (the bug that made the
///     destination base intermittently blank), and because UIKit renders the
///     real view at every step it never rasterizes/upscales (so it stays sharp).
///
/// The cross-dissolve falls out for free: as the source snapshot fades out on
/// top, the real destination — riding the backdrop fade-in underneath (or solid,
/// in reverse) — is revealed. Both follow the *same* morphing frame, so the
/// element reads as one object continuously transforming between screens. Corner
/// radius interpolates on the source; the real view carries its own.
///
/// `morph` selects which axes move:
///   • `frameFade` (default) — frame morph **and** cross-dissolve.
///   • `fade` — cross-dissolve only; both elements stay put (suits co-located
///     elements).
///   • `frame` — frame morph, no dissolve: the opaque source slides into place
///     and the real destination is revealed at completion (no real view shows
///     through mid-flight, so both reals stay hidden until the end).
@MainActor
private final class ElementMorpher {

    let config: DSL.Model.ScreenTransition.ElementTransition

    private let container: UIView
    private weak var fromReal: UIView?
    private weak var toReal: UIView?

    private let sourceSnapshot: UIView           // outgoing render, lifted above both screens
    private let crossFade: Bool                  // morph ≠ .frame ⇒ dissolve over the real dest
    private let morphFrame: Bool                 // morph ≠ .fade  ⇒ interpolate frame + radius

    private let fromFrame: CGRect
    private let toFrame: CGRect
    private let fromRadius: CGFloat
    private let toRadius: CGFloat

    /// Transform that places `toReal` at the source frame; animating it back to
    /// `.identity` morphs the real destination from source → final geometry.
    private let destStartTransform: CGAffineTransform

    init?(
        container: UIView,
        fromReal: UIView,
        toReal: UIView,
        config: DSL.Model.ScreenTransition.ElementTransition,
        direction: TransitionDirection
    ) {
        // Both elements must have a non-degenerate frame in the container.
        // Converting each view's own `bounds` yields its on-screen rect in
        // container coordinates (position + size).
        let f = fromReal.convert(fromReal.bounds, to: container)
        let t = toReal.convert(toReal.bounds, to: container)
        guard f.width > 0.5, f.height > 0.5, t.width > 0.5, t.height > 0.5 else { return nil }

        // Only the *outgoing* element is snapshotted — it is on screen and fully
        // painted, so the render is always faithful (no capture-timing race).
        self.sourceSnapshot = ElementMorpher.render(fromReal)

        self.container = container
        self.fromReal = fromReal
        self.toReal = toReal
        self.config = config
        self.fromFrame = f
        self.toFrame = t
        self.fromRadius = fromReal.layer.cornerRadius
        self.toRadius = toReal.layer.cornerRadius
        self.crossFade = (config.morph != .frame)
        self.morphFrame = (config.morph != .fade)
        self.destStartTransform = ElementMorpher.transform(mapping: t, to: f)
    }

    /// Affine transform that makes a view currently occupying `current` appear at
    /// `target` (scale around centre + recentre). Animating it to `.identity`
    /// returns the view to its laid-out frame.
    private static func transform(mapping current: CGRect, to target: CGRect) -> CGAffineTransform {
        guard current.width > 0, current.height > 0 else { return .identity }
        return CGAffineTransform(translationX: target.midX - current.midX,
                                 y: target.midY - current.midY)
            .scaledBy(x: target.width / current.width, y: target.height / current.height)
    }

    /// Rasterize an on-screen view into an image-view. `drawHierarchy` captures
    /// the live (already-painted) presentation faithfully; `layer.render` is a
    /// synchronous fallback. Only ever called on the outgoing element.
    private static func render(_ view: UIView) -> UIView {
        let bounds = view.bounds
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        let image = renderer.image { ctx in
            if !view.drawHierarchy(in: bounds, afterScreenUpdates: false) {
                view.layer.render(in: ctx.cgContext)
            }
        }
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        return imageView
    }

    func installBegin() {
        // The outgoing element is always hidden — its snapshot stands in for it.
        fromReal?.isHidden = true

        // Lift the source snapshot above both screens at the source frame.
        sourceSnapshot.frame = fromFrame
        sourceSnapshot.layer.cornerRadius = fromRadius
        sourceSnapshot.layer.masksToBounds = true
        sourceSnapshot.alpha = 1
        container.addSubview(sourceSnapshot)

        if crossFade {
            // Real destination is the live base: shrink it to the source frame so
            // it morphs out from under the fading snapshot. It stays visible and
            // rides the backdrop fade-in (forward) / sits solid (reverse).
            toReal?.isHidden = false
            if morphFrame { toReal?.transform = destStartTransform }
        } else {
            // Frame-only: no real view should show through, so keep the
            // destination hidden and reveal it (seamlessly, already in place) at
            // completion.
            toReal?.isHidden = true
        }
    }

    func applyEnd() {
        if morphFrame {
            sourceSnapshot.frame = toFrame
            sourceSnapshot.layer.cornerRadius = toRadius
        }
        if crossFade {
            sourceSnapshot.alpha = 0          // dissolve into the real destination
            toReal?.transform = .identity     // morph the real view to its final geometry
        }
    }

    func cleanup() {
        sourceSnapshot.removeFromSuperview()
        fromReal?.isHidden = false
        toReal?.isHidden = false
        toReal?.transform = .identity         // never leave the real view transformed (cancel-safe)
    }

    /// Stagger expressed as a fraction of the total duration (clamped to `0…1`).
    func delayFactor(forDuration duration: TimeInterval) -> CGFloat {
        guard let stagger = config.stagger, duration > 0 else { return 0 }
        return CGFloat(max(0, min(1, stagger / duration)))
    }
}

// MARK: - Unmatched element fallback

/// Handles a keyed element with no counterpart on the other screen: it fades
/// (and optionally slides) in or out on its own. Operates on the real view and
/// restores it on completion.
@MainActor
private final class ElementFallback {

    private weak var view: UIView?
    private let appearing: Bool
    private let kind: DSL.Model.ScreenTransition.Fallback
    private let originalAlpha: CGFloat
    private let slide: CGAffineTransform

    init?(view: UIView, config: DSL.Model.ScreenTransition.ElementTransition, appearing: Bool) {
        guard config.fallback != .none else { return nil }
        self.view = view
        self.appearing = appearing
        self.kind = config.fallback
        self.originalAlpha = view.alpha
        switch config.fallback {
        case .slideTop:    self.slide = CGAffineTransform(translationX: 0, y: -40)
        case .slideBottom: self.slide = CGAffineTransform(translationX: 0, y: 40)
        case .fade, .none: self.slide = .identity
        }
    }

    func installBegin() {
        guard let view else { return }
        if appearing {
            view.alpha = 0
            view.transform = slide
        } else {
            view.alpha = originalAlpha
            view.transform = .identity
        }
    }

    func applyEnd() {
        guard let view else { return }
        if appearing {
            view.alpha = originalAlpha
            view.transform = .identity
        } else {
            view.alpha = 0
            view.transform = slide
        }
    }

    func cleanup() {
        view?.alpha = originalAlpha
        view?.transform = .identity
    }
}

// MARK: - Shared affine math

/// The keyframe → affine transform mapping, shared with the backdrop apply.
/// Kept here (rather than duplicated) so screen-level keyframes in a shared
/// transition behave identically to `PropertyTransitionAnimator`.
enum TransitionMath {
    static func affineTransform(
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
        return anchored.concatenating(CGAffineTransform(translationX: tx, y: ty))
    }
}

private extension DSL.Model.ScreenTransition.TransitionState {
    static func opacity(_ value: Double) -> Self {
        .init(opacity: value, translate: .zero, scale: .identity, rotate: 0, anchor: .center)
    }
}
