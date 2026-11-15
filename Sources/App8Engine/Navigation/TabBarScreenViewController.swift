import UIKit
import Combine

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

    /// Re-resolves tab `badge` expressions when an app variable changes.
    private var badgeSubscription: AnyCancellable?

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
        if #available(iOS 18.0, *) {
            // A DSL tab bar is always the classic bottom bar, also on the iPad
            // idiom (Mac Catalyst hosts) where the default is the floating top
            // bar / sidebar that hides the bottom bar.
            mode = .tabBar
        }
    }

    private func configureTabBarAppearance() {
        if let tintColor = resolveColor(tabBarContent.tintColor) {
            tabBar.tintColor = tintColor
        }

        if let unselectedColor = resolveColor(tabBarContent.unselectedColor) {
            tabBar.unselectedItemTintColor = unselectedColor
        }
    }

    /// A tab bar color field (hex or color expression) resolved against app
    /// variables; a non-hex result leaves the field unset and logs `style.color.invalid`.
    private func resolveColor(_ raw: String?) -> UIColor? {
        guard let raw, !raw.isEmpty else { return nil }
        guard raw.contains("{{") else { return UIColor(withHexString: raw) }
        let variables = VariableContext(store: appService.appVariableStore)
        let value = ((try? PropertyResolver().resolveToString(raw, context: variables)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard DSL.Model.Style.Color.Hex.isValidHexString(value), let color = UIColor(withHexString: value) else {
            context.logger.warning("style.color.invalid: '\(raw)' resolved to '\(value)', not a hex color — field left unset. tabBarScreen")
            return nil
        }
        return color
    }

    /// True when a bar or tab color is an expression (re-applied on app variable changes).
    private var hasColorExpressions: Bool {
        let fields = [tabBarContent.tintColor, tabBarContent.unselectedColor,
                      tabBarContent.badgeColor, tabBarContent.badgeTextColor]
            + tabBarContent.tabs.map(\.badgeColor)
        return fields.contains { $0?.contains("{{") == true }
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

            applyBadgeColors(to: navController.tabBarItem, tab: tab)

            tabNavigationControllers[tab.id] = navController
            tabIds.append(tab.id)
            viewControllers.append(navController)
        }

        self.viewControllers = viewControllers
        bindBadges()

        if let initialTab = tabBarContent.initialTab,
           let index = tabIds.firstIndex(of: initialTab) {
            selectedIndex = index
        }
    }

    // MARK: - Badges

    /// Badge background (`badgeColor`, per tab over the bar's) and text color
    /// (`badgeTextColor`) on the tab's `UITabBarItem`, normal and selected.
    private func applyBadgeColors(to item: UITabBarItem, tab: DSL.Model.Tab) {
        if let color = resolveColor(tab.badgeColor ?? tabBarContent.badgeColor) {
            item.badgeColor = color
        }
        if let color = resolveColor(tabBarContent.badgeTextColor) {
            item.setBadgeTextAttributes([.foregroundColor: color], for: .normal)
            item.setBadgeTextAttributes([.foregroundColor: color], for: .selected)
        }
    }

    private func bindBadges() {
        let colorExpressions = hasColorExpressions
        guard colorExpressions || tabBarContent.tabs.contains(where: { $0.badge != nil }) else { return }
        updateBadges()
        badgeSubscription = appService.appVariableStore.anyVariableChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateBadges()
                if colorExpressions { self?.reapplyColors() }
            }
    }

    /// Re-resolves the bar and badge colors after an app variable change.
    private func reapplyColors() {
        configureTabBarAppearance()
        for tab in tabBarContent.tabs {
            guard let nav = tabNavigationControllers[tab.id] else { continue }
            applyBadgeColors(to: nav.tabBarItem, tab: tab)
        }
    }

    private func updateBadges() {
        let resolver = PropertyResolver()
        let variables = VariableContext(store: appService.appVariableStore)
        for tab in tabBarContent.tabs {
            guard let raw = tab.badge, let nav = tabNavigationControllers[tab.id] else { continue }
            let value = (try? resolver.resolveToString(raw, context: variables)) ?? raw
            let badge = value.isEmpty || value == "0" ? nil : value
            if nav.tabBarItem.badgeValue != badge { nav.tabBarItem.badgeValue = badge }
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

        // Wait for a dismissal the same action list started (see FlowCoordinator).
        let gate = context.pendingDismissal
        Task { @MainActor in
            await gate?.value
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
            // A presented modal handles its own pushes.
            guard presentedViewController == nil, parent?.presentedViewController == nil else { return }
            let screenComponent = try await screenLoader.loadScreen(id: screenId)
            let screenVC = await appService.renderScreen(screenComponent, screenId: screenId, params: params.isEmpty ? nil : params)
            if let transition = request.transition, transition.kind == .nativeZoom {
                NativeZoomTransition.push(screenVC, on: currentNavController, transition: transition, coordinator: nil, logger: context.logger)
            } else {
                currentNavController.pushViewController(screenVC, animated: true)
            }

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
