import ObjectiveC
import UIKit

/// The engine's navigation controller. The top screen decides the status bar
/// style (a screen's `userInterfaceStyle`); UIKit's own asks the navigation
/// bar while it is showing.
final class App8NavigationController: UINavigationController {
    override var childForStatusBarStyle: UIViewController? { topViewController }

    /// Called with every screen about to join the stack (push or set), before
    /// UIKit reads it. An edge tab bar takes `hidesBottomBarWhenPushed` over here.
    var willAddViewController: ((UIViewController) -> Void)?

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        willAddViewController?(viewController)
        super.pushViewController(viewController, animated: animated)
    }

    override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
        if let willAddViewController { viewControllers.forEach(willAddViewController) }
        super.setViewControllers(viewControllers, animated: animated)
    }
}

extension UIViewController {
    private static var app8HidesTabBarKey: UInt8 = 0

    /// `hidesTabBar` of a screen whose tab bar the engine hides itself (an
    /// edge stripe): UIKit's `hidesBottomBarWhenPushed` is cleared so UIKit
    /// never shows its own (hidden) bar again or reserves room for it.
    var app8HidesTabBar: Bool {
        get { (objc_getAssociatedObject(self, &Self.app8HidesTabBarKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &Self.app8HidesTabBarKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
