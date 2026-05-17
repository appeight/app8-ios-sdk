import UIKit

extension UIView {

    func cMakeEqualToSuperview() {
        guard let superview else {
            // Programmer-error guard: crashes in DEBUG, no-op in release.
            assertionFailure("No superview for edge constraints: \(self)")
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
