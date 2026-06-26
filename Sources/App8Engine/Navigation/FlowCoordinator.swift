import UIKit
import Combine

/// Manages navigation flows defined in app.json.
@MainActor
final class FlowCoordinator {

    private let app: DSL.Model.App
    private let screenLoader: ScreenLoaderProtocol
    private let appService: App8Service
    private let context: App8Context

    private let screenContextSubject = CurrentValueSubject<App8.ScreenContext?, Never>(nil)

    var screenContext: AnyPublisher<App8.ScreenContext, Never> {
        screenContextSubject.compactMap { $0 }.eraseToAnyPublisher()
    }

    private(set) var currentFlowId: String

    private(set) var currentFlowViewController: FlowViewController?

    /// Cached FlowViewControllers by flow ID (for switchFlow — future).
    private var flowViewControllers: [String: FlowViewController] = [:]

    /// - Parameter startFlowId: When non-nil, the coordinator starts at this
    ///   flow instead of the manifest's `navigation.startFlow`. Used by
    ///   `renderFlow(flowId:)` to render a specific (possibly non-default) flow
    ///   from a multi-flow manifest.
    init(
        app: DSL.Model.App,
        screenLoader: ScreenLoaderProtocol,
        appService: App8Service,
        context: App8Context,
        startFlowId: String? = nil
    ) {
        self.app = app
        self.screenLoader = screenLoader
        self.appService = appService
        self.context = context
        self.currentFlowId = startFlowId ?? app.navigation?.startFlow ?? ""
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        currentFlowViewController = nil
        flowViewControllers.removeAll()
    }

    /// Start the initial flow and return its view controller.
    func start() async throws -> UIViewController {
        guard let flow = findFlow(id: currentFlowId) else {
            throw NavigationError.flowNotFound(currentFlowId)
        }

        let flowVC = try await createFlowViewController(for: flow)
        currentFlowViewController = flowVC
        flowViewControllers[flow.id] = flowVC

        subscribeToNavigationRequests()
        emitVisibleContext()

        return flowVC
    }

    /// Transition to a new flow (one-way, cannot return).
    func completeFlow(destination: String) async throws {
        guard let flow = findFlow(id: destination) else {
            throw NavigationError.flowNotFound(destination)
        }

        let newFlowVC = try await createFlowViewController(for: flow)

        let previousFlowId = currentFlowId
        currentFlowId = destination
        currentFlowViewController = newFlowVC
        flowViewControllers[destination] = newFlowVC

        // App8RootViewController observes this to swap the flow.
        NotificationCenter.default.post(
            name: .app8FlowComplete,
            object: FlowTransition(from: previousFlowId, to: destination, viewController: newFlowVC)
        )

        emitVisibleContext()
    }

    private func findFlow(id: String) -> DSL.Model.App.Navigation.Flow? {
        return app.navigation?.flows.first { $0.id == id }
    }

    private func createFlowViewController(for flow: DSL.Model.App.Navigation.Flow) async throws -> FlowViewController {
        let flowVC = FlowViewController(
            flow: flow,
            screenLoader: screenLoader,
            appService: appService,
            context: context
        )

        let startScreenComponent = try await screenLoader.loadScreen(id: flow.startScreen)
        try await flowVC.setup(with: startScreenComponent)

        return flowVC
    }

    private func subscribeToNavigationRequests() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNavigationRequest(_:)),
            name: .app8NavigationRequest,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenContextChanged),
            name: .app8ScreenContextChanged,
            object: nil
        )
    }

    @objc private func handleScreenContextChanged() {
        emitVisibleContext()
    }

    /// Walk the managed VC hierarchy to find the visible screen and emit its context.
    func emitVisibleContext() {
        guard let flowVC = currentFlowViewController else { return }

        // Modal takes priority.
        if let modal = flowVC.presentedModal {
            if let screenVC = modal.topScreenViewController {
                sendContext(from: screenVC)
                return
            }
        }

        if let screenVC = flowVC.visibleScreenViewController {
            sendContext(from: screenVC)
        }
    }

    private func sendContext(from screenVC: ScreenViewController) {
        guard let screenId = screenVC.screenId else { return }
        let screenContext = App8.ScreenContext(
            screenId: screenId,
            title: screenVC.screenTitle,
            flowId: currentFlowId
        )
        guard screenContext != screenContextSubject.value else { return }
        context.logger.debug("ScreenContext: \(screenContext)")
        screenContextSubject.send(screenContext)
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
        switch request.type {
        case .push(let screenId, let params):
            // When a modal is presented, the modal handles push/pop itself.
            guard currentFlowViewController?.presentedModal == nil else { return }
            try await currentFlowViewController?.pushScreen(
                id: screenId,
                params: params,
                transition: request.transition,
                animated: true
            )

        case .pop:
            guard currentFlowViewController?.presentedModal == nil else { return }
            currentFlowViewController?.popScreen(animated: true)

        case .popToRoot:
            guard currentFlowViewController?.presentedModal == nil else { return }
            currentFlowViewController?.popToRoot(animated: true)

        case .completeFlow(let destination):
            try await completeFlow(destination: destination)

        case .presentModal(let screenId, let params, let style, let detents, let grabber):
            try await currentFlowViewController?.presentModal(
                screenId: screenId,
                params: params,
                style: style,
                detents: detents,
                grabber: grabber,
                transition: request.transition
            )
            emitVisibleContext()

        case .dismiss:
            currentFlowViewController?.dismissModal(animated: true)
            // Context is emitted in dismissModal's completion, after presentedModal clears.

        case .switchFlow:
            context.logger.warning("Action not yet implemented: \(request.type)")

        case .selectTab:
            // Handled by TabBarScreenViewController.
            break
        }
    }
}

struct FlowTransition {
    let from: String
    let to: String
    let viewController: UIViewController
}

enum NavigationError: Error, LocalizedError {
    case flowNotFound(String)
    case screenNotFound(String)
    case screenLoadFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case .flowNotFound(let id):
            return "Flow not found: \(id)"
        case .screenNotFound(let id):
            return "Screen not found: \(id)"
        case .screenLoadFailed(let id, let error):
            return "Failed to load screen '\(id)': \(error.localizedDescription)"
        }
    }
}
