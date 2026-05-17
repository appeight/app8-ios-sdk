import UIKit

extension CGRect {
    func outsetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        insetBy(dx: -dx, dy: -dy)
    }
}
