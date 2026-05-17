import UIKit

/// Controls the user interface style (light/dark) for App8-rendered screens only.
/// Native app UI is unaffected. Set `userInterfaceStyle` to apply the override
/// immediately to every active `ScreenViewController`.
@MainActor
public final class App8Appearance {
    public init() {}

    /// Weak set of all registered ScreenViewControllers.
    private let viewControllers = NSHashTable<UIViewController>.weakObjects()

    public var userInterfaceStyle: UIUserInterfaceStyle = .unspecified {
        didSet {
            guard oldValue != userInterfaceStyle else { return }
            viewControllers.allObjects.forEach {
                $0.overrideUserInterfaceStyle = userInterfaceStyle
            }
        }
    }

    /// Called by ScreenViewController on viewDidLoad to opt into App8Appearance management.
    func register(_ viewController: UIViewController) {
        viewControllers.add(viewController)
        viewController.overrideUserInterfaceStyle = userInterfaceStyle
    }
}
