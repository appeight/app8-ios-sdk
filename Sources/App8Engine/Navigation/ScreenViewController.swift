import UIKit
import Combine

/// View controller for rendered screens with optional navigation bar configuration.
@MainActor
final class ScreenViewController: BaseViewController {

    let screenId: String?
    var screenTitle: String? { navigationBarConfig?.title }

    private let navigationBarConfig: DSL.Model.NavigationBar?
    private let dismissKeyboardOnTap: Bool

    /// Whether the interactive swipe-back (edge-pan pop) gesture is allowed while
    /// this screen is on top. Read by `App8NavTransitionCoordinator` in `didShow`.
    /// `false` makes the screen non-dismissable by swipe (DSL `swipeBackEnabled: false`).
    let allowsSwipeBack: Bool
    /// DSL `userInterfaceStyle`: this screen's own light/dark, over the app's.
    /// `nil` follows the app (`App8Appearance`, then the app default, then the system).
    let screenUserInterfaceStyle: UIUserInterfaceStyle?
    private let additionalSafeAreaInsetsConfig: UIEdgeInsets?
    private weak var titleViewService: App8Service?
    private var titleViewVariableStore: VariableStoreProtocol?
    /// The screen root's variable scope (native zoom re-evaluates `sourceKey` here).
    var screenVariableStore: VariableStoreProtocol? { titleViewVariableStore }
    /// Rendered left-aligned titleView, attached directly to the nav bar in viewWillAppear
    /// to avoid UIBarButtonItem's automatic pill/capsule decoration.
    private var leftNavTitleView: UIView?
    /// Runs DSL actions in the screen's scope (navigation-bar search `onSubmit`).
    private let actionHandler: ((DSL.Model.Action) -> Void)?
    /// `navigationBar.search` field; delegate callbacks sync `bindVariable`.
    private var searchController: UISearchController?
    /// Width of a `fillsBar` search field; tracks the bar width and focus.
    private var searchWidthConstraint: NSLayoutConstraint?
    /// Writes to `search.bindVariable` from elsewhere (a recent search tapped) reach the field.
    private var searchTextSubscription: AnyCancellable?
    /// Re-resolves an expression `navigationBar.title` when its variables change.
    private var titleSubscription: AnyCancellable?
    /// Re-resolve expression bar items (`icon`, `label`, `color`) when their variables change.
    private var barItemSubscriptions: [AnyCancellable] = []
    /// `search.autoFocus` runs on the first appearance only: coming back from a
    /// result keeps the results without raising the keyboard again.
    private var didAutoFocusSearch = false
    /// The ✕ was tapped: `onCancel` runs once the field has finished unfocusing.
    private var pendingSearchCancel = false
    private var lastSearchTap: CFTimeInterval = 0
    /// The field's focus as the search controller last announced it.
    private var searchFieldFocused = false

    /// Holds the current rendered component view — a stable swap target for
    /// streaming structural updates.
    let rootContainerView = UIView()

    /// Shared-element transition participants on this screen, keyed by matching
    /// key. Snapshotted by `App8Service.renderScreen` after the screen renders;
    /// read by `SharedElementTransitionAnimator` to morph matched elements.
    var transitionParticipants: [String: TransitionParticipant] = [:]

    /// `bottomBar` content pinned to the bottom of the screen (see `ScreenBottomBar`).
    var bottomBar: ScreenBottomBar?
    /// Active streaming session (non-nil for screens with streaming: true).
    private var streamingSession: StreamingSession?

    /// Wall-clock of the most-recent `viewDidAppear`. Paired with
    /// `viewDidDisappear` to compute `dwell_ms` for `app8.screen.dismissed`.
    private var appearedAt: Date?

    /// From `viewDidAppear` until `viewWillDisappear`; never for offscreen
    /// (snapshot) renders. Drives `native` visibility (see `NativeVisibility`).
    private(set) var isOnScreen = false
    var rendersOffscreen = false

    override var hasNavigationBar: Bool {
        guard let config = navigationBarConfig else { return false }
        return config.hidden != true
    }

    /// A screen with its own `userInterfaceStyle` picks the status bar's
    /// content colour; the engine's containers forward to the top screen
    /// (`childForStatusBarStyle`).
    override var preferredStatusBarStyle: UIStatusBarStyle {
        switch screenUserInterfaceStyle {
        case .dark: return .lightContent
        case .light: return .darkContent
        default: return super.preferredStatusBarStyle
        }
    }

    override func baseAdditionalBottomInset() -> CGFloat {
        (additionalSafeAreaInsetsConfig?.bottom ?? 0) + (bottomBar?.safeAreaContribution ?? 0)
    }

    // MARK: - Init

    init(
        screenId: String? = nil,
        navigationBar: DSL.Model.NavigationBar?,
        hidesTabBar: Bool = false,
        swipeBackEnabled: Bool = true,
        userInterfaceStyle: UIUserInterfaceStyle? = nil,
        dismissKeyboardOnTap: Bool = true,
        additionalSafeAreaInsets: UIEdgeInsets? = nil,
        titleViewService: App8Service? = nil,
        titleViewVariableStore: VariableStoreProtocol? = nil,
        actionHandler: ((DSL.Model.Action) -> Void)? = nil,
        context: App8Context
    ) {
        self.screenId = screenId
        self.navigationBarConfig = navigationBar
        self.allowsSwipeBack = swipeBackEnabled
        self.screenUserInterfaceStyle = userInterfaceStyle
        self.dismissKeyboardOnTap = dismissKeyboardOnTap
        self.additionalSafeAreaInsetsConfig = additionalSafeAreaInsets
        self.titleViewService = titleViewService
        self.titleViewVariableStore = titleViewVariableStore
        self.actionHandler = actionHandler
        super.init(context: context)
        self.hidesBottomBarWhenPushed = hidesTabBar
        if let userInterfaceStyle { overrideUserInterfaceStyle = userInterfaceStyle }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `navigationBar.largeTitle` with a plain `title` to show large.
    private var usesLargeTitle: Bool {
        guard let config = navigationBarConfig, config.hidden != true, config.largeTitle == true else { return false }
        return config.titleView == nil && config.title != nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        context.appearance.register(self)
        setupRootContainer()
        // Every screen states its mode: a tab's navigation controller turns
        // `prefersLargeTitles` on for its large-title root, and a pushed
        // screen must not inherit it (`.automatic` would).
        navigationItem.largeTitleDisplayMode = usesLargeTitle ? .always : .never
        configureNavigationBar()
        configureKeyboardDismissal()
        if let insets = additionalSafeAreaInsetsConfig {
            // Apply top/left/right only — bottom is owned by baseAdditionalBottomInset()
            // and will be set by BaseViewController's keyboard binding on the next run loop.
            additionalSafeAreaInsets = UIEdgeInsets(top: insets.top, left: insets.left, bottom: 0, right: insets.right)
        }
    }

    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        // `navigationController` is not set yet; the parent is.
        if usesLargeTitle, let nav = parent as? UINavigationController, !nav.navigationBar.prefersLargeTitles {
            nav.navigationBar.prefersLargeTitles = true
        }
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        enableLargeTitlesIfNeeded()
    }

    /// Large titles are a navigation-bar switch (`prefersLargeTitles`); each
    /// screen then picks its own `largeTitleDisplayMode`. Set as soon as the
    /// screen joins its navigation controller, before it is first shown.
    private func enableLargeTitlesIfNeeded() {
        guard usesLargeTitle, let bar = navigationController?.navigationBar, !bar.prefersLargeTitles else { return }
        bar.prefersLargeTitles = true
    }

    override func viewWillAppear(_ animated: Bool) {
        enableLargeTitlesIfNeeded()
        super.viewWillAppear(animated)
        attachLeftTitleViewIfNeeded()
        updateCustomBackItem()
        installSearchFillIfNeeded()
        applySearchFillTopGap()
        navigationController?.navigationBar.tintColor = resolveColor(navigationBarConfig?.tintColor)
        applyInterfaceStyleToChrome()
        pulseClock()
        NativeVisibility.evaluateNow() // a presented screen covers the one below now
    }

    /// `now()` / `today()` re-evaluate when the screen appears.
    private func pulseClock() {
        var store: VariableStoreProtocol? = titleViewVariableStore
        while let parent = store?.getParentStore() { store = parent }
        (store as? VariableStore)?.pulseClock()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isOnScreen = !rendersOffscreen
        NativeVisibility.evaluateNow()
        autoFocusSearchIfNeeded()
        guard context.analyticsConfig.autoScreenEvents else {
            appearedAt = nil
            return
        }
        let now = Date()
        appearedAt = now
        var properties: [String: Any] = [:]
        if let title = navigationBarConfig?.title { properties["title"] = title }
        context.analyticsBus.dispatch(App8AnalyticsEvent(
            name: App8AnalyticsEvent.Auto.screenAppeared,
            screenId: screenId,
            componentId: nil,
            componentType: DSL.Model.Component.CType.Key.screen.rawValue,
            locale: context.translationStore.activeLocale,
            properties: properties,
            timestamp: now
        ))
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isOnScreen = false
        NativeVisibility.evaluateNow()
        leftNavTitleView?.removeFromSuperview()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NativeVisibility.screenDidDisappear() // uncovers the screen below
        guard context.analyticsConfig.autoScreenEvents, let appeared = appearedAt else {
            appearedAt = nil
            return
        }
        let now = Date()
        appearedAt = nil
        let dwellMs = Int(now.timeIntervalSince(appeared) * 1000)
        let properties: [String: Any] = ["dwell_ms": dwellMs]
        context.analyticsBus.dispatch(App8AnalyticsEvent(
            name: App8AnalyticsEvent.Auto.screenDismissed,
            screenId: screenId,
            componentId: nil,
            componentType: DSL.Model.Component.CType.Key.screen.rawValue,
            locale: context.translationStore.activeLocale,
            properties: properties,
            timestamp: now
        ))
    }

    private func setupRootContainer() {
        view.addSubview(rootContainerView)
        rootContainerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rootContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            rootContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rootContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    /// Starts a StreamingSession for this screen after initial render.
    /// Called by App8Service when the screen component has `streaming: true`.
    func startStreaming(
        screenId: String,
        store: ScopedVariableStore,
        component: DSL.Model.Component.`Any`,
        currentView: UIView,
        dataSource: A8.DataSourceProtocol,
        service: App8Service
    ) {
        guard streamingSession == nil else { return }
        let updater = ScreenUpdater(container: rootContainerView, initialView: currentView, service: service, context: context, requestedScreenId: screenId)
        streamingSession = StreamingSession(
            screenId: screenId,
            component: component,
            variableStore: store,
            dataSource: dataSource,
            updater: updater,
            styleResolver: service.styleResolver,
            styleUpdater: { [weak service] data in service?.applyStyleUpdate(data) },
            context: context
        )
        streamingSession?.start()
    }

    private func configureKeyboardDismissal() {
        if dismissKeyboardOnTap {
            context.keyboardService.addViewForDismissTap(view)
        }
    }

    /// Attaches the left-aligned titleView directly to the nav bar, bypassing
    /// UIBarButtonItem to avoid its automatic pill decoration.
    private func attachLeftTitleViewIfNeeded() {
        guard let titleView = leftNavTitleView,
              let navBar = navigationController?.navigationBar,
              titleView.superview == nil else { return }
        navBar.addSubview(titleView)
        titleView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleView.leadingAnchor.constraint(equalTo: navBar.layoutMarginsGuide.leadingAnchor),
            titleView.centerYAnchor.constraint(equalTo: navBar.centerYAnchor)
        ])
    }

    // MARK: - Navigation Bar Configuration

    private func configureNavigationBar() {
        guard let config = navigationBarConfig, config.hidden != true else {
            return
        }

        // Title: custom DSL component or plain string.
        if let titleComponent = config.titleView, let service = titleViewService {
            let container = UIView()
            service.renderComponent(
                titleComponent,
                superview: container,
                parentPath: "navigationBar.titleView",
                parentVariableStore: titleViewVariableStore,
                reuseViewModel: nil
            )
            // Size the container to its content so UIBarButtonItem / titleView renders correctly.
            let size = container.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            container.frame = CGRect(origin: .zero, size: size)

            if config.titleAlignment == "left" {
                // Store for direct nav bar attachment in viewWillAppear.
                // We bypass UIBarButtonItem entirely to avoid the automatic
                // pill/capsule decoration UIKit applies to all customView items.
                navigationItem.hidesBackButton = true
                leftNavTitleView = container
            } else {
                navigationItem.titleView = container
            }
        } else if let rawTitle = config.title {
            if let store = titleViewVariableStore, rawTitle.contains("{{") {
                let resolve: () -> String = { [weak store] in
                    guard let store else { return rawTitle }
                    return (try? PropertyResolver().resolveToString(rawTitle, context: VariableContext(store: store))) ?? rawTitle
                }
                title = resolve()
                // The title is an expression like any text: it follows its variables.
                let names = ExpressionDependencies.names(in: [rawTitle])
                titleSubscription = store.anyVariableChanged
                    .filter { names?.contains($0) ?? true }
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        guard let self else { return }
                        let text = resolve()
                        guard self.title != text else { return }
                        self.title = text
                        if let label = self.navigationItem.titleView as? UILabel {
                            label.text = text
                            label.sizeToFit()
                        }
                    }
            } else {
                title = rawTitle
            }
            // A titleView would replace the large title; large titles keep the label color.
            if !usesLargeTitle, let color = resolveColor(config.titleColor) {
                let titleLabel = UILabel()
                titleLabel.text = title
                titleLabel.textColor = color
                titleLabel.font = UIFont.boldSystemFont(ofSize: 17)
                titleLabel.sizeToFit()
                navigationItem.titleView = titleLabel
            }
        }

        // Custom back label (only when no titleView and no leftAction).
        if config.titleView == nil, let backLabel = config.backLabel, config.leftAction == nil {
            navigationItem.hidesBackButton = true
            var cfg = UIButton.Configuration.plain()
            cfg.image = UIImage(systemName: "chevron.left")
            cfg.title = backLabel
            cfg.imagePadding = 4
            let btn = UIButton(configuration: cfg)
            btn.addTarget(self, action: #selector(customBackTapped), for: .touchUpInside)
            customBackItem = UIBarButtonItem(customView: btn)
            updateCustomBackItem()
        }

        // Left action (skipped when titleView is left-aligned — it already occupies leftBarButtonItem).
        if config.titleAlignment != "left" || config.titleView == nil {
            if let leftAction = config.leftAction {
                navigationItem.leftBarButtonItem = makeBarButton(from: leftAction)
            }
        }

        // Right actions — array takes priority over singular rightAction (backward compat).
        // rightBarButtonItems (plural) lets iOS 26 Liquid Glass group image buttons into
        // shared glass backgrounds. UIKit displays them in REVERSE order, so reverse to
        // preserve declaration order.
        let rightActions = config.rightActions ?? config.rightAction.map { [$0] } ?? []
        if !rightActions.isEmpty {
            navigationItem.rightBarButtonItems = rightActions.reversed().map { makeBarButton(from: $0) }
        }

        if let search = config.search {
            configureSearch(search)
        }

        if config.hidesBackButton == true {
            navigationItem.hidesBackButton = true
        }
    }

    // MARK: - Navigation Bar Search

    private func configureSearch(_ config: DSL.Model.SearchBar) {
        let controller = UISearchController(searchResultsController: nil)
        controller.obscuresBackgroundDuringPresentation = false
        controller.searchResultsUpdater = self
        controller.searchBar.delegate = self
        controller.delegate = self
        if let placeholder = config.placeholder {
            controller.searchBar.placeholder = resolveString(placeholder)
        }
        if let color = resolveColor(config.tintColor) {
            controller.searchBar.tintColor = color
        }
        if let name = config.bindVariable,
           let text = titleViewVariableStore?.getValue(name: name) as? String {
            controller.searchBar.text = text
        }

        if let name = config.bindVariable, let store = titleViewVariableStore {
            searchTextSubscription = store.anyVariableChanged
                .filter { $0 == name }
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak store] _ in
                    guard let bar = self?.searchController?.searchBar else { return }
                    let text = store?.getValue(name: name) as? String ?? ""
                    if bar.text != text { bar.text = text }
                }
        }

        navigationItem.searchController = controller
        navigationItem.hidesSearchBarWhenScrolling = config.hidesWhenScrolling ?? false
        navigationItem.preferredSearchBarPlacement = searchBarPlacement(config.placement ?? .automatic)
        definesPresentationContext = true
        searchController = controller

    }

    /// `navigationBar.search.autoFocus`: a search screen opens with its field
    /// focused and the keyboard up, once the push has landed (activating the
    /// search controller mid-transition would animate its own presentation
    /// against the push).
    private func autoFocusSearchIfNeeded() {
        guard !didAutoFocusSearch, navigationBarConfig?.search?.autoFocus == true,
              navigationBarConfig?.search?.isButton != true, let controller = searchController else { return }
        didAutoFocusSearch = true
        focusSearch(controller, attemptsLeft: 3)
    }

    /// Activates the search controller and raises the keyboard; tries again a
    /// little later while the screen is still settling (a device can still
    /// be finishing the push, or another field giving up first responder).
    private func focusSearch(_ controller: UISearchController, attemptsLeft: Int) {
        guard view.window != nil, navigationController?.topViewController === self else { return }
        if !controller.isActive { controller.isActive = true }
        DispatchQueue.main.async { [weak self] in
            let field = controller.searchBar.searchTextField
            if !field.isFirstResponder { field.becomeFirstResponder() }
            guard !field.isFirstResponder, attemptsLeft > 1 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self?.focusSearch(controller, attemptsLeft: attemptsLeft - 1)
            }
        }
    }

    /// `navigationBar.search.fillsBar`: an integrated field is compact and
    /// trailing; placed as the leading item with an explicit width it spans the
    /// bar. Runs from `viewWillAppear`, not `viewDidLoad`: the view loads inside
    /// the engine's async render, and the bar re-layout this triggers can spin
    /// the run loop while that task is current.
    private func installSearchFillIfNeeded() {
        guard #available(iOS 26.0, *), searchWidthConstraint == nil,
              let config = navigationBarConfig?.search, config.fillsBar == true,
              config.placement == .integrated, let controller = searchController,
              navigationItem.leftBarButtonItem == nil else { return }
        controller.delegate = self
        // Never move `searchBarPlacementBarButtonItem` into the navigation bar's
        // left items: UIKit raises NSInvalidArgumentException ("only supported
        // in UIToolbar") — observed on iPhone with iOS 26.2 — which crashed any
        // screen using `fillsBar` (the list screens of a tab app). The field
        // stays in its integrated (trailing) slot and is widened in place.
        let width = controller.searchBar.widthAnchor.constraint(equalToConstant: 0)
        width.isActive = true
        searchWidthConstraint = width
        updateSearchWidth()
    }

    /// A `fillsBar` screen's bar sits this far below the status bar, so the
    /// field floats free of it. The bar is 10pt taller than the field, so the
    /// content starts at safe area + 10 + field + 10.
    private static let searchFillTopGap: CGFloat = 10

    private var usesSearchFill: Bool {
        guard #available(iOS 26.0, *), let config = navigationBarConfig?.search else { return false }
        return config.fillsBar == true && config.placement == .integrated && navigationBarConfig?.hidden != true
    }

    /// The gap moves the navigation bar, which every screen in the stack
    /// shares, so it belongs to the stack, not to the screen on top: the root
    /// screen decides it and screens pushed over it keep it. UIKit freezes the
    /// bar's frame for the length of a push/pop (an alongside change of the
    /// navigation controller's safe area only lands at completion), so a
    /// per-screen gap made the bar jump 10pt right after every transition
    /// between a `fillsBar` screen and one without it.
    private func applySearchFillTopGap() {
        guard let nav = navigationController else { return }
        let root = nav.viewControllers.first as? ScreenViewController
        let top = root?.usesSearchFill == true ? Self.searchFillTopGap : 0
        guard nav.additionalSafeAreaInsets.top != top else { return }
        nav.additionalSafeAreaInsets.top = top
    }

    /// iPhone: the field is trailing-aligned at the bar's margin and UIKit
    /// keeps it only while it fits between both margins; one point wider and
    /// it collapses into a search button. The margin is 16pt on iOS 26.0 and
    /// 20pt (24pt on 414pt+ wide phones) on iOS 26.4, so the field is sized
    /// for the wider one first; once the field is on screen its measured
    /// trailing gap replaces the guess, so it is centred on both. Before, it
    /// was sized for 16pt and collapsed into a button on iOS 26.4.
    /// Focused, the field makes room for the ✕. Elsewhere (iPad idiom, e.g.
    /// Mac Catalyst previews) the field stays a trailing item, spans to the
    /// bar's margins, and has no outside ✕.
    private func searchFillInset(barWidth: CGFloat) -> CGFloat {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return Self.searchFillPadInset }
        return 2 * (measuredSearchMargin ?? (barWidth >= 414 ? 24 : 20))
    }

    /// The bar's trailing gap beside the unfocused field, measured once it is
    /// on screen (the field is trailing-aligned, so the gap does not depend on
    /// its width). A system metric, so shared: a search screen that focuses
    /// before it was ever laid out unfocused uses the gap the first screen
    /// measured, and the two fields line up.
    private static var measuredSearchMargin: CGFloat?
    private var measuredSearchMargin: CGFloat? {
        get { Self.measuredSearchMargin }
        set { Self.measuredSearchMargin = newValue }
    }

    private func measureSearchMarginIfNeeded() {
        guard measuredSearchMargin == nil, !searchFieldFocused, searchWidthConstraint != nil,
              let bar = navigationController?.navigationBar,
              let field = searchController?.searchBar.searchTextField, field.window != nil,
              field.bounds.width > 100 else { return }
        let gap = bar.bounds.width - field.convert(field.bounds, to: bar).maxX
        guard (8...32).contains(gap) else { return }
        measuredSearchMargin = gap
        searchWidthKey = nil
    }
    private static var searchFillFocusedInset: CGFloat {
        UIDevice.current.userInterfaceIdiom == .phone ? 72 : Self.searchFillPadInset
    }
    /// Widest the iPad-idiom bar keeps the field (measured in Stage, Catalyst).
    private static let searchFillPadInset: CGFloat = 28

    /// Bar width + focus the field was last sized for. Layout passes re-enter
    /// `viewDidLayoutSubviews`; only a real change may touch the constraint.
    private var searchWidthKey: (CGFloat, Bool)?

    private func updateSearchWidth(focused override: Bool? = nil) {
        guard let constraint = searchWidthConstraint,
              let bar = navigationController?.navigationBar, bar.bounds.width > 0 else { return }
        let focused = override ?? searchFieldFocused
        if let key = searchWidthKey, key.0 == bar.bounds.width, key.1 == focused { return }
        searchWidthKey = (bar.bounds.width, focused)
        // Unfocused, the field shares the bar with the trailing items; sized
        // as if it had the bar to itself it overflowed it, and the bar laid the
        // row out past the leading edge (the field, or the item beside it,
        // clipped by the screen edge). Focused, UIKit swaps the items for the ✕.
        // Never wider focused than unfocused: the trailing items come back
        // while the field unfocuses, and a field still too wide for them makes
        // UIKit collapse it into a search button for good.
        let resting = searchFillInset(barWidth: bar.bounds.width) + trailingItemsReserve + leadingBackReserve
        let inset = focused ? max(Self.searchFillFocusedInset, resting) : resting
        constraint.constant = max(0, bar.bounds.width - inset)
    }

    /// Room the trailing bar items take beside an unfocused `fillsBar` field:
    /// image items share one 44pt glass capsule (54pt between centres), text
    /// and prominent items get their own, 8pt apart, plus 8pt before the field.
    /// A pushed screen's back button sits before the field: the 44pt glass
    /// circle and 8pt (plus 8pt of slack, see `trailingItemsReserve`).
    private var leadingBackReserve: CGFloat {
        guard let nav = navigationController, nav.viewControllers.first !== self,
              !navigationItem.hidesBackButton, navigationItem.leftBarButtonItems?.isEmpty ?? true else { return 0 }
        return 44 + 16
    }

    private var trailingItemsReserve: CGFloat {
        let items = navigationItem.rightBarButtonItems ?? []
        guard !items.isEmpty else { return 0 }
        var width: CGFloat = 0
        var run = 0
        func add(_ w: CGFloat) { width += (width > 0 ? 8 : 0) + w }
        func flush() {
            if run > 0 { add(run > 1 ? 2 * 23.33 + CGFloat(run - 1) * 54 : 44) }
            run = 0
        }
        for item in items.reversed() {
            let prominent: Bool
            if #available(iOS 26.0, *) { prominent = item.style == .prominent } else { prominent = item.style == .done }
            if item.image != nil && !prominent {
                run += 1
            } else {
                flush()
                let title = (item.title ?? "") as NSString
                let text = ceil(title.size(withAttributes: [.font: UIFont.systemFont(ofSize: 17)]).width)
                add(item.image != nil ? 44 : max(44, text + 28))
            }
        }
        flush()
        // 8pt before the field, plus 8pt of slack: sized to the point, the
        // row sits on UIKit's collapse threshold.
        return width + 16
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        measureSearchMarginIfNeeded()
        updateSearchWidth()
        applyTopEdgeEffect()
        attachLargeTitleScrollViewIfNeeded()
        bottomBar?.layoutPass(content: rootContainerView)
    }

    /// The large title collapses as the screen's main scroll view scrolls.
    /// UIKit only finds it by itself near the top of the view hierarchy; a
    /// DSL list sits several containers deep, so name it explicitly.
    private func attachLargeTitleScrollViewIfNeeded() {
        guard usesLargeTitle || tracksScrollEdgeForBar, contentScrollView(for: .top) == nil,
              let scrollView = Self.firstVerticalScrollView(in: rootContainerView) else { return }
        setContentScrollView(scrollView, for: .top)
    }

    /// Breadth-first: the outermost scroll view that scrolls vertically.
    static func firstVerticalScrollView(in root: UIView) -> UIScrollView? {
        var queue: [UIView] = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let scrollView = view as? UIScrollView, !(scrollView is UITextView),
               scrollView.isScrollEnabled, !scrollView.isPagingEnabled {
                if let collection = scrollView as? UICollectionView {
                    // A horizontal shelf scrolls in its own orthogonal scroller.
                    if collection.alwaysBounceVertical { return collection }
                } else {
                    return scrollView
                }
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// `navigationBar.topEdgeEffect` on iOS 26+: the system's own
    /// `UIScrollEdgeEffect` on the screen's scroll views, with the authored
    /// style as is (`automatic`, `soft`, `hard`) or hidden. App8 adds no
    /// overlay, tint or background of its own; the blur under the bar is the
    /// one any UIKit app gets. Re-run on layout so scroll views the DSL renders
    /// later (collections, async content) are picked up too. Before iOS 26 the
    /// bar keeps the system's default appearance.
    private func applyTopEdgeEffect() {
        guard #available(iOS 26.0, *) else { return }
        let effect = navigationBarConfig?.topEdgeEffect ?? .automatic
        let hidden = effect == .hidden
        let style = Self.systemTopEdgeStyle(effect)
        func apply(in view: UIView) {
            if let scrollView = view as? UIScrollView {
                let edge = scrollView.topEdgeEffect
                if edge.isHidden != hidden { edge.isHidden = hidden }
                if let style, edge.style != style { edge.style = style }
            }
            view.subviews.forEach(apply(in:))
        }
        apply(in: rootContainerView)
    }

    private func searchBarPlacement(_ placement: DSL.Model.SearchBar.Placement) -> UINavigationItem.SearchBarPlacement {
        switch placement {
        case .automatic: return .automatic
        case .stacked: return .stacked
        case .inline: return .inline
        case .integrated:
            if #available(iOS 26.0, *) { return .integrated }
            return .inline
        case .integratedButton:
            if #available(iOS 26.0, *) { return .integratedButton }
            return .inline
        case .integratedCentered:
            if #available(iOS 26.0, *) { return .integratedCentered }
            return .inline
        }
    }

    private func resolveString(_ raw: String) -> String {
        guard raw.contains("{{"), let store = titleViewVariableStore else { return raw }
        return (try? PropertyResolver().resolveToString(raw, context: VariableContext(store: store))) ?? raw
    }

    /// A bar color field (hex or color expression) resolved in the screen's
    /// scope; a non-hex result leaves the field unset and logs `style.color.invalid`.
    private func resolveColor(_ raw: String?) -> UIColor? {
        guard let raw, !raw.isEmpty else { return nil }
        guard raw.contains("{{") else { return UIColor(withHexString: raw) }
        let value = resolveString(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard DSL.Model.Style.Color.Hex.isValidHexString(value), let color = UIColor(withHexString: value) else {
            context.logger.warning("style.color.invalid: '\(raw)' resolved to '\(value)', not a hex color — field left unset. screen='\(screenId)'")
            return nil
        }
        return color
    }

    private func makeBarButton(from barAction: DSL.Model.BarAction, compact: Bool = false) -> UIBarButtonItem {
        // Create a native UIBarButtonItem so iOS 26 Liquid Glass automatically applies
        // the shared circular glass background. Wrapping in a customView would bypass it.
        let uiAction = UIAction { [weak self] _ in
            for action in barAction.actions { self?.executeBarAction(action) }
        }
        // `icon` and `label` are expressions like the title (navigation.md, Bar Action).
        let item: UIBarButtonItem
        if let rawIcon = barAction.icon {
            item = UIBarButtonItem(image: barSymbol(resolveString(rawIcon)), primaryAction: uiAction)
        } else if let rawLabel = barAction.label {
            item = UIBarButtonItem(title: resolveString(rawLabel), primaryAction: uiAction)
        } else {
            item = UIBarButtonItem(primaryAction: uiAction)
        }

        // On iOS 26, `.done` is deprecated — `.prominent` is the new "save/finalize" style
        // and also breaks the item out of the shared glass group into its own colored pill.
        switch barAction.style {
        case "bold", "prominent":
            if #available(iOS 26.0, *) {
                item.style = .prominent
            } else {
                item.style = .done
            }
        case "destructive":
            item.tintColor = .systemRed
        default:
            break
        }

        if let tint = barItemTint(barAction) { item.tintColor = tint }
        observeBarItem(item, barAction)
        return item
    }

    /// The item's tint: `color`, else the bar's `tintColor` (not on a destructive item).
    private func barItemTint(_ barAction: DSL.Model.BarAction) -> UIColor? {
        if let color = resolveColor(barAction.color) { return color }
        guard barAction.style != "destructive" else { return nil }
        // iOS 26 draws bar buttons in the shared glass group with the label
        // color and ignores `navigationBar.tintColor`; the bar's `tintColor`
        // tints its buttons (navigation.md), so set it on the item.
        return resolveColor(navigationBarConfig?.tintColor)
    }

    private func barSymbol(_ name: String) -> UIImage? {
        name.isEmpty ? nil : UIImage(systemName: name)
    }

    /// An item whose `icon`, `label` or `color` is an expression follows its variables:
    /// the same `UIBarButtonItem` gets the new image, title or tint in place (no new
    /// item, so the glass group does not rebuild or flicker). A symbol swap uses the
    /// system replace transition, like an SF Symbol toggled in a button.
    private func observeBarItem(_ item: UIBarButtonItem, _ barAction: DSL.Model.BarAction) {
        let raws = [barAction.icon, barAction.label, barAction.color, navigationBarConfig?.tintColor]
        guard let store = titleViewVariableStore, raws.contains(where: { $0?.contains("{{") == true }) else { return }
        let names = ExpressionDependencies.names(in: raws)
        var icon = barAction.icon.map(resolveString)
        var label = item.title
        barItemSubscriptions.append(store.anyVariableChanged
            .filter { names?.contains($0) ?? true }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                guard let self, let item else { return }
                if let rawIcon = barAction.icon {
                    let name = self.resolveString(rawIcon)
                    if name != icon {
                        icon = name
                        if let image = self.barSymbol(name) {
                            item.setSymbolImage(image, contentTransition: .replace)
                        } else {
                            item.image = nil
                        }
                    }
                } else if let rawLabel = barAction.label {
                    let text = self.resolveString(rawLabel)
                    if text != label {
                        label = text
                        item.title = text
                    }
                }
                let tint = self.barItemTint(barAction) ?? (barAction.style == "destructive" ? .systemRed : nil)
                if item.tintColor != tint { item.tintColor = tint }
            })
    }

    /// `backLabel`'s back button, shown only where there is something to go
    /// back to: never on the root of a stack (a tab's first screen, a flow's
    /// start screen, a modal's first screen).
    private var customBackItem: UIBarButtonItem?

    private func updateCustomBackItem() {
        guard let item = customBackItem else { return }
        let show = canGoBack
        if show, navigationItem.leftBarButtonItem == nil {
            navigationItem.leftBarButtonItem = item
        } else if !show, navigationItem.leftBarButtonItem === item {
            navigationItem.leftBarButtonItem = nil
        }
    }

    /// True when this screen (or the container it sits in, such as a tab
    /// bar screen) is above the first screen of its navigation stack.
    var canGoBack: Bool {
        guard let nav = navigationController else { return false }
        var vc: UIViewController? = self
        while let current = vc, current.parent !== nav { vc = current.parent }
        guard let entry = vc, let index = nav.viewControllers.firstIndex(of: entry) else { return false }
        return index > 0
    }

    @objc private func customBackTapped() {
        let request = NavigationRequest(type: .pop)
        NotificationCenter.default.post(name: .app8NavigationRequest, object: request)
    }

    func executeBarAction(_ action: DSL.Model.Action) {
        switch action.type {
        case .dismiss:
            let request = NavigationRequest(type: .dismiss)
            NotificationCenter.default.post(name: .app8NavigationRequest, object: request)

        case .navigation:
            if action.isBack == true {
                let request = NavigationRequest(type: .pop)
                NotificationCenter.default.post(name: .app8NavigationRequest, object: request)
            } else if let actionHandler {
                // The full executor honors `presentation` (sheet, fullScreen…),
                // `detents`, `grabber`, `transition` and resolves `params`
                // expressions, exactly like the same action on a button.
                actionHandler(action)
            } else if let nextScreen = action.nextScreen {
                let params = action.params?.mapValues { $0.value } ?? [:]
                let request = NavigationRequest(type: .push(screenId: nextScreen, params: params))
                NotificationCenter.default.post(name: .app8NavigationRequest, object: request)
            }

        case .completeFlow:
            if let destination = action.destination {
                let request = NavigationRequest(type: .completeFlow(destination: destination))
                NotificationCenter.default.post(name: .app8NavigationRequest, object: request)
            }

        default:
            // Every other action (showAlert, request, updateVariable, …) runs
            // in the screen's scope through the full action executor.
            if let actionHandler {
                actionHandler(action)
            } else {
                context.logger.warning("Unsupported bar action type: \(action.type)")
            }
        }
    }
}

// MARK: - UISearchResultsUpdating, UISearchBarDelegate

extension ScreenViewController: UISearchResultsUpdating, UISearchBarDelegate, UISearchControllerDelegate {

    /// The width follows the field's focus inside the presentation's own
    /// animation: updated a run loop later, the full-width field met the ✕
    /// first and slid past the leading edge before shrinking back.
    func willPresentSearchController(_ searchController: UISearchController) {
        if navigationBarConfig?.search?.isButton == true {
            // A tap on the integrated capsule can activate the controller
            // without asking `searchBarShouldBeginEditing` first: undo it and
            // treat it as the tap. Left active, it held the presentation
            // context and the pushed search screen's field could not focus.
            DispatchQueue.main.async { searchController.isActive = false }
            runSearchTapOnce()
            return
        }
        resizeSearchAlongPresentation(of: searchController, focused: true)
    }

    func willDismissSearchController(_ searchController: UISearchController) {
        resizeSearchAlongPresentation(of: searchController, focused: false)
    }

    private func resizeSearchAlongPresentation(of searchController: UISearchController, focused: Bool) {
        guard searchWidthConstraint != nil, let bar = navigationController?.navigationBar else { return }
        searchWidthKey = nil
        // `isActive` still reads true through the dismissal: layout passes in
        // between sized the field for focus again, beside the trailing items
        // that came back, and UIKit collapsed it into a search button.
        searchFieldFocused = focused
        updateSearchWidth(focused: focused)
        if let coordinator = searchController.transitionCoordinator {
            coordinator.animate(alongsideTransition: { _ in bar.layoutIfNeeded() }, completion: { [weak self] _ in
                self?.searchWidthKey = nil
                self?.updateSearchWidth()
            })
        } else {
            // Cubic ease-out, 0.33 s (easeOutCubic), like the rest of the engine's motion.
            let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.215, y: 0.61), controlPoint2: CGPoint(x: 0.355, y: 1))
            let animator = UIViewPropertyAnimator(duration: 0.33, timingParameters: timing)
            animator.addAnimations { bar.layoutIfNeeded() }
            animator.startAnimation()
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        guard let name = navigationBarConfig?.search?.bindVariable,
              let store = titleViewVariableStore else { return }
        let text = searchController.searchBar.text ?? ""
        guard (store.getValue(name: name) as? String) != text else { return }
        do {
            try store.setValue(name: name, value: text)
        } catch {
            context.logger.warning("navigationBar.search: can't set '\(name)': \(error)")
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        navigationBarConfig?.search?.onSubmit?.forEach { actionHandler?($0) }
    }

    /// `mode: "button"`: the field never takes focus; the tap runs `onTap`.
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        guard navigationBarConfig?.search?.isButton == true else { return true }
        runSearchTapOnce()
        return false
    }

    /// `onTap` once per tap: activation and editing can both report one tap.
    private func runSearchTapOnce() {
        let now = CACurrentMediaTime()
        guard now - lastSearchTap > 0.5 else { return }
        lastSearchTap = now
        navigationBarConfig?.search?.onTap?.forEach { actionHandler?($0) }
    }

    /// The cancel ✕: UIKit clears and unfocuses the field, then `onCancel` runs
    /// (a search screen pops back to the screen it came from).
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        guard navigationBarConfig?.search?.onCancel?.isEmpty == false else { return }
        // A pop requested while the search controller is still dismissing is
        // dropped by the navigation controller: wait for the dismissal.
        if searchController?.isActive == true {
            pendingSearchCancel = true
        } else {
            runSearchCancel()
        }
    }

    func didDismissSearchController(_ searchController: UISearchController) {
        guard pendingSearchCancel else { return }
        pendingSearchCancel = false
        runSearchCancel()
    }

    private func runSearchCancel() {
        navigationBarConfig?.search?.onCancel?.forEach { actionHandler?($0) }
    }
}
