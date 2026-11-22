// Percent-driven interactive driver for gesture-dismissed modals and
// gesture-popped pushes. A pan recognizer on the dismissing view maps drag
// distance along the configured edge to transition progress, with a rubber-band
// guard on wrong-direction drag and velocity-or-threshold completion.

import UIKit

@MainActor
final class App8InteractiveTransitionDriver: UIPercentDrivenInteractiveTransition, UIGestureRecognizerDelegate {

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
        if let dismissPan { dismissPan.view?.removeGestureRecognizer(dismissPan) }
        pan = nil
        dismissPan = nil
        trackedView = nil
    }

    // MARK: - Drag to dismiss as a card (zoom from a full-screen source)

    /// The screen that shrinks into a card under the finger while a drag
    /// dismisses it (nil: no card).
    weak var cardView: UIView?
    /// The navigation bar over the card: it fades as the card shrinks, so the
    /// screen's bar buttons never float over the screen below.
    weak var cardBar: UIView?
    private var dismissPan: UIPanGestureRecognizer?
    private var dismissShouldBegin: ((UIPanGestureRecognizer) -> Bool)?

    /// A pan from anywhere on `view` that the content does not use.
    func attachDismissPan(to view: UIView, shouldBegin: @escaping (UIPanGestureRecognizer) -> Bool) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        if let edgePan = self.pan { pan.require(toFail: edgePan) }
        view.addGestureRecognizer(pan)
        dismissPan = pan
        dismissShouldBegin = shouldBegin
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPan, let pan = dismissPan else { return true }
        return dismissShouldBegin?(pan) ?? true
    }

    /// Card scale for a drag progress: 1 at rest, down to 0.6.
    nonisolated static func cardScale(progress: CGFloat) -> CGFloat {
        max(0.6, 1 - min(max(progress, 0), 1) * 0.5)
    }

    private func applyCard(translation t: CGPoint, progress: CGFloat) {
        guard let card = cardView else { return }
        let scale = Self.cardScale(progress: progress)
        card.transform = CGAffineTransform(translationX: t.x, y: t.y).scaledBy(x: scale, y: scale)
        card.layer.cornerCurve = .continuous
        card.layer.cornerRadius = 32 / scale
        card.clipsToBounds = true
        cardBar?.alpha = max(0, 1 - progress * 4)
    }

    /// Runs after a cancelled interactive transition has settled.
    var onCancelled: (() -> Void)?

    private func afterCancel() {
        guard let onCancelled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: onCancelled)
    }

    /// A cancelled drag springs the card back to full screen.
    private func releaseCard(cancelled: Bool) {
        guard let card = cardView else { return }
        let bar = cardBar
        let reset = {
            card.transform = .identity
            card.layer.cornerRadius = 0
            if cancelled { bar?.alpha = 1 }
        }
        if !cancelled {
            // The bar is hidden or replaced by the screen below once the pop ends.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { bar?.alpha = 1 }
        }
        if cancelled {
            UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction], animations: reset)
        } else {
            UIView.animate(withDuration: 0.32, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: reset)
        }
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
        // A drag from anywhere (zoom dismiss) counts its distance in any
        // direction but up.
        let isFreeDrag = gesture === dismissPan
        func drag() -> CGFloat {
            guard isFreeDrag else { return signedDrag(of: gesture, in: view) }
            let t = gesture.translation(in: view)
            return max(abs(t.x), t.y)
        }

        switch gesture.state {
        case .began:
            committed = false

        case .changed:
            let raw = drag()
            if committed {
                let p = min(max(raw, 0) / dimension, 1)
                update(p)
                applyCard(translation: gesture.translation(in: view), progress: p)
            } else if raw > 0 {
                commit(view: view, gesture: gesture, dimension: dimension)
            } else if !isFreeDrag {
                // Wrong-direction (or at-rest) drag: elastic resistance only.
                view.transform = rubberBand(translation: gesture.translation(in: view), dimension: dimension)
            }

        case .ended:
            if committed {
                isInteracting = false
                committed = false
                completionSpeed = 1   // settle from where the finger left off
                let p = min(max(drag(), 0) / dimension, 1)
                let v = isFreeDrag ? hypot(gesture.velocity(in: view).x, max(0, gesture.velocity(in: view).y))
                                   : velocityAlongEdge(of: gesture, in: view)
                let finishing = p >= threshold || v >= velocityThreshold
                releaseCard(cancelled: !finishing)
                if finishing { finish() } else { cancel(); afterCancel() }
            } else {
                releaseRubberBand(view)
            }

        case .cancelled, .failed:
            if committed {
                isInteracting = false
                committed = false
                releaseCard(cancelled: true)
                cancel()
                afterCancel()
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
