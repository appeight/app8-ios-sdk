//
//  NativeZoomTransition.swift
//  App8Engine
//
//  `{ "preset": "zoom", "sourceKey": … }` → iOS 18 `preferredTransition =
//  .zoom(options:sourceViewProvider:)`. The source is the presenting-screen
//  element whose `content.transition.key` matches `sourceKey`.
//

import ObjectiveC
import UIKit

// MARK: - Element key tags

/// Live `content.transition.key` of a rendered element. Keys may be expressions
/// (`"{{'card-' + item.handle}}"`), so they are resolved in the component's
/// current scope when looked up — a reused collection cell reports its new item.
@MainActor
final class TransitionKeyTag {
    private static var key: UInt8 = 0

    let rawKey: String
    /// Resolved when tagged; used when the view model is gone.
    let keyAtRender: String
    private weak var viewModel: ComponentViewModelAbstract?

    init(rawKey: String, viewModel: ComponentViewModelAbstract?) {
        self.rawKey = rawKey
        self.viewModel = viewModel
        self.keyAtRender = rawKey.contains("{{") ? (viewModel?.resolvePropertyToString(rawKey) ?? rawKey) : rawKey
    }

    var currentKey: String {
        guard rawKey.contains("{{") else { return rawKey }
        return viewModel?.resolvePropertyToString(rawKey) ?? keyAtRender
    }

    static func tag(_ view: UIView, rawKey: String, viewModel: ComponentViewModelAbstract?) -> TransitionKeyTag {
        let tag = TransitionKeyTag(rawKey: rawKey, viewModel: viewModel)
        objc_setAssociatedObject(view, &key, tag, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return tag
    }

    static func tag(of view: UIView) -> TransitionKeyTag? {
        objc_getAssociatedObject(view, &key) as? TransitionKeyTag
    }
}

@MainActor
enum TransitionKeyLocator {

    /// The visible view under `root` whose element key equals `key`. Views on
    /// screen win over off-screen ones (recycled cells keep stale tags).
    static func view(forKey key: String, in root: UIView?) -> UIView? {
        guard let root, !key.isEmpty else { return nil }
        var offscreen: UIView?
        var stack: [UIView] = [root]
        while let view = stack.popLast() {
            if view.isHidden || view.alpha < 0.01 { continue }
            if let tag = TransitionKeyTag.tag(of: view), tag.currentKey == key {
                if isOnScreen(view, root: root) { return view }
                if offscreen == nil { offscreen = view }
            }
            stack.append(contentsOf: view.subviews)
        }
        return offscreen.flatMap { isOnScreen($0, root: root) ? $0 : nil }
    }

    private static func isOnScreen(_ view: UIView, root: UIView) -> Bool {
        let frame = view.convert(view.bounds, to: root)
        return frame.width > 0 && frame.height > 0 && frame.intersects(root.bounds)
    }
}

// MARK: - Zoom transition

@MainActor
enum NativeZoomTransition {

    /// Sets `preferredTransition = .zoom` on `viewController` with its source
    /// on `presentingScreen`. Returns false when no source element is on screen
    /// (the caller falls back to a cross-dissolve).
    @discardableResult
    static func apply(
        to viewController: UIViewController,
        zoom: DSL.Model.ScreenTransition.NativeZoom,
        presentingScreen: ScreenViewController?,
        logger: A8Log?
    ) -> Bool {
        guard let presentingScreen else { return false }
        let initialKey = zoom.resolvedSourceKey ?? zoom.sourceKeyExpression
        guard TransitionKeyLocator.view(forKey: initialKey, in: presentingScreen.view) != nil else {
            logger?.warning("transition.zoom.sourceMissing: no element with key '\(initialKey)' on the presenting screen — cross-dissolve")
            return false
        }

        let options = UIViewController.Transition.ZoomOptions()
        let gesture = zoom.dismissGesture
        options.interactiveDismissShouldBegin = { [weak viewController] context in
            MainActor.assumeIsolated {
                shouldBeginDismiss(gesture: gesture, context: context, zoomedView: viewController?.view)
            }
        }
        if let alignmentExpression = zoom.alignmentKeyExpression {
            let initialAlignment = zoom.resolvedAlignmentKey
            options.alignmentRectProvider = { [weak presentingScreen] context in
                MainActor.assumeIsolated {
                    let zoomedView = context.zoomedViewController.view
                    let key = presentingScreen.flatMap { reevaluate(alignmentExpression, in: $0) }
                    let candidates = [key, initialAlignment, alignmentExpression].compactMap { $0 }
                    for candidate in candidates {
                        if let view = TransitionKeyLocator.view(forKey: candidate, in: zoomedView), let zoomedView {
                            return view.convert(view.bounds, to: zoomedView)
                        }
                    }
                    return nil
                }
            }
        }

        let sourceExpression = zoom.sourceKeyExpression
        viewController.preferredTransition = .zoom(options: options) { [weak presentingScreen] _ in
            MainActor.assumeIsolated {
                guard let presentingScreen else { return nil }
                // Re-evaluated in the presenting screen's scope (dismissal can
                // return to a different element), then the key the action resolved.
                var candidates: [String] = []
                if let key = reevaluate(sourceExpression, in: presentingScreen) { candidates.append(key) }
                candidates.append(initialKey)
                for key in candidates {
                    if let view = TransitionKeyLocator.view(forKey: key, in: presentingScreen.view) {
                        return view
                    }
                }
                return nil
            }
        }
        return true
    }

    /// The cross-dissolve used when the source element is missing.
    static func crossDissolveFallback(mode: DSL.Model.ScreenTransition.Mode) -> DSL.Model.ScreenTransition.Resolved {
        var inline = DSL.Model.ScreenTransition.Inline.empty
        inline.preset = .crossDissolve
        inline.mode = mode
        return DSL.Model.ScreenTransition.resolve(inline)
    }

    /// Pushes `screenVC` with the native zoom out of the top screen's source
    /// element, or a cross-dissolve when the source is missing.
    static func push(
        _ screenVC: UIViewController,
        on navController: UINavigationController,
        transition: DSL.Model.ScreenTransition.Resolved,
        coordinator: App8NavTransitionCoordinator?,
        logger: A8Log?
    ) {
        let presenting = navController.topViewController as? ScreenViewController
        if let zoom = transition.nativeZoom,
           apply(to: screenVC, zoom: zoom, presentingScreen: presenting, logger: logger) {
            navController.pushViewController(screenVC, animated: true)
            return
        }
        if let coordinator {
            coordinator.register(crossDissolveFallback(mode: .push), for: screenVC)
            navController.pushViewController(screenVC, animated: true)
        } else {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.3
            navController.view.layer.add(fade, forKey: kCATransition)
            navController.pushViewController(screenVC, animated: false)
        }
    }

    /// `expression` in the presenting screen's scope; nil when it doesn't resolve.
    private static func reevaluate(_ expression: String, in screen: ScreenViewController) -> String? {
        guard expression.contains("{{") else { return expression }
        guard let store = screen.screenVariableStore else { return nil }
        let resolver = PropertyResolver()
        guard let value = try? resolver.resolveToString(expression, context: VariableContext(store: store)),
              !value.isEmpty else { return nil }
        return value
    }

    /// `none`: never. `down`: a mostly vertical, downward drag. `any`: any drag
    /// the content under the finger cannot use itself (a zoomed scroll view, a
    /// horizontal pan a horizontal scroller can still scroll with, or the
    /// pull-down of a stretchy-top scroll view).
    private static func shouldBeginDismiss(
        gesture: DSL.Model.ScreenTransition.DismissGesture,
        context: UIViewController.Transition.ZoomOptions.InteractionContext,
        zoomedView: UIView?
    ) -> Bool {
        shouldBeginDismiss(
            gesture: gesture,
            location: context.location,
            velocity: CGPoint(x: context.velocity.dx, y: context.velocity.dy),
            willBegin: context.willBegin,
            zoomedView: zoomedView
        )
    }

    /// `interactiveDismissShouldBegin` decision, testable without a live
    /// transition. `location` is in `zoomedView`'s coordinates.
    static func shouldBeginDismiss(
        gesture: DSL.Model.ScreenTransition.DismissGesture,
        location: CGPoint,
        velocity: CGPoint,
        willBegin: Bool,
        zoomedView: UIView?
    ) -> Bool {
        switch gesture {
        case .none:
            return false
        case .down:
            return velocity.y > 0 && abs(velocity.y) > abs(velocity.x)
        case .any:
            guard willBegin else { return true }
            let horizontal = abs(velocity.x) > abs(velocity.y)
            // A pan from the leading edge always dismisses, even over a pager.
            if let root = zoomedView, horizontal {
                let rtl = root.effectiveUserInterfaceLayoutDirection == .rightToLeft
                // `location` is where the pan is recognized, a few points past
                // its start; allow for that travel.
                let x = location.x
                let edge = App8CollectionView.edgeWidth + 24
                if rtl ? (velocity.x < 0 && x > root.bounds.width - edge)
                       : (velocity.x > 0 && x < edge) {
                    return true
                }
            }
            guard let root = zoomedView,
                  let hit = root.hitTest(location, with: nil) else { return true }
            var view: UIView? = hit
            while let current = view, current !== root.superview {
                if let scroll = current as? UIScrollView {
                    if scroll.zoomScale > scroll.minimumZoomScale + 0.01 { return false }
                    // The innermost horizontal scroller keeps any pan it can use:
                    // see `claimsHorizontalPan`.
                    if horizontal, claimsHorizontalPan(scroll, velocityX: velocity.x) { return false }
                    // A stretchy-top scroll view uses the pull-down at its top.
                    if !horizontal, velocity.y > 0, let zooming = scroll as? App8ZoomingScrollView, zooming.claimsPullDown {
                        return false
                    }
                }
                view = current.superview
            }
            return true
        }
    }

    /// Whether a horizontal scroller keeps a horizontal pan rather than leaving
    /// it to the dismiss: always while it is moving (dragged, decelerating,
    /// snapping to a page or bouncing back from an edge), for a forward drag
    /// (it rubber-bands at its end instead of dismissing), and for a back drag
    /// while it has content that way. Only a back drag on a scroller at rest at
    /// its leading end reaches the dismiss.
    static func claimsHorizontalPan(_ scroll: UIScrollView, velocityX: CGFloat) -> Bool {
        guard scroll.isScrollEnabled else { return false }
        let inset = scroll.adjustedContentInset
        let minX = -inset.left
        let maxX = scroll.contentSize.width + inset.right - scroll.bounds.width
        guard maxX > minX + 1 else { return false }
        if scroll.isDragging || scroll.isDecelerating { return true }
        let x = scroll.contentOffset.x
        if x < minX - 0.5 || x > maxX + 0.5 { return true }   // bouncing back
        let rtl = scroll.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let back = rtl ? velocityX < 0 : velocityX > 0
        if !back { return true }
        return canScrollHorizontally(scroll, velocityX: velocityX)
    }

    /// Whether a horizontal drag with this velocity can still scroll `scroll`:
    /// a drag to the right needs content to the left of the visible bounds, a
    /// drag to the left content to the right (pure geometry, so it holds for
    /// right-to-left layouts, whose collection views flip the content).
    static func canScrollHorizontally(_ scroll: UIScrollView, velocityX: CGFloat) -> Bool {
        guard scroll.isScrollEnabled else { return false }
        let inset = scroll.adjustedContentInset
        let minX = -inset.left
        let maxX = scroll.contentSize.width + inset.right - scroll.bounds.width
        guard maxX > minX + 1 else { return false }
        if velocityX > 0 { return scroll.contentOffset.x > minX + 0.5 }
        if velocityX < 0 { return scroll.contentOffset.x < maxX - 0.5 }
        return true
    }
}
