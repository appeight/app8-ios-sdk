import UIKit

/// Container view controller for modal presentations with its own navigation stack,
/// supporting hierarchical navigation within the modal (e.g. multi-step wizards).
@MainActor
final class ModalViewController: UIViewController {

    private let screenLoader: ScreenLoaderProtocol
    private let appService: App8Service
    private let initialParams: [String: Any]?
    private let context: App8Context

    private let navController: UINavigationController

    /// Strong reference to the transitioning delegate for a custom presentation
    /// (`transitioningDelegate` is weak). Set by the presenter.
    var transitionManager: App8TransitionManager?

    /// Owns delegate duties for the modal's own navigation stack (intra-modal
    /// custom push/pop transitions + context notifications).
    private let navTransitionCoordinator = App8NavTransitionCoordinator()

    var topScreenViewController: ScreenViewController? {
        navController.topViewController as? ScreenViewController
    }

    private let modalId = UUID()

    /// Guards against re-entrant navigation request handling.
    private var isHandlingRequest = false

    init(
        rootScreenVC: UIViewController,
        screenLoader: ScreenLoaderProtocol,
        appService: App8Service,
        params: [String: Any]? = nil,
        context: App8Context
    ) {
        self.screenLoader = screenLoader
        self.appService = appService
        self.initialParams = params
        self.context = context

        self.navController = UINavigationController(rootViewController: rootScreenVC)

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
        // Opaque background prevents the previous view showing through during fullScreen transitions.
        view.backgroundColor = .black
        setupNavigationController()
        subscribeToNavigationRequests()
    }

    private func setupNavigationController() {
        navController.delegate = navTransitionCoordinator
        addChild(navController)
        view.addSubview(navController.view)
        // Pin with Auto Layout (not an autoresizing-mask frame) so the embedded
        // content resizes in lockstep when the host resizes — e.g. a native sheet
        // animating between detents — instead of catching up a frame later.
        navController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            navController.view.topAnchor.constraint(equalTo: view.topAnchor),
            navController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            navController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        navController.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Install gesture-driven swipe-to-dismiss for interactive custom modals.
        transitionManager?.installInteractiveDismiss(on: view)
    }

    private func subscribeToNavigationRequests() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNavigationRequest(_:)),
            name: .app8NavigationRequest,
            object: nil
        )
    }

    // MARK: - Navigation Request Handling

    @objc private func handleNavigationRequest(_ notification: Notification) {
        guard let request = notification.object as? NavigationRequest else { return }

        guard !isHandlingRequest else { return }

        // Only handle requests while this modal is presented.
        guard isBeingPresented || presentingViewController != nil else { return }

        Task { @MainActor in
            do {
                try await handleRequest(request)
            } catch {
                context.logger.error("Navigation error: \(error)")
            }
        }
    }

    private func handleRequest(_ request: NavigationRequest) async throws {
        isHandlingRequest = true
        defer { isHandlingRequest = false }

        switch request.type {
        case .push(let screenId, let params):
            try await pushScreen(id: screenId, params: params, transition: request.transition, animated: true)

        case .pop:
            // At root, dismiss is left to the FlowCoordinator.
            if navController.viewControllers.count > 1 {
                popScreen(animated: true)
            }

        case .popToRoot:
            if navController.viewControllers.count > 1 {
                navController.popToRootViewController(animated: true)
            }

        case .dismiss:
            dismissModal(animated: true)

        case .completeFlow, .switchFlow, .presentModal, .selectTab:
            // Handled by FlowCoordinator / TabBarScreenViewController, not the modal.
            break
        }
    }

    // MARK: - Navigation API

    func pushScreen(
        id: String,
        params: [String: Any] = [:],
        transition: DSL.Model.ScreenTransition.Resolved? = nil,
        animated: Bool = true
    ) async throws {
        let screenComponent = try await screenLoader.loadScreen(id: id)
        let screenVC = await appService.renderScreen(screenComponent, screenId: id, params: params.isEmpty ? nil : params)

        // Intra-modal pushes honor an action-level custom transition; otherwise
        // fall back to UIKit's native push.
        switch transition?.kind {
        case .some(.custom):
            navTransitionCoordinator.register(transition, for: screenVC)
            navController.pushViewController(screenVC, animated: true)
        case .some(.none):
            navController.pushViewController(screenVC, animated: false)
        default:   // .some(.system) or nil → UIKit's native push
            navController.pushViewController(screenVC, animated: animated)
        }
    }

    func popScreen(animated: Bool = true) {
        navController.popViewController(animated: animated)
    }

    func dismissModal(animated: Bool = true) {
        dismiss(animated: animated)
    }

    var stackDepth: Int {
        navController.viewControllers.count
    }
}
