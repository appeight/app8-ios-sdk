import UIKit

/// View controller for rendered screens with optional navigation bar configuration.
@MainActor
final class ScreenViewController: BaseViewController {

    let screenId: String?
    var screenTitle: String? { navigationBarConfig?.title }

    private let navigationBarConfig: DSL.Model.NavigationBar?
    private let dismissKeyboardOnTap: Bool
    private let additionalSafeAreaInsetsConfig: UIEdgeInsets?
    private weak var titleViewService: App8Service?
    private var titleViewVariableStore: VariableStoreProtocol?
    /// Rendered left-aligned titleView, attached directly to the nav bar in viewWillAppear
    /// to avoid UIBarButtonItem's automatic pill/capsule decoration.
    private var leftNavTitleView: UIView?

    /// Holds the current rendered component view — a stable swap target for
    /// streaming structural updates.
    let rootContainerView = UIView()

    /// Active streaming session (non-nil for screens with streaming: true).
    private var streamingSession: StreamingSession?

    /// Wall-clock of the most-recent `viewDidAppear`. Paired with
    /// `viewDidDisappear` to compute `dwellMs` for `app8_screen_dismissed`.
    private var appearedAt: Date?

    override var hasNavigationBar: Bool {
        guard let config = navigationBarConfig else { return false }
        return config.hidden != true
    }

    override func baseAdditionalBottomInset() -> CGFloat {
        additionalSafeAreaInsetsConfig?.bottom ?? 0
    }

    // MARK: - Init

    init(
        screenId: String? = nil,
        navigationBar: DSL.Model.NavigationBar?,
        hidesTabBar: Bool = false,
        dismissKeyboardOnTap: Bool = true,
        additionalSafeAreaInsets: UIEdgeInsets? = nil,
        titleViewService: App8Service? = nil,
        titleViewVariableStore: VariableStoreProtocol? = nil,
        context: App8Context
    ) {
        self.screenId = screenId
        self.navigationBarConfig = navigationBar
        self.dismissKeyboardOnTap = dismissKeyboardOnTap
        self.additionalSafeAreaInsetsConfig = additionalSafeAreaInsets
        self.titleViewService = titleViewService
        self.titleViewVariableStore = titleViewVariableStore
        super.init(context: context)
        self.hidesBottomBarWhenPushed = hidesTabBar
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        context.appearance.register(self)
        setupRootContainer()
        configureNavigationBar()
        configureKeyboardDismissal()
        if let insets = additionalSafeAreaInsetsConfig {
            // Apply top/left/right only — bottom is owned by baseAdditionalBottomInset()
            // and will be set by BaseViewController's keyboard binding on the next run loop.
            additionalSafeAreaInsets = UIEdgeInsets(top: insets.top, left: insets.left, bottom: 0, right: insets.right)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        attachLeftTitleViewIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard context.analyticsConfig.autoScreenEvents else {
            appearedAt = nil
            return
        }
        let now = Date()
        appearedAt = now
        var properties: [String: Any] = [:]
        if let title = navigationBarConfig?.title { properties["title"] = title }
        context.analyticsBus.dispatch(App8AnalyticsEvent(
            name: "app8_screen_appeared",
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
        leftNavTitleView?.removeFromSuperview()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard context.analyticsConfig.autoScreenEvents, let appeared = appearedAt else {
            appearedAt = nil
            return
        }
        let now = Date()
        appearedAt = nil
        let dwellMs = Int(now.timeIntervalSince(appeared) * 1000)
        let properties: [String: Any] = ["dwellMs": dwellMs]
        context.analyticsBus.dispatch(App8AnalyticsEvent(
            name: "app8_screen_dismissed",
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
        let updater = ScreenUpdater(container: rootContainerView, initialView: currentView, service: service, context: context)
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
                let resolver = PropertyResolver()
                let context = VariableContext(store: store)
                title = (try? resolver.resolveToString(rawTitle, context: context)) ?? rawTitle
            } else {
                title = rawTitle
            }
            if let colorHex = config.titleColor, let color = UIColor(withHexString: colorHex) {
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
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: btn)
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
    }

    private func makeBarButton(from barAction: DSL.Model.BarAction, compact: Bool = false) -> UIBarButtonItem {
        // Create a native UIBarButtonItem so iOS 26 Liquid Glass automatically applies
        // the shared circular glass background. Wrapping in a customView would bypass it.
        let uiAction = UIAction { [weak self] _ in
            self?.executeBarAction(barAction.action)
        }
        let item: UIBarButtonItem
        if let iconName = barAction.icon {
            item = UIBarButtonItem(image: UIImage(systemName: iconName), primaryAction: uiAction)
        } else if let label = barAction.label {
            item = UIBarButtonItem(title: label, primaryAction: uiAction)
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

        if let colorHex = barAction.color, let color = UIColor(withHexString: colorHex) {
            item.tintColor = color
        }

        return item
    }

    @objc private func customBackTapped() {
        let request = NavigationRequest(type: .pop)
        NotificationCenter.default.post(name: .app8NavigationRequest, object: request)
    }

    private func executeBarAction(_ action: DSL.Model.Action) {
        switch action.type {
        case .dismiss:
            let request = NavigationRequest(type: .dismiss)
            NotificationCenter.default.post(name: .app8NavigationRequest, object: request)

        case .navigation:
            if action.isBack == true {
                let request = NavigationRequest(type: .pop)
                NotificationCenter.default.post(name: .app8NavigationRequest, object: request)
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
            context.logger.warning("Unsupported bar action type: \(action.type)")
        }
    }
}
