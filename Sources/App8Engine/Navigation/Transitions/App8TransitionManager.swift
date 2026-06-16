// Transitioning delegate for custom modal presentations. Vends the present /
// dismiss animators, a presentation controller (keeps the presenter visible and
// optionally dims the backdrop), and an interactive driver for swipe-to-dismiss.
//
// Retained strongly by the presented `ModalViewController` — `transitioningDelegate`
// is a weak reference.

import UIKit

@MainActor
final class App8TransitionManager: NSObject, UIViewControllerTransitioningDelegate {

    private let resolved: DSL.Model.ScreenTransition.Resolved

    /// Run when the modal has fully dismissed (any trigger: button, backdrop, swipe).
    /// Set by the presenter to clear its modal bookkeeping.
    var onDismissCompleted: (() -> Void)?

    /// Starts a dismissal synchronously. Wired by the presenter to dismiss the
    /// modal through UIKit so backdrop taps and interactive swipes both drive
    /// this transitioning delegate.
    var requestDismiss: (() -> Void)?

    private var interactiveDriver: App8InteractiveTransitionDriver?
    private weak var presentationController: App8DimmingPresentationController?

    init(resolved: DSL.Model.ScreenTransition.Resolved) {
        self.resolved = resolved
        super.init()
    }

    // MARK: - Animators

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        resolved.makeAnimator(direction: .forward)
    }

    func animationController(
        forDismissed dismissed: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        let animator = resolved.makeAnimator(direction: .reverse)
        // Clear modal bookkeeping when a dismissal completes, regardless of which
        // animator drives it.
        if let property = animator as? PropertyTransitionAnimator {
            property.onFinished = { [weak self] completed in
                if completed { self?.onDismissCompleted?() }
            }
        } else if let shared = animator as? SharedElementTransitionAnimator {
            shared.onFinished = { [weak self] completed in
                if completed { self?.onDismissCompleted?() }
            }
        }
        return animator
    }

    func interactionControllerForDismissal(
        using animator: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        guard let interactiveDriver, interactiveDriver.isInteracting else { return nil }
        return interactiveDriver
    }

    // MARK: - Presentation controller

    func presentationController(
        forPresented presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController
    ) -> UIPresentationController? {
        // Always vend a controller so the presenting view stays in the hierarchy
        // (cover / scale transitions reveal it). Dimming is optional.
        let controller = App8DimmingPresentationController(
            presentedViewController: presented,
            presenting: presenting,
            dimming: resolved.dimming,
            presentation: resolved.presentation,
            interactive: resolved.interactive
        )
        controller.onBackdropTap = { [weak self] in self?.requestDismiss?() }
        // A frame-driven sheet plays out its own dismissal, then asks us to clear
        // the modal bookkeeping (no separate animator runs for it).
        controller.onInteractiveDismiss = { [weak self] in self?.onDismissCompleted?() }
        presentationController = controller
        return controller
    }

    // MARK: - Interactive dismiss

    /// Install gesture-driven swipe-to-dismiss on the presented view. Call once
    /// the modal has appeared. No-op when the transition isn't interactive, or
    /// when a sized sheet drives its own frame-based interaction.
    func installInteractiveDismiss(on view: UIView) {
        guard let config = resolved.interactive, config.enabled else { return }
        if presentationController?.usesSheetInteraction == true { return }
        let driver = App8InteractiveTransitionDriver(
            edge: resolved.edge,
            config: config,
            begin: { [weak self] in self?.requestDismiss?() }
        )
        driver.attach(to: view)
        interactiveDriver = driver
    }
}
