// Navigation-controller delegate that applies custom transitions to pushes and
// pops. Retained by the owning container (FlowViewController / ModalViewController)
// and set as `navController.delegate`.
//
// It also owns the navigation controller's "did show" duties (screen-context
// notifications, interactive-pop gesture management) that previously lived on
// the container, so all delegate behavior is in one place.

import UIKit

@MainActor
final class App8NavTransitionCoordinator: NSObject, UINavigationControllerDelegate, UIGestureRecognizerDelegate {

    /// Transition to apply to the next push. Set immediately before pushing.
    var pendingPush: DSL.Model.ScreenTransition.Resolved?

    /// Per-screen transition so a pop reuses the same one, reversed.
    private var transitions: [ObjectIdentifier: DSL.Model.ScreenTransition.Resolved] = [:]

    /// Active interactive-pop driver for the visible custom-interactive screen.
    private var interactiveDriver: App8InteractiveTransitionDriver?

    private weak var navigationController: UINavigationController?

    /// Register the transition that pushed `viewController` (so its pop matches).
    func register(_ transition: DSL.Model.ScreenTransition.Resolved?, for viewController: UIViewController) {
        guard let transition, transition.isAnimated else { return }
        transitions[ObjectIdentifier(viewController)] = transition
        pendingCustomPush = true
        refreshDelegateIfNeeded()
    }

    /// The navigation controller this coordinator is the delegate of.
    func attach(to navigationController: UINavigationController) {
        self.navigationController = navigationController
        navigationController.delegate = self
        answeredTransitionMethods = wantsCustomTransitions
    }

    // MARK: - Content back swipe (CustomTransitionDelegateGate)

    /// A custom push is about to start (its transition is registered).
    private var pendingCustomPush = false
    /// What `responds(to:)` answered when UIKit last read the delegate.
    private var answeredTransitionMethods = false

    /// Whether the transition methods are needed: a custom push about to
    /// start, or a top screen whose pop is custom (or the engine's zoom).
    var wantsCustomTransitions: Bool {
        if pendingCustomPush || ZoomMorphTransition.hasPendingPush { return true }
        guard let top = navigationController?.topViewController else { return false }
        return transitions[ObjectIdentifier(top)] != nil || ZoomMorphTransition.of(top) != nil
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if CustomTransitionDelegateGate.isTransitionSelector(aSelector) { return wantsCustomTransitions }
        return super.responds(to: aSelector)
    }

    func refreshDelegateIfNeeded() {
        let wants = wantsCustomTransitions
        guard wants != answeredTransitionMethods, let nav = navigationController, nav.delegate === self else { return }
        answeredTransitionMethods = wants
        CustomTransitionDelegateGate.refresh(nav)
    }

    // MARK: - UINavigationControllerDelegate

    func navigationController(
        _ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from fromVC: UIViewController,
        to toVC: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        self.navigationController = navigationController
        if let morph = ZoomMorphTransition.animator(for: operation, from: fromVC, to: toVC) { return morph }

        let resolved: DSL.Model.ScreenTransition.Resolved?
        let direction: TransitionDirection
        switch operation {
        case .push:
            resolved = transitions[ObjectIdentifier(toVC)]
            direction = .forward
        case .pop:
            resolved = transitions[ObjectIdentifier(fromVC)]   // the screen leaving
            direction = .reverse
        default:
            resolved = nil
            direction = .forward
        }

        guard let resolved, resolved.isAnimated else { return nil }   // nil → UIKit default
        return resolved.makeAnimator(direction: direction)
    }

    func navigationController(
        _ navigationController: UINavigationController,
        interactionControllerFor animationController: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        if let morph = ZoomMorphTransition.interactionController(for: animationController) { return morph }
        guard let interactiveDriver, interactiveDriver.isInteracting else { return nil }
        return interactiveDriver
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        self.navigationController = navigationController
        pruneTransitions(keeping: navigationController.viewControllers)
        pendingCustomPush = false
        configureInteractivePop(for: navigationController)
        DispatchQueue.main.async { [weak self] in self?.refreshDelegateIfNeeded() }
        NotificationCenter.default.post(name: .app8ScreenContextChanged, object: nil)
    }

    // MARK: - Interactive pop wiring

    /// Either keep the system swipe-back (default screens) or install a custom
    /// edge-pan driving an interactive pop (screens with an interactive custom
    /// transition). Never both, to avoid double-driving the transition.
    private func configureInteractivePop(for navigationController: UINavigationController) {
        let canPop = navigationController.viewControllers.count > 1
        let top = navigationController.topViewController
        let resolved = top.flatMap { transitions[ObjectIdentifier($0)] }

        // Screen-level opt-out (DSL `swipeBackEnabled: false`): the visible screen
        // forbids any swipe-back gesture — neither the system pop nor a custom
        // interactive edge-pan is installed, so it can only be left programmatically.
        let allowsSwipeBack = (top as? ScreenViewController)?.allowsSwipeBack ?? true

        let wantsCustomInteractive = canPop
            && allowsSwipeBack
            && (resolved?.isAnimated ?? false)
            && (resolved?.interactive?.enabled ?? false)

        // Tear down any previous custom driver.
        interactiveDriver?.detach()
        interactiveDriver = nil

        if ZoomMorphTransition.blocksSystemPopGesture(in: navigationController) {
            // The pose-and-morph screen runs its own back swipe.
            navigationController.interactivePopGestureRecognizer?.isEnabled = false
        } else if wantsCustomInteractive, let resolved {
            // Custom interactive pop: disable the system gesture, drive our own.
            navigationController.interactivePopGestureRecognizer?.isEnabled = false
            let config = resolved.interactive ?? .init(enabled: true, edge: nil, threshold: 0.3, velocity: 800)
            let driver = App8InteractiveTransitionDriver(
                edge: resolved.edge,
                config: config,
                begin: { [weak navigationController] in
                    navigationController?.popViewController(animated: true)
                }
            )
            driver.attachScreenEdge(
                to: navigationController.view,
                edges: screenEdge(for: resolved.edge.opposite)
            )
            interactiveDriver = driver
        } else {
            // Default behavior: system interactive pop gesture (as before),
            // unless the visible screen opts out via `swipeBackEnabled: false`.
            navigationController.interactivePopGestureRecognizer?.delegate = self
            navigationController.interactivePopGestureRecognizer?.isEnabled = canPop && allowsSwipeBack
        }
    }

    private func screenEdge(for edge: DSL.Model.ScreenTransition.Edge) -> UIRectEdge {
        switch edge {
        case .leading:  return .left
        case .trailing: return .right
        case .top:      return .top
        case .bottom:   return .bottom
        }
    }

    private func pruneTransitions(keeping viewControllers: [UIViewController]) {
        let live = Set(viewControllers.map(ObjectIdentifier.init))
        transitions = transitions.filter { live.contains($0.key) }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }
}
