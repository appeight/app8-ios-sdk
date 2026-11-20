import UIKit

/// Container view controller that manages a navigation stack for a single flow.
@MainActor
final class FlowViewController: UIViewController, UIAdaptivePresentationControllerDelegate {

    private let flow: DSL.Model.App.Navigation.Flow
    private let screenLoader: ScreenLoaderProtocol
    private let appService: App8Service
    private let context: App8Context

    private var navController: UINavigationController?

    /// Owns the navigation controller's delegate duties: custom push/pop
    /// transitions, screen-context notifications, and interactive-pop gestures.
    /// Retained here because `UINavigationController.delegate` is weak.
    private let navTransitionCoordinator = App8NavTransitionCoordinator()

    /// Set when the start screen is a tabBarScreen.
    private var tabBarScreenController: TabBarScreenViewController?

    init(flow: DSL.Model.App.Navigation.Flow, screenLoader: ScreenLoaderProtocol, appService: App8Service, context: App8Context) {
        self.flow = flow
        self.screenLoader = screenLoader
        self.appService = appService
        self.context = context

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The top screen decides the status bar style (its `userInterfaceStyle`).
    override var childForStatusBarStyle: UIViewController? { navController ?? tabBarScreenController }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    /// Set up the flow with its start screen, choosing navigation controller vs tab bar.
    func setup(with startScreenComponent: DSL.Model.Component.`Any`) async throws {
        if case .key(.tabBarScreen) = startScreenComponent.type,
           let entity: DSL.Model.Component.TabBarScreen.Entity = startScreenComponent.asConcreteEntity() {
            let tabBarVC = TabBarScreenViewController(
                tabBarContent: DSL.Model.TabBarContent(
                    tabs: entity.content.tabs,
                    initialTab: entity.content.initialTab,
                    tintColor: entity.content.tintColor,
                    unselectedColor: entity.content.unselectedColor,
                    badgeColor: entity.content.badgeColor,
                    badgeTextColor: entity.content.badgeTextColor,
                    barStyle: entity.content.barStyle,
                    selectionIndicatorColor: entity.content.selectionIndicatorColor
                ),
                screenLoader: screenLoader,
                appService: appService,
                context: context
            )
            try await tabBarVC.setupTabs()
            embedTabBar(tabBarVC)
            self.tabBarScreenController = tabBarVC
        } else {
            let navController = App8NavigationController()
            navController.setNavigationBarHidden(true, animated: false)
            navController.delegate = navTransitionCoordinator
            embedNavigationController(navController)
            self.navController = navController

            let screenVC = await appService.renderScreen(startScreenComponent, screenId: flow.startScreen)
            navController.pushViewController(screenVC, animated: false)
        }
    }

    private func embedNavigationController(_ navController: UINavigationController) {
        addChild(navController)
        view.addSubview(navController.view)
        navController.view.frame = view.bounds
        navController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        navController.didMove(toParent: self)
    }

    private func embedTabBar(_ tabBarVC: TabBarScreenViewController) {
        addChild(tabBarVC)
        view.addSubview(tabBarVC.view)
        tabBarVC.view.frame = view.bounds
        tabBarVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tabBarVC.didMove(toParent: self)
    }

    // MARK: - Navigation API

    func pushScreen(
        id: String,
        params: [String: Any] = [:],
        transition: DSL.Model.ScreenTransition.Resolved? = nil,
        animated: Bool = true
    ) async throws {
        guard let navController = navController else {
            // With a tab bar, navigation is handled by TabBarScreenViewController.
            return
        }

        let screenComponent = try await screenLoader.loadScreen(id: id)
        let screenVC = await appService.renderScreen(screenComponent, screenId: id, params: params.isEmpty ? nil : params)

        // Precedence: action transition → target screen default → app default.
        let resolved = transition ?? resolveDefaultTransition(for: screenComponent)
        pushScreen(screenVC, on: navController, transition: resolved, animated: animated)
    }

    /// Apply the resolved transition and push. `.custom` registers an animator
    /// on the coordinator; `.none` pushes instantly; `.system`/nil use UIKit's
    /// native push.
    private func pushScreen(
        _ screenVC: UIViewController,
        on navController: UINavigationController,
        transition: DSL.Model.ScreenTransition.Resolved?,
        animated: Bool
    ) {
        switch transition?.kind {
        case .some(.nativeZoom):
            NativeZoomTransition.push(screenVC, on: navController, transition: transition!, coordinator: navTransitionCoordinator, logger: context.logger)
        case .some(.custom), .some(.shared):
            navTransitionCoordinator.register(transition, for: screenVC)
            navController.pushViewController(screenVC, animated: true)
        case .some(.none):
            navController.pushViewController(screenVC, animated: false)
        default:   // .some(.system) or nil → UIKit's native push
            navController.pushViewController(screenVC, animated: animated)
        }
    }

    /// Screen-level default → app-level default. Returns nil when neither is set
    /// (caller falls back to UIKit's native push).
    private func resolveDefaultTransition(
        for screenComponent: DSL.Model.Component.`Any`
    ) -> DSL.Model.ScreenTransition.Resolved? {
        let animationResolver = context.animationResolver ?? { _ in nil }
        let screenEntity: DSL.Model.Component.ConcreteEntity<DSL.Model.Component.View.C>? =
            screenComponent.asConcreteEntity()
        if let inline = screenEntity?.content.transition?.screenOrNil?.inlineOrNil {
            return DSL.Model.ScreenTransition.resolve(inline, animationResolver: animationResolver)
        }
        if let appDefault = context.appDefaultTransition {
            return DSL.Model.ScreenTransition.resolve(appDefault, animationResolver: animationResolver)
        }
        return nil
    }

    func popScreen(animated: Bool = true) {
        navController?.popViewController(animated: animated)
    }

    func popToRoot(animated: Bool = true) {
        navController?.popToRootViewController(animated: animated)
    }

    /// The currently visible ScreenViewController in this flow's managed hierarchy.
    var visibleScreenViewController: ScreenViewController? {
        if let tabBarVC = tabBarScreenController {
            guard tabBarVC.selectedIndex < tabBarVC.viewControllers?.count ?? 0,
                  let selectedNav = tabBarVC.viewControllers?[tabBarVC.selectedIndex] as? UINavigationController
            else { return nil }
            return selectedNav.topViewController as? ScreenViewController
        }
        return navController?.topViewController as? ScreenViewController
    }

    var stackDepth: Int {
        navController?.viewControllers.count ?? 0
    }

    // MARK: - Modal Presentation

    private(set) var presentedModal: ModalViewController?

    func presentModal(
        screenId: String,
        params: [String: Any],
        style: ModalPresentationStyle,
        detents: [DSL.Model.Action.SheetDetent]?,
        grabber: Bool? = nil,
        transition: DSL.Model.ScreenTransition.Resolved? = nil
    ) async throws {
        let screenComponent = try await screenLoader.loadScreen(id: screenId)
        let screenVC = await appService.renderScreen(screenComponent, screenId: screenId, params: params.isEmpty ? nil : params)

        // Modal container with its own nav stack.
        let modalVC = ModalViewController(
            rootScreenVC: screenVC,
            screenLoader: screenLoader,
            appService: appService,
            params: params.isEmpty ? nil : params,
            context: context
        )

        if let transition, transition.kind == .nativeZoom, let zoom = transition.nativeZoom {
            // Native zoom out of an element on the visible screen.
            switch style {
            case .sheet, .pageSheet: modalVC.modalPresentationStyle = .pageSheet
            case .formSheet: modalVC.modalPresentationStyle = .formSheet
            default: modalVC.modalPresentationStyle = .fullScreen
            }
            let presenting = presentedModal?.topScreenViewController ?? visibleScreenViewController
            if !NativeZoomTransition.apply(to: modalVC, zoom: zoom, presentingScreen: presenting, logger: context.logger) {
                modalVC.modalTransitionStyle = .crossDissolve
            }
        } else if style == .custom, let transition, transition.isAnimated {
            // Engine-driven custom modal transition.
            let manager = App8TransitionManager(resolved: transition)
            modalVC.modalPresentationStyle = .custom
            modalVC.transitioningDelegate = manager
            modalVC.transitionManager = manager   // strong retention (delegate is weak)
            manager.requestDismiss = { [weak modalVC] in modalVC?.dismiss(animated: true) }
            manager.onDismissCompleted = { [weak self] in
                self?.presentedModal = nil
                NotificationCenter.default.post(name: .app8ScreenContextChanged, object: nil)
            }
        } else {
            switch style {
            case .sheet, .pageSheet:
                modalVC.modalPresentationStyle = .pageSheet
                if let sheet = modalVC.sheetPresentationController {
                    let list = (detents?.isEmpty == false) ? detents! : [.large]
                    sheet.detents = list.map(Self.uiDetent(for:))
                    sheet.prefersGrabberVisible = grabber ?? true
                    // Scrolling past the top of the content grows the sheet to the
                    // next detent instead of bouncing (matches the system default,
                    // set explicitly for clarity).
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = true
                }
            case .fullScreen:
                modalVC.modalPresentationStyle = .fullScreen
            case .formSheet:
                modalVC.modalPresentationStyle = .formSheet
            case .crossDissolve:
                modalVC.modalPresentationStyle = .overFullScreen
                modalVC.modalTransitionStyle = .crossDissolve
            case .custom:
                // Custom requested but no usable transition — degrade to fullScreen.
                modalVC.modalPresentationStyle = .fullScreen
            }
        }

        // A screen with its own `userInterfaceStyle` passes it to what it presents
        // (UIKit passes the presenter's traits; the engine presents from here,
        // whose style is the app's). The modal's own screens may set theirs.
        let presenter = presentedModal?.topScreenViewController ?? visibleScreenViewController
        if let style = presenter?.screenUserInterfaceStyle ?? presentedModal.flatMap({ $0.overrideUserInterfaceStyle == .unspecified ? nil : $0.overrideUserInterfaceStyle }) {
            modalVC.overrideUserInterfaceStyle = style
        }

        presentedModal = modalVC
        modalVC.onDidDismiss = { [weak self, weak modalVC] in
            // Covers dismissals that bypass `dismissModal` (e.g. the zoom
            // transition's interactive dismiss).
            guard let self, self.presentedModal === modalVC else { return }
            self.presentedModal = nil
            NotificationCenter.default.post(name: .app8ScreenContextChanged, object: nil)
        }
        modalVC.presentationController?.delegate = self
        present(modalVC, animated: true)
    }

    // MARK: - UIAdaptivePresentationControllerDelegate

    /// Called when a modal is dismissed via swipe-down gesture.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        presentedModal = nil
        NotificationCenter.default.post(name: .app8ScreenContextChanged, object: nil)
    }

    func dismissModal(animated: Bool = true) {
        if presentedModal != nil {
            dismiss(animated: animated) { [weak self] in
                self?.presentedModal = nil
                NotificationCenter.default.post(name: .app8ScreenContextChanged, object: nil)
            }
        }
    }

    /// Dismisses the presented modal and returns once it is gone (immediately
    /// when nothing is presented). Waits for an in-flight presentation first:
    /// UIKit drops a dismissal requested mid-transition without calling its
    /// completion. Time limits keep a stuck transition from holding up
    /// navigation forever.
    func dismissModalAndWait(animated: Bool = true) async {
        guard presentedModal != nil, let presented = presentedViewController else {
            presentedModal = nil
            return
        }
        let step: UInt64 = 20_000_000
        var deadline = Date().addingTimeInterval(2)
        while presented.isBeingPresented, Date() < deadline {
            try? await Task.sleep(nanoseconds: step)
        }
        var completed = false
        dismiss(animated: animated) { completed = true }
        deadline = Date().addingTimeInterval(2)
        while !completed, presentedViewController === presented, Date() < deadline {
            try? await Task.sleep(nanoseconds: step)
        }
        if !completed, presentedViewController === presented {
            context.logger.warning("dismiss: the modal did not finish dismissing; continuing")
        }
        presentedModal = nil
        NotificationCenter.default.post(name: .app8ScreenContextChanged, object: nil)
    }

    /// Map a declarative `SheetDetent` to a UIKit sheet detent. `fixed`/`fraction`
    /// become custom detents (heights are clamped to the container by UIKit).
    private static func uiDetent(for detent: DSL.Model.Action.SheetDetent) -> UISheetPresentationController.Detent {
        switch detent {
        case .medium:
            return .medium()
        case .large:
            return .large()
        case .fixed(let raw):
            // A DSL height can be negative or absurd; UIKit clamps to the container.
            let height = raw.isFinite ? max(0, min(raw, 100_000)) : 0
            let id = UISheetPresentationController.Detent.Identifier("app8.fixed.\(Int(height.rounded()))")
            return .custom(identifier: id) { _ in CGFloat(height) }
        case .fraction(let fraction):
            let clamped = max(0.1, min(1, fraction))
            let id = UISheetPresentationController.Detent.Identifier("app8.fraction.\(Int((clamped * 1000).rounded()))")
            return .custom(identifier: id) { context in context.maximumDetentValue * CGFloat(clamped) }
        }
    }
}
