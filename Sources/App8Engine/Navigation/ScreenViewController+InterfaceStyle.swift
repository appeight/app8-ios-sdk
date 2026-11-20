import UIKit

// Screen-level `userInterfaceStyle` (light / dark for one screen).
//
// The screen's own view hierarchy follows `overrideUserInterfaceStyle` on the
// screen. The chrome around it does not: the navigation bar (with its glass bar
// buttons, back button and search field) belongs to the navigation controller,
// the status bar is asked of the window's root, and alerts are presented from
// the root. Each of these is pointed at the top screen's style here.

extension ScreenViewController {

    /// The style this screen resolves for: its own, else the app's
    /// (`App8Appearance`, `.unspecified` = inherit).
    func resolvedInterfaceStyle(appStyle: UIUserInterfaceStyle) -> UIUserInterfaceStyle {
        screenUserInterfaceStyle ?? appStyle
    }

    /// `App8Appearance` sets the app's style: a screen with its own keeps it.
    func applyAppInterfaceStyle(_ appStyle: UIUserInterfaceStyle) {
        let style = resolvedInterfaceStyle(appStyle: appStyle)
        if overrideUserInterfaceStyle != style { overrideUserInterfaceStyle = style }
        guard viewIfLoaded?.window != nil, navigationController?.topViewController === self else { return }
        applyInterfaceStyleToChrome()
    }

    /// Points the navigation bar and the status bar at this screen's style.
    /// From `viewWillAppear`: alongside a push or pop (a cancelled interactive
    /// pop puts back the screen that stays on top).
    func applyInterfaceStyleToChrome() {
        guard let navigationController else {
            setNeedsStatusBarAppearanceUpdate()
            return
        }
        let apply = { [weak self, weak navigationController] in
            guard let self, let navigationController else { return }
            let bar = navigationController.navigationBar
            if bar.overrideUserInterfaceStyle != self.overrideUserInterfaceStyle {
                bar.overrideUserInterfaceStyle = self.overrideUserInterfaceStyle
            }
            navigationController.setNeedsStatusBarAppearanceUpdate()
        }
        guard let coordinator = transitionCoordinator, coordinator.isAnimated else {
            apply()
            return
        }
        coordinator.animate(alongsideTransition: { _ in apply() }, completion: { [weak navigationController] context in
            guard context.isCancelled, let navigationController else { return }
            if let top = navigationController.topViewController as? ScreenViewController {
                top.applyInterfaceStyleToChrome()
            } else {
                navigationController.navigationBar.overrideUserInterfaceStyle = .unspecified
                navigationController.setNeedsStatusBarAppearanceUpdate()
            }
        })
    }
}

extension UIViewController {

    /// The App8 screen showing in this controller: the top of a navigation
    /// stack, the selected tab, else the frontmost child that holds one.
    var app8VisibleScreen: ScreenViewController? {
        if let screen = self as? ScreenViewController { return screen }
        if let nav = self as? UINavigationController { return nav.topViewController?.app8VisibleScreen }
        if let tabs = self as? UITabBarController { return tabs.selectedViewController?.app8VisibleScreen }
        for child in children.reversed() {
            if let screen = child.app8VisibleScreen { return screen }
        }
        return nil
    }

    /// Presents `viewController` (an alert, a picker, a browser) in the style of
    /// the screen showing under it when that screen has its own
    /// `userInterfaceStyle`: the engine presents from the window's root, whose
    /// style is the app's.
    func app8PresentInScreenStyle(_ viewController: UIViewController, animated: Bool = true, completion: (() -> Void)? = nil) {
        let screen = app8VisibleScreen ?? presentingViewController?.app8VisibleScreen
        if let style = screen?.screenUserInterfaceStyle, viewController.overrideUserInterfaceStyle == .unspecified {
            viewController.overrideUserInterfaceStyle = style
        }
        present(viewController, animated: animated, completion: completion)
    }
}
