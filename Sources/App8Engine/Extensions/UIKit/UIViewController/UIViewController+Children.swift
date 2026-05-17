import UIKit

extension UIViewController {

    func embed(_ child: UIViewController, inheritTraitOverrides: Bool = true) {
        addChild(child)
        view.addSubview(child.view)
        if inheritTraitOverrides {
            child.traitOverrides = traitOverrides
        }
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        child.didMove(toParent: self)
    }
}
