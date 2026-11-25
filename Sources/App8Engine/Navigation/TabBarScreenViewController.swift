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

    /// `barStyle`: the engine-drawn bar inside the system one (nil: system items).
    private var styledBar: StyledTabBarView?
    /// Pins the styled bar over the system bar until it moves into the iOS 26 platter.
    private var styledBarConstraints: [NSLayoutConstraint] = []

    override var selectedIndex: Int {
        didSet {
            styledBar?.select(selectedIndex, animated: true)
            syncEdgeStripeToSelectedTab()
            // The lens may rebuild its selection view on a change: paint it again.
            DispatchQueue.main.async { [weak self] in self?.applySelectionIndicator() }
        }
    }

    override var selectedViewController: UIViewController? {
        didSet {
            syncEdgeStripeToSelectedTab()
            guard let styledBar, let vc = selectedViewController,
                  let index = viewControllers?.firstIndex(where: { $0 === vc }) else { return }
            styledBar.select(index, animated: true)
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard selectedIndex < tabIds.count,
              let navController = tabNavigationControllers[tabIds[selectedIndex]] else {
            return false
        }
        return navController.viewControllers.count > 1
    }

    /// Each tab's stack has the engine's transition coordinator (custom
    /// transitions, the shared-element zoom and their interactive pops); this
    /// controller stays the navigation delegate and forwards to it.
    private var tabCoordinators: [ObjectIdentifier: App8NavTransitionCoordinator] = [:]

    func transitionCoordinator(for nav: UINavigationController) -> App8NavTransitionCoordinator {
        if let existing = tabCoordinators[ObjectIdentifier(nav)] { return existing }
        let coordinator = App8NavTransitionCoordinator()
        coordinator.navigationController = nav
        tabCoordinators[ObjectIdentifier(nav)] = coordinator
        return coordinator
    }

    /// The transition methods are answered only while a custom transition is
    /// in play on a tab's stack (`CustomTransitionDelegateGate`): otherwise the
    /// iOS 26 content back swipe works on every pushed screen.
    private var wantsCustomTransitions: Bool {
        tabCoordinators.values.contains { $0.wantsCustomTransitions }
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if CustomTransitionDelegateGate.isTransitionSelector(aSelector) { return wantsCustomTransitions }
        return super.responds(to: aSelector)
    }

    func navigationController(
        _ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from fromVC: UIViewController,
        to toVC: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        transitionCoordinator(for: navigationController)
            .navigationController(navigationController, animationControllerFor: operation, from: fromVC, to: toVC)
    }

    func navigationController(
        _ navigationController: UINavigationController,
        interactionControllerFor animationController: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        transitionCoordinator(for: navigationController)
            .navigationController(navigationController, interactionControllerFor: animationController)
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
        if edgeStripe != nil {
            applyEdgeInsets(in: navigationController)
            slideEdgeStripeAlongTransition(of: navigationController, to: viewController)
            return
        }
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
        return stack[..<(index + 1)].dropFirst().contains { $0.hidesBottomBarWhenPushed || $0.app8HidesTabBar }
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        // The system resets the delegate on navigation — re-apply it.
        navigationController.interactivePopGestureRecognizer?.delegate = self
        navigationController.interactivePopGestureRecognizer?.isEnabled = navigationController.viewControllers.count > 1
        // The coordinator decides the interactive pop (a custom transition's
        // own gestures, else the system one) and refreshes the delegate gate.
        transitionCoordinator(for: navigationController).navigationController(navigationController, didShow: viewController, animated: animated)
        if edgeStripe != nil {
            applyEdgeInsets(in: navigationController)
            if navigationController === selectedViewController, navigationController.transitionCoordinator == nil {
                setEdgeStripe(hidden: Self.hidesTabBar(at: viewController, in: navigationController))
            }
        }

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

    /// The selected tab's top screen decides the status bar style.
    override var childForStatusBarStyle: UIViewController? { selectedViewController }

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
        // Adaptive glass: iOS 26's tab bar glass follows the content behind it;
        // `glassAppearance: light | dark` pins it.
        tabBar.overrideUserInterfaceStyle = (tabBarContent.style?.glassAppearance ?? .auto).interfaceStyle
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

    /// Tabs whose screen has been built (the others hold a placeholder root).
    private var builtTabs: Set<String> = []
    /// In-flight builds, so a tap and the idle prewarm never build a tab twice.
    private var tabBuilds: [String: Task<Void, Never>] = [:]

    /// Badge values for the styled bar, by tab id.
    private var styledBadges: [String: String] = [:]

    /// Set up all tabs — must be called after init to load screens asynchronously.
    /// Only the initial tab's screen is built before the tab bar appears; the
    /// others are built in idle time once it is showing (or at once when the
    /// user picks one first), as `UITabBarController` loads tabs lazily.
    func setupTabs() async throws {
        var viewControllers: [UIViewController] = []

        for tab in tabBarContent.tabs {
            let navController = App8NavigationController()
            navController.setNavigationBarHidden(true, animated: false)
            navController.delegate = self
            navController.interactivePopGestureRecognizer?.isEnabled = true
            navController.interactivePopGestureRecognizer?.delegate = self
            if context.layoutMode.isEnabled {
                navController.view.backgroundColor = .clear
            }
            navController.setViewControllers([TabPlaceholderViewController()], animated: false)

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

        var initialIndex = 0
        if let initialTab = tabBarContent.initialTab,
           let index = tabIds.firstIndex(of: initialTab) {
            initialIndex = index
        }
        if tabBarContent.tabs.indices.contains(initialIndex) {
            let initial = tabBarContent.tabs[initialIndex]
            // Errors here fail the setup, as before.
            try await buildTab(initial)
        }

        self.viewControllers = viewControllers
        installStyledBarIfNeeded(selectedIndex: initialIndex)
        bindBadges()
        selectedIndex = initialIndex
        prewarmTabs()
    }

    /// Builds `tab`'s screen into its navigation controller.
    private func buildTab(_ tab: DSL.Model.Tab) async throws {
        guard !builtTabs.contains(tab.id), let navController = tabNavigationControllers[tab.id] else { return }
        let screenComponent = try await screenLoader.loadScreen(id: tab.screen)
        let screenVC = await appService.renderScreen(screenComponent, screenId: tab.screen, params: nil)
        guard !builtTabs.contains(tab.id) else { return }
        builtTabs.insert(tab.id)
        navController.setViewControllers([screenVC], animated: false)
        // Behind the tab's screens (a zoom shrinks the top one): the root
        // screen's background, not the system white.
        if !context.layoutMode.isEnabled, let color = screenVC.view.backgroundColor { navController.view.backgroundColor = color }
        if edgeStripe != nil { applyEdgeInsets(in: navController) }
    }

    /// Builds the tab with `id` unless it already is (or is being) built.
    func ensureTabBuilt(_ id: String) async {
        guard !builtTabs.contains(id) else { return }
        if let running = tabBuilds[id] { return await running.value }
        guard let tab = tabBarContent.tabs.first(where: { $0.id == id }) else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.buildTab(tab)
            } catch {
                self.context.logger.error("tab.build.failed: '\(id)': \(error)")
            }
            self.tabBuilds[id] = nil
        }
        tabBuilds[id] = task
        await task.value
    }

    /// Builds the other tabs one at a time once the first one is showing,
    /// so switching tabs later is instant.
    private func prewarmTabs() {
        let pending = tabIds.filter { !builtTabs.contains($0) }
        guard !pending.isEmpty else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            for id in pending {
                guard let self else { return }
                await self.ensureTabBuilt(id)
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        applySelectionIndicator()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.applySelectionIndicator() }
    }

    // MARK: - Reselect

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard viewController === selectedViewController else {
            if let id = tabNavigationControllers.first(where: { $0.value === viewController })?.key,
               !builtTabs.contains(id) {
                Task { @MainActor [weak self] in await self?.ensureTabBuilt(id) }
            }
            return true
        }
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
        applySelectionIndicator()
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
            if styledBar != nil {
                styledBadges[tab.id] = badge
                continue
            }
            if nav.tabBarItem.badgeValue != badge { nav.tabBarItem.badgeValue = badge }
        }
        styledBar?.setItems(badges: tabBarContent.tabs.map { styledBadges[$0.id] })
    }

    // MARK: - Styled bar (barStyle)

    /// Blanks the system items and lays the engine-drawn bar over them. The
    /// system bar stays (hidden on push, safe area, slide back on pop).
    private func installStyledBarIfNeeded(selectedIndex: Int) {
        guard let style = tabBarContent.barStyle, style.isCustom, styledBar == nil else { return }
        if style.isEngineDrawn {
            installEdgeStripe(style: style, selectedIndex: selectedIndex)
            return
        }
        for item in tabBar.items ?? [] {
            item.title = nil
            item.image = UIImage()
            item.selectedImage = UIImage()
            item.isEnabled = false
            item.accessibilityElementsHidden = true
        }
        if style.background != "glass" {
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
        }
        let bar = makeStyledBar(style: style, selectedIndex: selectedIndex)
        bar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addSubview(bar)
        let guide = tabBar.safeAreaLayoutGuide
        styledBarConstraints = [
            bar.topAnchor.constraint(equalTo: tabBar.topAnchor),
            bar.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: Self.styledBarInset),
            bar.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -Self.styledBarInset),
        ]
        NSLayoutConstraint.activate(styledBarConstraints)
        tabBar.accessibilityElements = [bar]
        styledBar = bar
    }

    private func makeStyledBar(style: DSL.Model.TabBarContent.BarStyle, selectedIndex: Int) -> StyledTabBarView {
        let items = tabBarContent.tabs.map { StyledTabBarView.Item(id: $0.id, label: $0.label, icon: $0.icon, badge: nil) }
        let background: UIColor? = style.background == "solid" ? .systemBackground : style.background.hasPrefix("#") ? UIColor(withHexString: style.background) : nil
        let bar = StyledTabBarView(
            style: style, items: items, selectedIndex: selectedIndex, service: appService,
            tint: resolveColor(tabBarContent.tintColor) ?? tabBar.tintColor,
            unselected: resolveColor(tabBarContent.unselectedColor) ?? .secondaryLabel,
            indicator: resolveColor(style.indicatorColor),
            badge: resolveColor(tabBarContent.badgeColor), badgeText: resolveColor(tabBarContent.badgeTextColor),
            background: background
        )
        if style.background != "glass", style.background != "solid", !style.background.hasPrefix("#") {
            // A fill / material style id: drawn by a DSL view behind the items.
            bar.backgroundStyleId = style.background
        }
        bar.onSelect = { [weak self] index in
            guard let self, let controllers = self.viewControllers, controllers.indices.contains(index) else { return }
            let target = controllers[index]
            guard self.tabBarController(self, shouldSelect: target) else { return }
            self.selectedIndex = index
        }
        return bar
    }

    // MARK: - Engine-drawn bar (edge stripe, flat floating bar)

    /// The engine-drawn bar (tab-bar-screen.md, "Flat bars"): an `edge`
    /// stripe, or a `floating` bar with a non-glass background. The
    /// system `UITabBar` is hidden for good and the stripe lives in this
    /// controller's view: on iOS 26 the system bar is a floating glass
    /// platter whose frame, height and glass UIKit owns (a styled bar inside
    /// it can only take the platter's shape), and a hidden-then-shown system
    /// bar brings its platter and safe area back. The engine owns the three
    /// things UIKit did for the bar instead:
    /// - its place: full width, flush with the bottom edge, `height` above
    ///   the bottom safe area, its background under the home indicator;
    /// - the safe area: each tab screen gets the stripe's height as
    ///   `tabStripeInset` (bottom safe area = height + device inset), 0 on a
    ///   screen that hides the bar, so its insets never change mid-transition;
    /// - `hidesTabBar`: `hidesBottomBarWhenPushed` is taken over when a screen
    ///   joins a stack (`App8NavigationController.willAddViewController`) and
    ///   the stripe slides out and back alongside the push and the pop
    ///   (scrubbed by an interactive pop, run back when it is cancelled).
    private var edgeStripe: StyledTabBarView? { tabBarContent.barStyle?.isEngineDrawn == true ? styledBar : nil }
    private var edgeStripeHidden = false

    private func installEdgeStripe(style: DSL.Model.TabBarContent.BarStyle, selectedIndex: Int) {
        tabBar.isHidden = true
        let bar = makeStyledBar(style: style, selectedIndex: selectedIndex)
        bar.isEdge = style.isEdge
        bar.drawnCornerRadius = style.drawnCornerRadius
        bar.clipsToBounds = false
        view.addSubview(bar)
        styledBar = bar
        for nav in tabNavigationControllers.values {
            if let nav = nav as? App8NavigationController {
                nav.willAddViewController = { vc in
                    guard vc.hidesBottomBarWhenPushed else { return }
                    vc.app8HidesTabBar = true
                    vc.hidesBottomBarWhenPushed = false
                }
            }
            for vc in nav.viewControllers where vc.hidesBottomBarWhenPushed {
                vc.app8HidesTabBar = true
                vc.hidesBottomBarWhenPushed = false
            }
            applyEdgeInsets(in: nav)
        }
        view.setNeedsLayout()
    }

    private func layoutEdgeStripe() {
        guard let bar = edgeStripe, let style = tabBarContent.barStyle else { return }
        // UIKit shows its bar again on some changes (a new `viewControllers`).
        if !tabBar.isHidden { tabBar.isHidden = true }
        let inset = view.safeAreaInsets.bottom
        let frame = Self.engineBarFrame(edge: style.isEdge, height: style.drawnHeight, in: view.bounds.size, safeAreaBottom: inset, bottomOffset: style.bottomOffset.map { CGFloat($0) }, sideInset: style.sideInset.map { CGFloat($0) })
        let bounds = CGRect(origin: .zero, size: frame.size)
        if bar.bounds != bounds { bar.bounds = bounds }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if bar.center != center { bar.center = center }
        bar.bottomExtension = style.isEdge ? inset : 0
        engineBarInset = Self.engineBarInset(barFrame: frame, viewHeight: view.bounds.height, safeAreaBottom: inset)
        if view.subviews.last !== bar { view.bringSubviewToFront(bar) }
        if edgeStripeHidden, bar.transform == .identity { bar.transform = edgeStripeOffscreen }
        tabNavigationControllers.values.forEach(applyEdgeInsets(in:))
    }

    /// Below the bottom edge: the bar (and a stripe's background under the home indicator).
    private var edgeStripeOffscreen: CGAffineTransform {
        guard let bar = edgeStripe else { return .identity }
        let top = bar.center.y - bar.bounds.height / 2
        return CGAffineTransform(translationX: 0, y: view.bounds.maxY - top + 1)
    }

    /// The bottom safe area the bar adds to a tab screen (bar top to the
    /// device inset), updated on layout.
    private var engineBarInset: CGFloat = 0

    /// iOS 26 system platter, measured (iPhone 17, iOS 26.4): 21 pt from each
    /// side, its bottom edge 21 pt above the screen's bottom edge, i.e. 13 pt
    /// into the 34 pt home-indicator inset. Without a home indicator: 8 pt.
    nonisolated static let floatingSideInset: CGFloat = 21
    nonisolated static let floatingIntoSafeArea: CGFloat = 13
    nonisolated static let floatingMinBottomGap: CGFloat = 8

    /// The engine-drawn bar's frame in a view of `size`: an edge stripe full
    /// width on the bottom safe area; a floating bar inset like the iOS 26
    /// platter. `height` is exact either way.
    nonisolated static func engineBarFrame(edge: Bool, height: CGFloat, in size: CGSize, safeAreaBottom: CGFloat, bottomOffset: CGFloat? = nil, sideInset: CGFloat? = nil) -> CGRect {
        if edge {
            return CGRect(x: 0, y: size.height - safeAreaBottom - height, width: size.width, height: height)
        }
        let gap = bottomOffset.map { max(0, safeAreaBottom + $0) } ?? max(floatingMinBottomGap, safeAreaBottom - floatingIntoSafeArea)
        let side = min(sideInset ?? floatingSideInset, size.width / 2)
        return CGRect(x: side, y: size.height - gap - height,
                      width: max(0, size.width - 2 * side), height: height)
    }

    /// Tab screens' bottom safe area reaches the bar's top edge: what the
    /// bar adds on top of the device inset.
    nonisolated static func engineBarInset(barFrame: CGRect, viewHeight: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        max(0, viewHeight - barFrame.minY - safeAreaBottom)
    }

    /// Each screen of the stack gets the stripe's height in its bottom safe
    /// area unless it hides the bar.
    private func applyEdgeInsets(in nav: UINavigationController) {
        guard let style = tabBarContent.barStyle, style.isEngineDrawn else { return }
        if engineBarInset == 0 {
            let frame = Self.engineBarFrame(edge: style.isEdge, height: style.drawnHeight, in: view.bounds.size, safeAreaBottom: view.safeAreaInsets.bottom, bottomOffset: style.bottomOffset.map { CGFloat($0) }, sideInset: style.sideInset.map { CGFloat($0) })
            engineBarInset = Self.engineBarInset(barFrame: frame, viewHeight: view.bounds.height, safeAreaBottom: view.safeAreaInsets.bottom)
        }
        for vc in nav.viewControllers {
            guard let screen = vc as? ScreenViewController else { continue }
            screen.tabStripeInset = Self.edgeStripeInset(height: engineBarInset, hidesTabBar: Self.hidesTabBar(at: vc, in: nav))
        }
    }

    /// The bottom safe area an edge stripe adds to a tab screen.
    nonisolated static func edgeStripeInset(height: CGFloat, hidesTabBar: Bool) -> CGFloat {
        hidesTabBar ? 0 : height
    }

    private func setEdgeStripe(hidden: Bool) {
        edgeStripeHidden = hidden
        edgeStripe?.transform = hidden ? edgeStripeOffscreen : .identity
    }

    /// The bar's resting state at the end of a transition, with no
    /// animation left on it.
    private func settleEdgeStripe(hidden: Bool) {
        edgeStripe?.layer.removeAllAnimations()
        setEdgeStripe(hidden: hidden)
    }

    private func syncEdgeStripeToSelectedTab() {
        guard edgeStripe != nil, let nav = selectedViewController as? UINavigationController,
              let top = nav.topViewController, nav.transitionCoordinator == nil else { return }
        setEdgeStripe(hidden: Self.hidesTabBar(at: top, in: nav))
    }

    /// The stripe leaves with a push of a `hidesTabBar` screen and comes back
    /// with the pop, alongside the transition (an interactive pop scrubs it).
    private func slideEdgeStripeAlongTransition(of nav: UINavigationController, to viewController: UIViewController) {
        guard nav === selectedViewController else { return }
        let toHidden = Self.hidesTabBar(at: viewController, in: nav)
        guard let coordinator = nav.transitionCoordinator, coordinator.isAnimated,
              let from = coordinator.viewController(forKey: .from), from !== viewController else {
            setEdgeStripe(hidden: toHidden)
            return
        }
        let fromHidden = edgeStripeHidden
        guard fromHidden != toHidden else { return }
        if coordinator.isInteractive {
            // An interactive pop: an alongside animation of a view outside the
            // transition container was left on the bar, paused, after the
            // pop ended (the bar stayed hidden, the app never went idle).
            // The bar slides in once the finger lifts on a completing pop.
            coordinator.notifyWhenInteractionChanges { [weak self] context in
                guard !context.isCancelled else { return }
                UIView.animate(withDuration: context.transitionDuration * (1 - context.percentComplete) + 0.1,
                               delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                    self?.setEdgeStripe(hidden: toHidden)
                }
            }
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                self?.settleEdgeStripe(hidden: context.isCancelled ? fromHidden : toHidden)
            }
            return
        }
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.setEdgeStripe(hidden: toHidden)
        }, completion: { [weak self] context in
            self?.settleEdgeStripe(hidden: context.isCancelled ? fromHidden : toHidden)
        })
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if edgeStripe != nil {
            layoutEdgeStripe()
            return
        }
        adoptGlassPlatter()
        applySelectionIndicator()
    }

    /// iOS 26 draws the bar as a floating glass platter with a "lens" that
    /// marks the selected item. The styled bar takes the platter's frame
    /// (same size and centre as the system items, and the platter's glass
    /// behind it) and the lens is hidden: the styled selection replaces it.
    /// The bar stays a subview of the tab bar, not of the platter, whose
    /// content is drawn monochrome (a red badge came out white). Without a
    /// platter (earlier iOS, or a changed hierarchy) the bar stays pinned
    /// over the system bar.
    private func adoptGlassPlatter() {
        guard let bar = styledBar,
              let platter = tabBar.subviews.first(where: { "\(type(of: $0))".contains("Platter") }) else { return }
        for sub in platter.subviews where "\(type(of: sub))".contains("Lens") && !sub.isHidden {
            sub.isHidden = true
        }
        // The platter's lens drag and the bar's own recognizers would take
        // touches meant for a template bar's items (its system items are
        // blank and disabled): the styled bar handles selection.
        disableSystemBarGestures(in: tabBar, except: bar)
        if !styledBarConstraints.isEmpty {
            NSLayoutConstraint.deactivate(styledBarConstraints)
            styledBarConstraints = []
            bar.translatesAutoresizingMaskIntoConstraints = true
        }
        let frame = platter.convert(platter.bounds, to: tabBar)
        if bar.frame != frame { bar.frame = frame }
    }

    /// `selectionIndicatorColor` (tab-bar-screen.md, "Selection indicator colour") on the
    /// platform bar. iOS 26 draws the selected item's pill as a backdrop layer inside the
    /// glass lens (`_UITabSelectionView`); it is hidden and a capsule in the colour takes
    /// its place, so it moves, stretches and lifts with the lens. Without the key the
    /// capsule is black at 10% on a light bar and white at 10% on a dark one. Earlier iOS
    /// draws no highlight of its own: only an authored colour adds one
    /// (`selectionIndicatorImage`). Styled bars (`barStyle`) keep their own indicator.
    private func applySelectionIndicator() {
        guard styledBar == nil else { return }
        let authored = resolveColor(tabBarContent.selectionIndicatorColor)
        if #available(iOS 26.0, *) {
            guard let selection = Self.findSubview(in: tabBar, named: "TabSelectionView") else { return }
            for layer in selection.layer.sublayers ?? [] where "\(type(of: layer))".contains("Backdrop") && !layer.isHidden {
                layer.isHidden = true
            }
            let fill: UIView
            if let existing = selection.subviews.first(where: { $0 is SelectionIndicatorFillView }) {
                fill = existing
            } else {
                fill = SelectionIndicatorFillView(frame: selection.bounds)
                fill.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                fill.isUserInteractionEnabled = false
                selection.insertSubview(fill, at: 0)
            }
            fill.backgroundColor = authored ?? Self.defaultSelectionIndicatorColor
        } else if let authored, selectionIndicatorImageColor != authored {
            selectionIndicatorImageColor = authored
            let size = CGSize(width: 24, height: 24)
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                authored.setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2), cornerRadius: 10).fill()
            }.resizableImage(withCapInsets: UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
            tabBar.selectionIndicatorImage = image
        }
    }

    private var selectionIndicatorImageColor: UIColor?

    /// Black at 10% on a light bar, white at 10% on a dark one (the bar's trait).
    static let defaultSelectionIndicatorColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.10) : UIColor(white: 0, alpha: 0.10)
    }

    private static func findSubview(in view: UIView, named fragment: String) -> UIView? {
        for sub in view.subviews {
            if "\(type(of: sub))".contains(fragment) { return sub }
            if let hit = findSubview(in: sub, named: fragment) { return hit }
        }
        return nil
    }

    private func disableSystemBarGestures(in view: UIView, except bar: UIView) {
        guard view !== bar else { return }
        for recognizer in view.gestureRecognizers ?? [] where recognizer.isEnabled { recognizer.isEnabled = false }
        for sub in view.subviews { disableSystemBarGestures(in: sub, except: bar) }
    }

    /// Side inset of the styled bar inside the system one (the iOS 26 bar
    /// floats as a capsule inset from the screen edges).
    static var styledBarInset: CGFloat {
        if #available(iOS 26.0, *) { return 20 }
        return 0
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

        // A screen built ahead (context menu preview tap): pushed now, in the
        // preview's commit, so the expansion dissolves straight into it.
        if case .push = request.type, let prepared = request.preparedScreen,
           request.transition?.kind == DSL.Model.ScreenTransition.Resolved.Kind.none,
           context.pendingDismissal == nil, presentedViewController == nil, parent?.presentedViewController == nil,
           selectedIndex < tabIds.count, let nav = tabNavigationControllers[tabIds[selectedIndex]],
           nav.transitionCoordinator == nil {
            UIView.performWithoutAnimation { nav.pushViewController(prepared, animated: false) }
            return
        }
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
                self.context.logger.critical("Navigation error: \(error.localizedDescription)")
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
            let screenVC: UIViewController
            if let prepared = request.preparedScreen {
                screenVC = prepared
            } else {
                let screenComponent = try await screenLoader.loadScreen(id: screenId)
                screenVC = await appService.renderScreen(screenComponent, screenId: screenId, params: params.isEmpty ? nil : params)
            }
            if let transition = request.transition, transition.kind == .nativeZoom {
                NativeZoomTransition.push(screenVC, on: currentNavController, transition: transition,
                                          coordinator: transitionCoordinator(for: currentNavController), logger: context.logger)
            } else if request.transition?.kind == DSL.Model.ScreenTransition.Resolved.Kind.none {
                currentNavController.pushViewController(screenVC, animated: false)
            } else {
                currentNavController.pushViewController(screenVC, animated: true)
            }

        case .pop:
            currentNavController.popViewController(animated: true)

        case .popToRoot:
            currentNavController.popToRootViewController(animated: true)

        case .selectTab(let index, let id):
            var target: Int?
            if let index = index, index >= 0, index < tabIds.count {
                target = index
            } else if let id = id, let index = tabIds.firstIndex(of: id) {
                target = index
            }
            if let target {
                await ensureTabBuilt(tabIds[target])
                selectedIndex = target
            }
            // Tab switch doesn't trigger didShow, so notify explicitly.
            NotificationCenter.default.post(name: .app8ScreenContextChanged, object: nil)

        case .completeFlow, .switchFlow, .presentModal, .dismiss:
            // Handled by FlowCoordinator, not TabBarScreenViewController.
            break
        }
    }
}

/// Root of a tab whose screen is not built yet.
private final class TabPlaceholderViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }
}

/// The capsule that paints `selectionIndicatorColor` inside the iOS 26 tab bar lens.
final class SelectionIndicatorFillView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerCurve = .continuous
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }
}
