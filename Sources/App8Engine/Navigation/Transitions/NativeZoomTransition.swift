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
    /// the content under the finger cannot use itself (a zoomed scroll view, or
    /// a horizontal pan over a horizontal scroller).
    private static func shouldBeginDismiss(
        gesture: DSL.Model.ScreenTransition.DismissGesture,
        context: UIViewController.Transition.ZoomOptions.InteractionContext,
        zoomedView: UIView?
    ) -> Bool {
        let velocity = CGPoint(x: context.velocity.dx, y: context.velocity.dy)
        switch gesture {
        case .none:
            return false
        case .down:
            return velocity.y > 0 && abs(velocity.y) > abs(velocity.x)
        case .any:
            guard context.willBegin else { return true }
            let horizontal = abs(velocity.x) > abs(velocity.y)
            // A pan from the leading edge always dismisses, even over a pager.
            if let root = zoomedView, horizontal {
                let rtl = root.effectiveUserInterfaceLayoutDirection == .rightToLeft
                // `location` is where the pan is recognized, a few points past
                // its start; allow for that travel.
                let x = context.location.x
                let edge = App8CollectionView.edgeWidth + 24
                if rtl ? (velocity.x < 0 && x > root.bounds.width - edge)
                       : (velocity.x > 0 && x < edge) {
                    return true
                }
            }
            guard let root = zoomedView,
                  let hit = root.hitTest(context.location, with: nil) else { return true }
            var view: UIView? = hit
            while let current = view, current !== root.superview {
                if let scroll = current as? UIScrollView {
                    if scroll.zoomScale > scroll.minimumZoomScale + 0.01 { return false }
                    if horizontal, scroll.contentSize.width > scroll.bounds.width + 1 { return false }
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
}
