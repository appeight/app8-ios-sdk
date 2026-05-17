import UIKit

extension UIView {

    /// Remove from superview, optionally animating a mutation block first.
    func rfs(animatables: ((UIView?) -> Void)? = nil, animated: Bool = false, duration: TimeInterval = 0.25) {
        if animated {
            UIView.animate(
                withDuration: duration,
                delay: .zero,
                options: .curveEaseOut,
                animations: { [weak self] in animatables?(self) },
                completion: { _ in self.removeFromSuperview() }
            )
        } else {
            animatables?(self)
            removeFromSuperview()
        }
    }
}
