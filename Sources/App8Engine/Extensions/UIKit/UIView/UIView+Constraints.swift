import UIKit

extension UIView {

    func cMakeEqualToSuperview() {
        guard let superview else {
            // No superview yet: nothing to pin to (never trap; a debug host
            // previewing a broken bundle must keep running).
            return
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: superview.topAnchor),
            bottomAnchor.constraint(equalTo: superview.bottomAnchor),
            leadingAnchor.constraint(equalTo: superview.leadingAnchor),
            trailingAnchor.constraint(equalTo: superview.trailingAnchor)
        ])
    }
}
