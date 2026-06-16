// Presentation controller for custom modal transitions. Adds an optional
// backdrop dimming view (faded in/out alongside the transition) and keeps the
// presenting view in the hierarchy so partial-cover transitions reveal it.

import UIKit

@MainActor
final class App8DimmingPresentationController: UIPresentationController {

    private let dimming: DSL.Model.ScreenTransition.ResolvedDimming?

    /// Invoked when the backdrop is tapped (when dimming is present). Wired to
    /// dismiss the modal through the engine's normal path.
    var onBackdropTap: (() -> Void)?

    private lazy var dimmingView: UIView = {
        let view = UIView()
        view.backgroundColor = dimming?.color ?? .black
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackdropTap))
        view.addGestureRecognizer(tap)
        return view
    }()

    init(
        presentedViewController: UIViewController,
        presenting presentingViewController: UIViewController?,
        dimming: DSL.Model.ScreenTransition.ResolvedDimming?
    ) {
        self.dimming = dimming
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        containerView?.bounds ?? .zero
    }

    override func presentationTransitionWillBegin() {
        super.presentationTransitionWillBegin()
        guard let dimming, let containerView else { return }

        dimmingView.frame = containerView.bounds
        dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.insertSubview(dimmingView, at: 0)

        let target = CGFloat(dimming.opacity)
        guard let coordinator = presentedViewController.transitionCoordinator else {
            dimmingView.alpha = target
            return
        }
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.dimmingView.alpha = target
        })
    }

    override func dismissalTransitionWillBegin() {
        super.dismissalTransitionWillBegin()
        guard dimming != nil else { return }
        guard let coordinator = presentedViewController.transitionCoordinator else {
            dimmingView.alpha = 0
            return
        }
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.dimmingView.alpha = 0
        })
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        if let containerView { dimmingView.frame = containerView.bounds }
        presentedView?.frame = frameOfPresentedViewInContainerView
    }

    @objc private func handleBackdropTap() {
        onBackdropTap?()
    }
}
