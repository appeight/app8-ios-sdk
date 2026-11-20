import UIKit

/// Controls the user interface style (light/dark) for App8-rendered screens only.
/// Native app UI is unaffected. Set `userInterfaceStyle` to apply the override
/// immediately to every active `ScreenViewController`. A screen whose DSL sets
/// its own `userInterfaceStyle` keeps that style.
@MainActor
public final class App8Appearance {
    public init() {}

    /// Weak set of all registered ScreenViewControllers.
    private let viewControllers = NSHashTable<UIViewController>.weakObjects()

    public var userInterfaceStyle: UIUserInterfaceStyle = .unspecified {
        didSet {
            guard oldValue != userInterfaceStyle else { return }
            viewControllers.allObjects.forEach { apply(to: $0) }
        }
    }

    /// Called by ScreenViewController on viewDidLoad to opt into App8Appearance management.
    func register(_ viewController: UIViewController) {
        viewControllers.add(viewController)
        apply(to: viewController)
    }

    /// A screen with its own DSL `userInterfaceStyle` keeps it.
    private func apply(to viewController: UIViewController) {
        if let screen = viewController as? ScreenViewController {
            screen.applyAppInterfaceStyle(userInterfaceStyle)
        } else {
            viewController.overrideUserInterfaceStyle = userInterfaceStyle
        }
    }
}
