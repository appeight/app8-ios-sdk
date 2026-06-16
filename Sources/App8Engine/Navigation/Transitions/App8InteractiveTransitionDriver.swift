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

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = trackedView else { return }
        let dimension = isHorizontal ? view.bounds.width : view.bounds.height
        guard dimension > 0 else { return }

        switch gesture.state {
        case .began:
            isInteracting = true
            begin()   // triggers the dismiss/pop; transition becomes interactive

        case .changed:
            update(progress(of: gesture, in: view, dimension: dimension))

        case .ended:
            isInteracting = false
            let p = progress(of: gesture, in: view, dimension: dimension)
            let v = velocityAlongEdge(of: gesture, in: view)
            // Settle from where the finger left off rather than snapping.
            completionSpeed = 1
            if p >= threshold || v >= velocityThreshold {
                finish()
            } else {
                cancel()
            }

        case .cancelled, .failed:
            isInteracting = false
            cancel()

        default:
            break
        }
    }

    private var isHorizontal: Bool {
        switch edge {
        case .leading, .trailing: return true
        case .top, .bottom:       return false
        }
    }

    /// Signed magnitude of drag in the dismissal direction, normalized + clamped.
    private func progress(of gesture: UIPanGestureRecognizer, in view: UIView, dimension: CGFloat) -> CGFloat {
        let t = gesture.translation(in: view)
        let raw: CGFloat
        switch edge {
        case .trailing: raw = t.x
        case .leading:  raw = -t.x
        case .bottom:   raw = t.y
        case .top:      raw = -t.y
        }
        let normalized = raw / dimension
        // Ignore wrong-direction drag (stay at 0); clamp forward drag to 1.
        guard normalized > 0 else { return 0 }
        return min(normalized, 1)
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
