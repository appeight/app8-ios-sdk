import ObjectiveC
import UIKit

/// Applies a component's resolved `isHidden`, animated when the property
/// carries an `animation` (docs/animations.md "Animated visibility").
///
/// - First apply, cell binding / reuse, Reduce Motion, no animation, or a view
///   that is not in a window: the value applies at once.
/// - Arranged subview of a `UIStackView`: one animated layout pass, the UIKit
///   way (`isHidden` + `alpha` + `layoutIfNeeded()` on the top of the view
///   tree inside the animation), so the component grows or shrinks along the
///   stack axis and everything that depends on it (siblings after it, the
///   stack, its ancestors, an enclosing scroll view's content size) moves on
///   the same curve. The component clips to its animating bounds and its
///   content keeps its full size, so the moving edge reveals or covers it
///   instead of squeezing it.
/// - Anywhere else: an alpha cross-fade (the frame does not change).
///
/// A change while one is running starts from the in-flight state: the new
/// animation is additive on top of the running one, and only the latest
/// change's completion settles the view.
@MainActor
enum HiddenTransition {

    /// Per-view transition bookkeeping, kept as an associated object.
    final class Record {
        /// The value last applied (nil: never applied).
        var target: Bool?
        /// Bumped on every change; a completion only settles its own change.
        var generation = 0
        var inFlight = false
        /// Alpha the component shows when visible (its style / property alpha).
        var restAlpha: CGFloat = 1
        /// `clipsToBounds` before the transition clipped the view.
        var savedClipsToBounds: Bool?
        /// The content's required trailing-edge pin along the stack axis,
        /// deactivated while the component is collapsed (or collapsing).
        var contentPin: NSLayoutConstraint?
    }

    private static var recordKey: UInt8 = 0

    static func record(for view: UIView) -> Record {
        if let record = objc_getAssociatedObject(view, &recordKey) as? Record { return record }
        let record = Record()
        objc_setAssociatedObject(view, &recordKey, record, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return record
    }

    /// Test seam: Reduce Motion as the runtime sees it.
    static var isReduceMotionEnabled: () -> Bool = { UIAccessibility.isReduceMotionEnabled }

    /// Applies `hidden` to `view`. `animated: false` (first bind, cell reuse)
    /// always applies at once.
    static func apply(_ hidden: Bool, to view: UIView, animation: DSL.Model.Animation.Inline?, animated: Bool) {
        let record = record(for: view)
        if record.target == hidden && (record.inFlight || view.isHidden == hidden) { return }

        let isFirstApply = record.target == nil
        record.target = hidden
        record.generation += 1

        guard animated, !isFirstApply, let animation, animation.duration > 0,
              !isReduceMotionEnabled(), view.window != nil else {
            applyInstantly(hidden, to: view, record: record)
            return
        }

        if !record.inFlight { record.restAlpha = view.alpha }

        if let stack = view.superview as? UIStackView, stack.arrangedSubviews.contains(where: { $0 === view }) {
            animateInStack(hidden, view: view, stack: stack, animation: animation, record: record)
        } else {
            crossFade(hidden, view: view, animation: animation, record: record)
        }
    }

    // MARK: - Instant

    private static func applyInstantly(_ hidden: Bool, to view: UIView, record: Record) {
        if record.inFlight {
            view.layer.removeAllAnimations()
            view.alpha = record.restAlpha
            record.inFlight = false
        }
        restoreClipping(view, record: record)
        if view.isHidden != hidden { view.isHidden = hidden }
        if !hidden { reattachContent(view, record: record) }
        NativeVisibility.invalidate()
    }

    // MARK: - Stack: one animated layout pass

    private static func animateInStack(
        _ hidden: Bool,
        view: UIView,
        stack: UIStackView,
        animation: DSL.Model.Animation.Inline,
        record: Record
    ) {
        let root = layoutRoot(of: view)
        let wasInFlight = record.inFlight
        // Settle anything already pending so only this change animates.
        if !wasInFlight { UIView.performWithoutAnimation { root.layoutIfNeeded() } }

        if record.savedClipsToBounds == nil { record.savedClipsToBounds = view.clipsToBounds }
        view.clipsToBounds = true
        // The content lays out at its natural size whatever the component's
        // own extent; appearing re-pins it inside the animated pass.
        detachContent(view, axis: stack.axis, record: record)

        if !hidden && !wasInFlight {
            // Appearing from fully hidden: collapse the (still hidden, so
            // invisible) view to zero along the axis with its content laid
            // out at full size, so the animated pass grows it from nothing.
            // A hidden view whose content was pinned keeps a squeezed content
            // size (the stack's hiding constraint is only 999.999), so this
            // pass is what moves it to zero; nothing visible changes.
            view.alpha = 0
            UIView.performWithoutAnimation { root.layoutIfNeeded() }
        }

        let generation = record.generation
        let restAlpha = record.restAlpha
        record.inFlight = true
        let scrollViews = enclosingScrollViews(of: view)
        NativeVisibility.invalidate()

        run(animation, animations: {
            view.isHidden = hidden
            if !hidden { reattachContent(view, record: record) }
            view.alpha = hidden ? 0 : restAlpha
            root.layoutIfNeeded()
            for scrollView in scrollViews { clampContentOffset(scrollView) }
        }, completion: { [weak view] in
            guard let view, record.generation == generation else { return }
            record.inFlight = false
            if hidden {
                // Hidden views keep their content detached (no conflict with
                // the stack's zero-size constraint, and ready to reappear).
                view.alpha = restAlpha
            }
            restoreClipping(view, record: record)
            NativeVisibility.invalidate()
        })
    }

    // MARK: - Elsewhere: cross-fade

    private static func crossFade(_ hidden: Bool, view: UIView, animation: DSL.Model.Animation.Inline, record: Record) {
        let generation = record.generation
        let restAlpha = record.restAlpha
        if !hidden {
            if view.isHidden {
                view.alpha = 0
                view.isHidden = false
            }
        }
        record.inFlight = true
        NativeVisibility.invalidate()
        run(animation, animations: {
            view.alpha = hidden ? 0 : restAlpha
        }, completion: { [weak view] in
            guard let view, record.generation == generation else { return }
            record.inFlight = false
            if hidden {
                view.isHidden = true
                view.alpha = restAlpha
            }
            NativeVisibility.invalidate()
        })
    }

    // MARK: - Animation driver

    private static func run(_ animation: DSL.Model.Animation.Inline, animations: @escaping () -> Void, completion: @escaping () -> Void) {
        let animator = UIViewPropertyAnimator(duration: animation.duration, timingParameters: animation.timingParameters())
        animator.isUserInteractionEnabled = true
        animator.addAnimations(animations)
        animator.addCompletion { _ in completion() }
        animator.startAnimation(afterDelay: animation.delay)
    }

    // MARK: - Content detaching

    /// Deactivates the required pin between the component's content view and
    /// its trailing edge along the stack axis. The content (top / leading
    /// pinned) then keeps its natural size while the component collapses to
    /// zero under the stack's hiding constraint: it is covered or revealed
    /// by the moving edge instead of being squeezed. Any softer pin would
    /// still out-rank a label's compression resistance and squeeze it.
    private static func detachContent(_ view: UIView, axis: NSLayoutConstraint.Axis, record: Record) {
        guard record.contentPin == nil,
              let content = (view as? CViewProtocol)?.contentView,
              content.superview === view else { return }
        let attribute: NSLayoutConstraint.Attribute = axis == .vertical ? .bottom : .trailing
        guard let pin = view.constraints.first(where: { c in
            c.isActive && c.priority == .required && c.relation == .equal && c.constant == 0
                && c.firstAttribute == attribute && c.secondAttribute == attribute
                && ((c.firstItem === content && c.secondItem === view) || (c.firstItem === view && c.secondItem === content))
        }) else { return }
        pin.isActive = false
        record.contentPin = pin
    }

    private static func reattachContent(_ view: UIView, record: Record) {
        guard let pin = record.contentPin else { return }
        pin.isActive = true
        record.contentPin = nil
    }

    private static func restoreClipping(_ view: UIView, record: Record) {
        guard let saved = record.savedClipsToBounds else { return }
        view.clipsToBounds = saved
        record.savedClipsToBounds = nil
    }

    // MARK: - Geometry helpers

    /// The top of the view tree below the window: laying it out inside the
    /// animation moves every frame that depends on the change.
    static func layoutRoot(of view: UIView) -> UIView {
        var root = view
        while let parent = root.superview, !(parent is UIWindow) { root = parent }
        return root
    }

    private static func enclosingScrollViews(of view: UIView) -> [UIScrollView] {
        var result: [UIScrollView] = []
        var current = view.superview
        while let v = current {
            if let scrollView = v as? UIScrollView { result.append(scrollView) }
            current = v.superview
        }
        return result
    }

    /// Brings a scroll view that is now past its end back inside it (the last
    /// section closing at the bottom); content above the change never moves.
    private static func clampContentOffset(_ scrollView: UIScrollView) {
        let inset = scrollView.adjustedContentInset
        let size = scrollView.bounds.size
        var offset = scrollView.contentOffset
        let maxY = max(-inset.top, scrollView.contentSize.height + inset.bottom - size.height)
        let maxX = max(-inset.left, scrollView.contentSize.width + inset.right - size.width)
        if offset.y > maxY { offset.y = maxY }
        if offset.x > maxX { offset.x = maxX }
        if offset != scrollView.contentOffset { scrollView.contentOffset = offset }
    }
}
