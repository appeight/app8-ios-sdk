//
//  NativeVisibility.swift
//  App8Engine
//
//  Whether a `native` component is actually on screen.
//
//  The engine builds views before they are shown: tab roots render up front,
//  screens load their view to render, snapshots render in an offscreen window,
//  collection cells build views ahead of display. So visibility is never
//  inferred from view creation. It is recomputed from:
//  - the screen view controller lifecycle (true after `viewDidAppear`, false
//    from `viewWillDisappear`), which also covers background tabs and screens
//    lower in a navigation stack;
//  - presentations over the screen (modal, sheet, full-screen cover);
//  - the window (in a window, not hidden) and the app being in the foreground;
//  - `isHidden` on the view or an ancestor, and list cells being displayed.
//

import UIKit

/// Tracks one view's visibility and reports changes, never the same value twice.
@MainActor
final class NativeVisibilityTracker {

    private weak var view: UIView?
    private let onChange: @MainActor (Bool) -> Void
    private(set) var isVisible = false

    init(view: UIView, onChange: @escaping @MainActor (Bool) -> Void) {
        self.view = view
        self.onChange = onChange
        NativeVisibility.register(self)
    }

    /// Recomputes visibility now; calls `onChange` when it changed.
    func evaluate() {
        let visible = view.map(NativeVisibility.isVisible) ?? false
        guard visible != isVisible else { return }
        isVisible = visible
        onChange(visible)
    }

    /// Reports `false` now (the view is about to leave its window).
    func setNotVisible() {
        guard isVisible else { return }
        isVisible = false
        onChange(false)
    }
}

/// The trackers and the signals that move them.
@MainActor
enum NativeVisibility {

    private final class WeakTracker {
        weak var tracker: NativeVisibilityTracker?
        init(_ tracker: NativeVisibilityTracker) { self.tracker = tracker }
    }

    private static var trackers: [WeakTracker] = []
    private static var pendingPass = false
    private static var observersInstalled = false

    /// `false` between the app entering the background and returning to the foreground.
    private(set) static var appInForeground = true

    static func register(_ tracker: NativeVisibilityTracker) {
        installObserversIfNeeded()
        trackers.removeAll { $0.tracker == nil }
        trackers.append(WeakTracker(tracker))
    }

    /// Re-evaluates every tracker right away. Used at transition boundaries,
    /// where "false when a disappear transition starts" must not wait.
    static func evaluateNow() {
        pendingPass = false
        trackers.removeAll { $0.tracker == nil }
        for box in trackers { box.tracker?.evaluate() }
    }

    /// Re-evaluates every tracker on the next main run-loop turn; repeated
    /// calls before then coalesce into one pass.
    static func invalidate() {
        guard !trackers.isEmpty, !pendingPass else { return }
        pendingPass = true
        DispatchQueue.main.async {
            guard pendingPass else { return }
            evaluateNow()
        }
    }

    /// A screen finished disappearing: a dismissed screen uncovers the one
    /// below. UIKit clears `presentedViewController` around this call, so
    /// check now and once more on the next run-loop turn.
    static func screenDidDisappear() {
        evaluateNow()
        invalidate()
    }

    /// Sets the foreground flag (app lifecycle notifications; tests).
    static func setAppInForeground(_ value: Bool) {
        guard appInForeground != value else { return }
        appInForeground = value
        evaluateNow()
    }

    /// Scenes that entered the background and have not returned.
    private static var backgroundScenes = Set<ObjectIdentifier>()

    private static func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true
        let center = NotificationCenter.default
        // Foreground / background only: an inactive app (Control Center, the
        // app switcher, a call banner) is still visible.
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { setAppInForeground(false) }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { setAppInForeground(true) }
        }
        center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main) { note in
            let id = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                if let id { backgroundScenes.insert(id) }
                evaluateNow()
            }
        }
        center.addObserver(forName: UIScene.willEnterForegroundNotification, object: nil, queue: .main) { note in
            let id = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                if let id { backgroundScenes.remove(id) }
                evaluateNow()
            }
        }
        for name in [UIWindow.didBecomeVisibleNotification, UIWindow.didBecomeHiddenNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { invalidate() }
            }
        }
    }

    // MARK: - The rule

    /// Whether `view` is on screen now: in a shown window of a foreground
    /// scene, not hidden, in a displayed list cell, and on the topmost,
    /// uncovered screen of the selected tab.
    static func isVisible(_ view: UIView) -> Bool {
        guard appInForeground, let window = view.window, !window.isHidden else { return false }
        if let scene = window.windowScene, backgroundScenes.contains(ObjectIdentifier(scene)) { return false }
        guard isShownInHierarchy(view) else { return false }
        guard let controller = owningViewController(of: view) else {
            // A view hosted outside any view controller: the window decides.
            return true
        }
        return isOnScreen(controller)
    }

    /// No hidden ancestor, and every list cell on the way is displayed (a
    /// prefetched or reuse-pool cell is in the hierarchy but off screen).
    private static func isShownInHierarchy(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let v = current {
            if v.isHidden { return false }
            if let cell = v as? UICollectionViewCell {
                guard let list = enclosing(UICollectionView.self, of: cell),
                      list.visibleCells.contains(where: { $0 === cell }) else { return false }
            } else if let cell = v as? UITableViewCell {
                guard let list = enclosing(UITableView.self, of: cell),
                      list.visibleCells.contains(where: { $0 === cell }) else { return false }
            }
            current = v.superview
        }
        return true
    }

    private static func enclosing<T: UIView>(_ type: T.Type, of view: UIView) -> T? {
        var current = view.superview
        while let v = current {
            if let match = v as? T { return match }
            current = v.superview
        }
        return nil
    }

    /// Nearest view controller whose view contains `view`.
    static func owningViewController(of view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let r = responder {
            if let controller = r as? UIViewController { return controller }
            responder = r.next
        }
        return nil
    }

    /// The controller's screen has finished appearing, has not started to
    /// disappear, and nothing is presented over it.
    static func isOnScreen(_ controller: UIViewController) -> Bool {
        // Appearance: the engine's screens track it exactly; other
        // controllers count as shown while their view is in a window.
        var screen: ScreenViewController?
        var current: UIViewController? = controller
        while let c = current {
            if let s = c as? ScreenViewController { screen = s; break }
            current = c.parent
        }
        if let screen {
            guard screen.isOnScreen else { return false }
        } else if controller.viewIfLoaded?.window == nil {
            return false
        }
        return !isCovered(screen ?? controller)
    }

    /// Alerts, a search field's own presentation and context-menu previews
    /// don't change visibility.
    private static func isTransientOverlay(_ controller: UIViewController) -> Bool {
        controller is UIAlertController || controller is UISearchController
            || NSStringFromClass(type(of: controller)).contains("ContextMenu")
    }

    /// Something is presented over the controller (or the container it lives
    /// in): any modal — every sheet detent, full screen, form / page sheet, a
    /// custom modal or popup.
    static func isCovered(_ controller: UIViewController) -> Bool {
        var current: UIViewController? = controller
        while let c = current {
            if let presented = c.presentedViewController, !isTransientOverlay(presented) {
                return true
            }
            current = c.parent
        }
        return false
    }
}
