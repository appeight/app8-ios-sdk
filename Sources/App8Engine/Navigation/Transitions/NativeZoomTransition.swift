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
                    // UIKit asks before the incoming screen's first layout pass:
                    // its gallery cells (the alignment element) do not exist yet,
                    // the provider found nothing, and UIKit zoomed the whole
                    // screen out of the source instead of the matched element
                    // (the new screen just faded in). Lay it out first.
                    if let zoomedView, zoomedView.bounds.width > 0 {
                        zoomedView.setNeedsLayout()
                        zoomedView.layoutIfNeeded()
                    }
                    let key = presentingScreen.flatMap { reevaluate(alignmentExpression, in: $0) }
                    let candidates = [key, initialAlignment, alignmentExpression].compactMap { $0 }
                    for candidate in candidates {
                        if let view = TransitionKeyLocator.view(forKey: candidate, in: zoomedView), let zoomedView {
                            return view.convert(view.bounds, to: zoomedView)
                        }
                    }
                    logger?.warning("transition.zoom.alignmentMissing: no element with key '\(candidates.first ?? alignmentExpression)' on the incoming screen — UIKit zooms the whole screen")
                    return nil
                }
            }
        }

        let sourceExpression = zoom.sourceKeyExpression
        viewController.preferredTransition = .zoom(options: options) { [weak presentingScreen] context in
            MainActor.assumeIsolated {
                guard let presentingScreen else { return nil }
                // Re-evaluated in the presenting screen's scope (dismissal can
                // return to a different element), then the key the action resolved.
                var candidates: [String] = []
                if let key = reevaluate(sourceExpression, in: presentingScreen) { candidates.append(key) }
                candidates.append(initialKey)
                for key in candidates {
                    if let view = TransitionKeyLocator.view(forKey: key, in: presentingScreen.view) {
                        return SourceProxy.source(for: view, in: presentingScreen.view, coordinator: context.zoomedViewController.transitionCoordinator)
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
    /// horizontal pan the innermost horizontal scroller claims, or the
    /// pull-down of a stretchy-top scroll view).
    ///
    /// When the dismiss begins, the horizontal scrollers under the finger stop
    /// tracking this drag, so a pager never rubber-bands while the screen
    /// shrinks: one drag, one owner.
    private static func shouldBeginDismiss(
        gesture: DSL.Model.ScreenTransition.DismissGesture,
        context: UIViewController.Transition.ZoomOptions.InteractionContext,
        zoomedView: UIView?
    ) -> Bool {
        let begins = shouldBeginDismiss(
            gesture: gesture,
            location: context.location,
            velocity: CGPoint(x: context.velocity.dx, y: context.velocity.dy),
            willBegin: context.willBegin,
            zoomedView: zoomedView
        )
        if begins, let zoomedView {
            releaseHorizontalScrollers(at: context.location, in: zoomedView)
        }
        return begins
    }

    /// Cancels the pan of every horizontally scrollable view under `location`
    /// (toggling `isEnabled` cancels a running recognizer and drops the touches
    /// it was tracking), so it cannot scroll or bounce along with the dismiss.
    static func releaseHorizontalScrollers(at location: CGPoint, in root: UIView) {
        guard let hit = root.hitTest(location, with: nil) else { return }
        var view: UIView? = hit
        while let current = view, current !== root.superview {
            if let scroll = current as? UIScrollView, scrollsHorizontally(scroll) {
                let pan = scroll.panGestureRecognizer
                if pan.isEnabled {
                    pan.isEnabled = false
                    pan.isEnabled = true
                }
            }
            view = current.superview
        }
    }

    private static func scrollsHorizontally(_ scroll: UIScrollView) -> Bool {
        guard scroll.isScrollEnabled else { return false }
        let inset = scroll.adjustedContentInset
        return scroll.contentSize.width + inset.right - scroll.bounds.width > -inset.left + 1
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
            guard velocity.y > 0 && abs(velocity.y) > abs(velocity.x) else { return false }
            return !verticalScrollerClaims(location: location, velocityY: velocity.y, in: zoomedView)
        case .any:
            // `willBegin` is UIKit's own default: false while a scroll view under
            // the finger could use the drag. It is not trusted either way (it
            // says false for a back drag over a pager's later page, and true
            // while a pager's pan has already begun): the walk below decides.
            // With nothing under the finger claiming the drag, the dismiss
            // begins even where UIKit would not.
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
                    // A vertical scroller scrolls with a vertical drag; only a
                    // pull down at its top reaches the dismiss (as UIKit's zoom).
                    if !horizontal, claimsVerticalPan(scroll, velocityY: velocity.y) { return false }
                }
                view = current.superview
            }
            return true
        }
    }

    /// Whether a vertical scroller under `location` keeps a vertical drag.
    private static func verticalScrollerClaims(location: CGPoint, velocityY: CGFloat, in root: UIView?) -> Bool {
        guard let root, let hit = root.hitTest(location, with: nil) else { return false }
        var view: UIView? = hit
        while let current = view, current !== root.superview {
            if let scroll = current as? UIScrollView {
                if velocityY > 0, let zooming = scroll as? App8ZoomingScrollView, zooming.claimsPullDown { return true }
                if claimsVerticalPan(scroll, velocityY: velocityY) { return true }
            }
            view = current.superview
        }
        return false
    }

    /// Whether a vertical scroller keeps a vertical drag rather than leaving it
    /// to the dismiss: always while it is moving (decelerating or bouncing
    /// back from an edge), for an upward drag (it scrolls the content
    /// on, or rubber-bands at the end), and for a downward drag while it is
    /// scrolled down. Only a pull down on a scroller resting at its top
    /// (contentOffset at or above the top inset) reaches the dismiss.
    static func claimsVerticalPan(_ scroll: UIScrollView, velocityY: CGFloat) -> Bool {
        guard scroll.isScrollEnabled else { return false }
        let inset = scroll.adjustedContentInset
        let minY = -inset.top
        let maxY = scroll.contentSize.height + inset.bottom - scroll.bounds.height
        guard maxY > minY + 1 else { return false }
        // Not `isDragging`: the scroll view's own pan may already have begun
        // with this very drag (at the top, the pull down must still dismiss).
        if scroll.isDecelerating { return true }
        let y = scroll.contentOffset.y
        if y > maxY + 0.5 { return true }   // bouncing back from the end
        if velocityY < 0 { return true }
        return y > minY + 0.5
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

/// The view UIKit's zoom uses as its source. UIKit hides the source view for
/// the whole transition (and an interactive dismissal): for a card in a grid
/// that leaves the card's slot empty, as the system does. A source that fills
/// (most of) the presenting screen, such as the photo of a full-screen pager
/// page, would leave the screen black behind the shrinking screen; it stays
/// visible instead, and UIKit gets a transparent stand-in at its frame (same
/// corners) to measure and hide.
@MainActor
enum SourceProxy {
    /// Area share of the presenting screen above which the source stays visible.
    static let fillsScreen: CGFloat = 0.8

    private static var proxies: [ObjectIdentifier: UIView] = [:]

    static func source(for view: UIView, in screen: UIView, coordinator: UIViewControllerTransitionCoordinator?) -> UIView {
        guard covers(view, screen), let host = view.superview else { return view }
        let key = ObjectIdentifier(view)
        proxies[key]?.removeFromSuperview()
        let proxy = UIView(frame: view.frame)
        proxy.isUserInteractionEnabled = false
        proxy.backgroundColor = .clear
        proxy.layer.cornerRadius = view.layer.cornerRadius
        proxy.layer.cornerCurve = view.layer.cornerCurve
        proxy.layer.maskedCorners = view.layer.maskedCorners
        proxy.transform = view.transform
        host.insertSubview(proxy, aboveSubview: view)
        proxies[key] = proxy
        coordinator?.animate(alongsideTransition: nil) { _ in
            MainActor.assumeIsolated {
                if proxies[key] === proxy { proxies[key] = nil }
                proxy.removeFromSuperview()
            }
        }
        return proxy
    }

    /// Whether `view`, on screen, covers at least `fillsScreen` of `screen`.
    static func covers(_ view: UIView, _ screen: UIView) -> Bool {
        let area = screen.bounds.width * screen.bounds.height
        guard area > 0 else { return false }
        let frame = view.convert(view.bounds, to: screen).intersection(screen.bounds)
        guard !frame.isNull else { return false }
        return frame.width * frame.height >= area * fillsScreen
    }
}
