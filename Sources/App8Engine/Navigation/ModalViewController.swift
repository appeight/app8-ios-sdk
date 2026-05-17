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
        addChild(navController)
        view.addSubview(navController.view)
        navController.view.frame = view.bounds
        navController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        navController.didMove(toParent: self)
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
            try await pushScreen(id: screenId, params: params, animated: true)

        case .pop:
            // At root, dismiss is left to the FlowCoordinator.
            if navController.viewControllers.count > 1 {
                popScreen(animated: true)
            }

        case .dismiss:
            dismissModal(animated: true)

        case .completeFlow, .switchFlow, .presentModal, .selectTab:
            // Handled by FlowCoordinator / TabBarScreenViewController, not the modal.
            break
        }
    }

    // MARK: - Navigation API

    func pushScreen(id: String, params: [String: Any] = [:], animated: Bool = true) async throws {
        let screenComponent = try await screenLoader.loadScreen(id: id)
        let screenVC = await appService.renderScreen(screenComponent, screenId: id, params: params.isEmpty ? nil : params)
        navController.pushViewController(screenVC, animated: animated)
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
