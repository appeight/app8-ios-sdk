import UIKit

/// Container view controller that manages a navigation stack for a single flow.
@MainActor
final class FlowViewController: UIViewController, UIGestureRecognizerDelegate, UINavigationControllerDelegate, UIAdaptivePresentationControllerDelegate {

    private let flow: DSL.Model.App.Navigation.Flow
    private let screenLoader: ScreenLoaderProtocol
    private let appService: App8Service
    private let context: App8Context

    private var navController: UINavigationController?

    /// Set when the start screen is a tabBarScreen.
    private var tabBarScreenController: TabBarScreenViewController?

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return navController?.viewControllers.count ?? 0 > 1
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
                    unselectedColor: entity.content.unselectedColor
                ),
                screenLoader: screenLoader,
                appService: appService,
                context: context
            )
            try await tabBarVC.setupTabs()
            embedTabBar(tabBarVC)
            self.tabBarScreenController = tabBarVC
        } else {
            let navController = UINavigationController()
            navController.setNavigationBarHidden(true, animated: false)
            navController.delegate = self
            navController.interactivePopGestureRecognizer?.isEnabled = true
            navController.interactivePopGestureRecognizer?.delegate = self
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

    func pushScreen(id: String, params: [String: Any] = [:], animated: Bool = true) async throws {
        guard let navController = navController else {
            // With a tab bar, navigation is handled by TabBarScreenViewController.
            return
        }

        let screenComponent = try await screenLoader.loadScreen(id: id)
        let screenVC = await appService.renderScreen(screenComponent, screenId: id, params: params.isEmpty ? nil : params)
        navController.pushViewController(screenVC, animated: animated)
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
        detents: [DSL.Model.Action.SheetDetent]?
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

        switch style {
        case .sheet, .pageSheet:
            modalVC.modalPresentationStyle = .pageSheet
            if let sheet = modalVC.sheetPresentationController {
                sheet.detents = detents?.map { detent in
                    switch detent {
                    case .medium: return .medium()
                    case .large: return .large()
                    }
                } ?? [.large()]
                sheet.prefersGrabberVisible = true
            }
        case .fullScreen:
            modalVC.modalPresentationStyle = .fullScreen
        case .formSheet:
            modalVC.modalPresentationStyle = .formSheet
        case .crossDissolve:
            modalVC.modalPresentationStyle = .overFullScreen
            modalVC.modalTransitionStyle = .crossDissolve
        }

        presentedModal = modalVC
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
}
