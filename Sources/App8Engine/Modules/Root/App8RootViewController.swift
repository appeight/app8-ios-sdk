import UIKit

/// Root view controller for App8 apps. Manages flow transitions.
class App8RootViewController: UIViewController {

    private let defaultUserInterfaceStyle: UIUserInterfaceStyle?
    private let context: App8Context

    private var currentFlowViewController: UIViewController?

    init(app: DSL.Model.App, context: App8Context) {
        self.context = context
        defaultUserInterfaceStyle = app.defaultUserInterfaceStyle?.ui
        context.logger.debug("App8RootVC: app.title=\(app.title ?? "nil") app.defaultUserInterfaceStyle=\(String(describing: app.defaultUserInterfaceStyle))")
        super.init(nibName: nil, bundle: nil)
        if let defaultUserInterfaceStyle {
            overrideUserInterfaceStyle = defaultUserInterfaceStyle
            context.appearance.userInterfaceStyle = defaultUserInterfaceStyle
            context.logger.debug("App8RootVC: defaultUserInterfaceStyle = \(defaultUserInterfaceStyle == .light ? "light" : defaultUserInterfaceStyle == .dark ? "dark" : "unspecified")")
        } else {
            context.logger.debug("App8RootVC: defaultUserInterfaceStyle = nil (not set in app.json)")
        }
        subscribeToFlowTransitions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Also set on the window so every view resolves the correct trait collection,
        // even before being added to the VC hierarchy (e.g. during init, glass effects).
        if let defaultUserInterfaceStyle {
            view.window?.overrideUserInterfaceStyle = defaultUserInterfaceStyle
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func embedFlow(_ flowViewController: UIViewController) {
        currentFlowViewController = flowViewController
        embed(flowViewController)
    }

    private func subscribeToFlowTransitions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFlowTransition(_:)),
            name: .app8FlowComplete,
            object: nil
        )
    }

    @objc private func handleFlowTransition(_ notification: Notification) {
        guard let transition = notification.object as? FlowTransition else { return }
        transitionToFlow(transition.viewController)
    }

    private func transitionToFlow(_ newFlowVC: UIViewController) {
        guard let oldFlowVC = currentFlowViewController else {
            embedFlow(newFlowVC)
            return
        }

        addChild(newFlowVC)
        newFlowVC.view.frame = view.bounds
        newFlowVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        newFlowVC.view.alpha = 0

        view.addSubview(newFlowVC.view)

        UIView.animate(withDuration: 0.3, animations: {
            newFlowVC.view.alpha = 1
            oldFlowVC.view.alpha = 0
        }) { _ in
            oldFlowVC.willMove(toParent: nil)
            oldFlowVC.view.removeFromSuperview()
            oldFlowVC.removeFromParent()

            newFlowVC.didMove(toParent: self)
            self.currentFlowViewController = newFlowVC
        }
    }
}
