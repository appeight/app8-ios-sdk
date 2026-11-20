import UIKit

/// The engine's navigation controller. The top screen decides the status bar
/// style (a screen's `userInterfaceStyle`); UIKit's own asks the navigation
/// bar while it is showing.
final class App8NavigationController: UINavigationController {
    override var childForStatusBarStyle: UIViewController? { topViewController }
}
