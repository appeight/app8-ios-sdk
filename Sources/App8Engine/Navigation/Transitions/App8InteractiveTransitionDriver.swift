// Percent-driven interactive driver for gesture-dismissed modals and
// gesture-popped pushes. A pan recognizer on the dismissing view maps drag
// distance along the configured edge to transition progress, with a rubber-band
// guard on wrong-direction drag and velocity-or-threshold completion.

import UIKit

@MainActor
final class App8InteractiveTransitionDriver: UIPercentDrivenInteractiveTransition {

    /// True while a pan is actively driving the transition. The transitioning
    /// delegate / nav coordinator returns this driver as the interaction
    /// controller only while interacting, so non-gesture invocations animate
    /// normally.
    private(set) var isInteracting = false

    private let edge: DSL.Model.ScreenTransition.Edge
    private let threshold: CGFloat
    private let velocityThreshold: CGFloat

    /// Kicks off the dismissal/pop synchronously when the gesture begins, so the
    /// transition is live for subsequent `update(_:)` calls.
    private let begin: () -> Void

    private weak var trackedView: UIView?
    private var pan: UIPanGestureRecognizer?

    init(
        edge: DSL.Model.ScreenTransition.Edge,
        config: DSL.Model.ScreenTransition.InteractiveConfig,
        begin: @escaping () -> Void
    ) {
        self.edge = config.edge ?? edge
        self.threshold = CGFloat(config.threshold)
        self.velocityThreshold = CGFloat(config.velocity)
        self.begin = begin
        super.init()
    }

    /// Attach a full-view pan recognizer to the dismissing view (modal dismiss).
    func attach(to view: UIView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(pan)
        self.pan = pan
        self.trackedView = view
    }

    /// Attach a screen-edge pan recognizer (interactive push pop) originating
    /// from `edges`.
    func attachScreenEdge(to view: UIView, edges: UIRectEdge) {
        let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.edges = edges
        view.addGestureRecognizer(pan)
        self.pan = pan
        self.trackedView = view
    }

    func detach() {
        if let pan, let trackedView { trackedView.removeGestureRecognizer(pan) }
        pan = nil
        trackedView = nil
    }

    // MARK: - Gesture handling
    //
    // The dismiss only *begins* once the drag commits in the dismiss direction.
    // Before that — including any wrong-direction drag (e.g. swiping a bottom
    // sheet up) — the tracked view rubber-bands with elastic resistance and eases
    // back on release, so the sheet never starts dismissing from a wrong-way pull.

    /// True once the drag has committed and the percent-driven dismiss is live.
    private var committed = false

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = trackedView else { return }
        let dimension = isHorizontal ? view.bounds.width : view.bounds.height
        guard dimension > 0 else { return }

        switch gesture.state {
        case .began:
            committed = false

        case .changed:
            let raw = signedDrag(of: gesture, in: view)
            if committed {
                update(min(max(raw, 0) / dimension, 1))
            } else if raw > 0 {
                commit(view: view, gesture: gesture, dimension: dimension)
            } else {
                // Wrong-direction (or at-rest) drag: elastic resistance only.
                view.transform = rubberBand(translation: gesture.translation(in: view), dimension: dimension)
            }

        case .ended:
            if committed {
                isInteracting = false
                committed = false
                completionSpeed = 1   // settle from where the finger left off
                let p = min(max(signedDrag(of: gesture, in: view), 0) / dimension, 1)
                let v = velocityAlongEdge(of: gesture, in: view)
                if p >= threshold || v >= velocityThreshold { finish() } else { cancel() }
            } else {
                releaseRubberBand(view)
            }

        case .cancelled, .failed:
            if committed {
                isInteracting = false
                committed = false
                cancel()
            } else {
                releaseRubberBand(view)
            }

        default:
            break
        }
    }

    /// Commit to the dismiss: clear any rubber-band offset, mark interactive, and
    /// kick off the transition so subsequent `update(_:)` calls drive it.
    private func commit(view: UIView, gesture: UIPanGestureRecognizer, dimension: CGFloat) {
        view.transform = .identity
        committed = true
        isInteracting = true
        begin()
        update(min(max(signedDrag(of: gesture, in: view), 0) / dimension, 1))
    }

    /// Ease a rubber-banded view back to rest — a single cubic ease-in-out release.
    private func releaseRubberBand(_ view: UIView) {
        isInteracting = false
        guard view.transform != .identity else { return }
        UIViewPropertyAnimator(
            duration: 0.3,
            controlPoint1: CGPoint(x: 0.42, y: 0),
            controlPoint2: CGPoint(x: 0.58, y: 1)
        ) { view.transform = .identity }.startAnimation()
    }

    private var isHorizontal: Bool {
        switch edge {
        case .leading, .trailing: return true
        case .top, .bottom:       return false
        }
    }

    /// Signed drag distance along the dismissal direction (positive = toward
    /// dismissal, negative = the wrong way).
    private func signedDrag(of gesture: UIPanGestureRecognizer, in view: UIView) -> CGFloat {
        let t = gesture.translation(in: view)
        switch edge {
        case .trailing: return t.x
        case .leading:  return -t.x
        case .bottom:   return t.y
        case .top:      return -t.y
        }
    }

    /// Elastic rubber-band transform resisting motion *opposite* the dismiss
    /// direction (the classic diminishing-returns curve). Movement toward the
    /// dismiss direction returns identity here — it commits the transition instead.
    private func rubberBand(translation t: CGPoint, dimension: CGFloat) -> CGAffineTransform {
        func damp(_ x: CGFloat) -> CGFloat {
            let d = max(dimension, 1)
            return (1 - 1 / (abs(x) * 0.55 / d + 1)) * d
        }
        switch edge {
        case .bottom:   return CGAffineTransform(translationX: 0, y: -damp(min(0, t.y)))
        case .top:      return CGAffineTransform(translationX: 0, y:  damp(max(0, t.y)))
        case .trailing: return CGAffineTransform(translationX: -damp(min(0, t.x)), y: 0)
        case .leading:  return CGAffineTransform(translationX:  damp(max(0, t.x)), y: 0)
        }
    }

    private func velocityAlongEdge(of gesture: UIPanGestureRecognizer, in view: UIView) -> CGFloat {
        let v = gesture.velocity(in: view)
        switch edge {
        case .trailing: return v.x
        case .leading:  return -v.x
        case .bottom:   return v.y
        case .top:      return -v.y
        }
    }
}
