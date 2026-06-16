import UIKit

/// View controller that manages a tab bar with multiple screens, each with its own navigation stack.
@MainActor
final class TabBarScreenViewController: UITabBarController, UIGestureRecognizerDelegate, UINavigationControllerDelegate {

    private let tabBarContent: DSL.Model.TabBarContent
    private let screenLoader: ScreenLoaderProtocol
    private let appService: App8Service
    private let context: App8Context

    /// Navigation controllers for each tab, keyed by tab ID.
    private var tabNavigationControllers: [String: UINavigationController] = [:]

    private var tabIds: [String] = []

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard selectedIndex < tabIds.count,
              let navController = tabNavigationControllers[tabIds[selectedIndex]] else {
            return false
        }
        return navController.viewControllers.count > 1
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return false
    }

    // MARK: - UINavigationControllerDelegate

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        // The system resets the delegate on navigation — re-apply it.
        navigationController.interactivePopGestureRecognizer?.delegate = self
        navigationController.interactivePopGestureRecognizer?.isEnabled = navigationController.viewControllers.count > 1

        NotificationCenter.default.post(name: .app8ScreenContextChanged, object: nil)
    }

    init(tabBarContent: DSL.Model.TabBarContent, screenLoader: ScreenLoaderProtocol, appService: App8Service, context: App8Context) {
        self.tabBarContent = tabBarContent
        self.screenLoader = screenLoader
        self.appService = appService
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if context.layoutMode.isEnabled {
            view.backgroundColor = .clear
        }
        subscribeToNavigationRequests()
        configureTabBarAppearance()
    }

    private func configureTabBarAppearance() {
        if let tintColorHex = tabBarContent.tintColor,
           let tintColor = UIColor(withHexString: tintColorHex) {
            tabBar.tintColor = tintColor
        }

        if let unselectedColorHex = tabBarContent.unselectedColor,
           let unselectedColor = UIColor(withHexString: unselectedColorHex) {
            tabBar.unselectedItemTintColor = unselectedColor
        }
    }

    /// Set up all tabs — must be called after init to load screens asynchronously.
    func setupTabs() async throws {
        var viewControllers: [UIViewController] = []

        for tab in tabBarContent.tabs {
            let navController = UINavigationController()
            navController.setNavigationBarHidden(true, animated: false)
            navController.delegate = self
            navController.interactivePopGestureRecognizer?.isEnabled = true
            navController.interactivePopGestureRecognizer?.delegate = self
            if context.layoutMode.isEnabled {
                navController.view.backgroundColor = .clear
            }

            let screenComponent = try await screenLoader.loadScreen(id: tab.screen)
            let screenVC = await appService.renderScreen(screenComponent, screenId: tab.screen, params: nil)
            navController.setViewControllers([screenVC], animated: false)

            navController.tabBarItem = UITabBarItem(
                title: tab.label,
                image: UIImage(systemName: tab.icon),
                selectedImage: UIImage(systemName: "\(tab.icon).fill")
            )

            tabNavigationControllers[tab.id] = navController
            tabIds.append(tab.id)
            viewControllers.append(navController)
        }

        self.viewControllers = viewControllers

        if let initialTab = tabBarContent.initialTab,
           let index = tabIds.firstIndex(of: initialTab) {
            selectedIndex = index
        }
    }

    // MARK: - Navigation Handling

    private func subscribeToNavigationRequests() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNavigationRequest(_:)),
            name: .app8NavigationRequest,
            object: nil
        )
    }

    @objc private func handleNavigationRequest(_ notification: Notification) {
        guard let request = notification.object as? NavigationRequest else { return }

        Task { @MainActor in
            do {
                try await handleRequest(request)
            } catch {
                context.logger.error("Navigation error: \(error)")
            }
        }
    }

    private func handleRequest(_ request: NavigationRequest) async throws {
        guard selectedIndex < tabIds.count,
              let currentNavController = tabNavigationControllers[tabIds[selectedIndex]] else {
            return
        }

        switch request.type {
        case .push(let screenId, let params):
            let screenComponent = try await screenLoader.loadScreen(id: screenId)
            let screenVC = await appService.renderScreen(screenComponent, screenId: screenId, params: params.isEmpty ? nil : params)
            currentNavController.pushViewController(screenVC, animated: true)

        case .pop:
            currentNavController.popViewController(animated: true)

        case .popToRoot:
            currentNavController.popToRootViewController(animated: true)

        case .selectTab(let index, let id):
            if let index = index, index >= 0, index < tabIds.count {
                selectedIndex = index
            } else if let id = id, let index = tabIds.firstIndex(of: id) {
                selectedIndex = index
            }
            // Tab switch doesn't trigger didShow, so notify explicitly.
            NotificationCenter.default.post(name: .app8ScreenContextChanged, object: nil)

        case .completeFlow, .switchFlow, .presentModal, .dismiss:
            // Handled by FlowCoordinator, not TabBarScreenViewController.
            break
        }
    }
}
