import UIKit
import Combine

/// View controller that manages a tab bar with multiple screens, each with its own navigation stack.
@MainActor
final class TabBarScreenViewController: UITabBarController, UIGestureRecognizerDelegate, UINavigationControllerDelegate, UITabBarControllerDelegate {

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
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        slideTabBarInAlongTransition(of: navigationController, to: viewController)
    }

    /// `hidesTabBar` screens use UIKit's `hidesBottomBarWhenPushed` (it also
    /// owns the safe areas), but on iOS 26 a pop no longer slides the bar
    /// back: UIKit unhides it at the very start, so its icons and labels show
    /// at full opacity at once while only the glass fades in, and a cancelled
    /// interactive pop hides it again in one frame. Instead the bar starts
    /// below the bottom edge and slides up alongside the transition: the
    /// coordinator scrubs it with an interactive pop's progress (also a zoom
    /// pop's) and runs it back out when the pop is cancelled.
    private func slideTabBarInAlongTransition(of navigationController: UINavigationController, to viewController: UIViewController) {
        guard let coordinator = navigationController.transitionCoordinator, coordinator.isAnimated,
              let from = coordinator.viewController(forKey: .from),
              !Self.hidesTabBar(at: viewController, in: navigationController),
              from !== viewController, from.hidesBottomBarWhenPushed || Self.hidesTabBar(at: from, in: navigationController)
        else { return }
        let bar = tabBar
        let offscreen = CGAffineTransform(translationX: 0, y: Self.tabBarSlideDistance(bar, in: view))
        bar.transform = offscreen
        coordinator.animate(alongsideTransition: { _ in
            bar.transform = .identity
        }, completion: { context in
            guard context.isCancelled else {
                bar.transform = .identity
                return
            }
            // Cancelled: UIKit hides the bar again once the transition ends;
            // keep it below the edge until then so it never flashes back.
            bar.transform = offscreen
            DispatchQueue.main.async { bar.transform = .identity }
        })
    }

    /// From the bar's resting place to just below the screen's bottom edge
    /// (iOS 26 floats the bar above the home indicator).
    static func tabBarSlideDistance(_ bar: UITabBar, in container: UIView) -> CGFloat {
        let frame = bar.convert(bar.bounds, to: container)
        return max(bar.bounds.height, container.bounds.maxY - frame.minY) + 1
    }

    /// UIKit's rule: the bar is hidden while any screen pushed above the root,
    /// up to and including `viewController`, sets `hidesBottomBarWhenPushed`.
    static func hidesTabBar(at viewController: UIViewController, in navigationController: UINavigationController) -> Bool {
        let stack = navigationController.viewControllers
        guard let index = stack.firstIndex(where: { $0 === viewController }) else { return false }
        return stack[..<(index + 1)].dropFirst().contains { $0.hidesBottomBarWhenPushed }
    }

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
        delegate = self
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

    // MARK: - Reselect

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard viewController === selectedViewController else { return true }
        Self.handleReselect(of: viewController)
        return false
    }

    /// Tapping the selected tab again (iOS convention, like
    /// `UITabBarController` with a `UITableViewController`): a pushed stack
    /// pops to its root; at the root, the screen's main scroll view scrolls
    /// to its top. The DSL list sits several containers deep in the screen,
    /// where UIKit does not look for it, so the engine does it.
    static func handleReselect(of viewController: UIViewController, animated: Bool = true) {
        if let nav = viewController as? UINavigationController {
            if nav.viewControllers.count > 1 {
                nav.popToRootViewController(animated: animated)
                return
            }
            guard let root = nav.topViewController else { return }
            handleReselect(of: root, animated: animated)
            return
        }
        guard viewController.isViewLoaded,
              let scrollView = primaryScrollView(in: viewController.view) else { return }
        scrollToTop(scrollView, animated: animated)
    }

    /// Breadth-first: the outermost visible scroll view that scrolls
    /// vertically (not a sideways shelf, pager or text view).
    static func primaryScrollView(in root: UIView) -> UIScrollView? {
        var queue: [UIView] = [root]
        var index = 0
        while index < queue.count {
            let view = queue[index]
            index += 1
            if view.isHidden || view.alpha < 0.01 { continue }
            if let scrollView = view as? UIScrollView, !(scrollView is UITextView),
               scrollView.isScrollEnabled, !scrollView.isPagingEnabled {
                if let collection = scrollView as? UICollectionView {
                    // A horizontal collection scrolls in orthogonal sections.
                    if collection.alwaysBounceVertical || collection.contentSize.height > collection.bounds.height {
                        return collection
                    }
                } else if scrollView.alwaysBounceVertical
                            || scrollView.contentSize.height > scrollView.bounds.height
                            || scrollView.contentSize.width <= scrollView.bounds.width {
                    return scrollView
                }
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// Animate to the top rest position: below the bars and any large title
    /// (`adjustedContentInset`), not to raw offset 0.
    static func scrollToTop(_ scrollView: UIScrollView, animated: Bool = true) {
        let top = CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top)
        guard abs(scrollView.contentOffset.y - top.y) > 0.5 else { return }
        scrollView.setContentOffset(top, animated: animated)
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
        // Requests run one after another, each once the previous one's
        // transition has ended: an action list like [back toRoot, selectTab]
        // otherwise switches tabs while the pop is still animating, and UIKit
        // drops the switch half way (the new tab's view is never installed and
        // the tab bar stays hidden from the screen that was popped).
        let previous = navigationQueue
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await gate?.value
            guard let self else { return }
            await self.waitForRunningTransition()
            do {
                try await self.handleRequest(request)
            } catch {
                self.context.logger.error("Navigation error: \(error)")
            }
        }
        navigationQueue = task
    }

    /// The last queued navigation request (see `handleNavigationRequest`).
    private var navigationQueue: Task<Void, Never>?

    /// Returns once the selected tab's stack has no push or pop in flight
    /// (also an interactive pop, finished or cancelled).
    private func waitForRunningTransition() async {
        for _ in 0..<10 {
            guard selectedIndex < tabIds.count,
                  let nav = tabNavigationControllers[tabIds[selectedIndex]],
                  let coordinator = nav.transitionCoordinator else { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                var resumed = false
                let resume = {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume()
                }
                if !coordinator.animate(alongsideTransition: nil, completion: { _ in resume() }) {
                    resume()
                }
                // Never hold the queue on a transition that does not end.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { resume() }
            }
            // UIKit tears the transition down right after its completion blocks.
            await Task.yield()
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
