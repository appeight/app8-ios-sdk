import UIKit

extension DSL.Model.Style {

    struct PageControl: Decodable, BaseStyleProtocol, StylePointerResolvable {
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        @Alpha var alpha: CGFloat?
        let transform: View.Transform?

        /// Tint color for inactive page dots
        let pageIndicatorTintColor: String?
        /// Tint color for the active page dot
        let currentPageIndicatorTintColor: String?

        mutating func resolveStylePointers(resolver: (String) -> (any Entity)?) {
            _material.resolvePointer(type: .key(.material), resolver: resolver)
        }

        func isResolved() -> Bool {
            material?.isResolved() ?? true
        }
    }
}

extension DSL.Model.Style.PageControl: DSL.Model.Style.AlphaExpressionHolder {
    var alphaSlot: DSL.Model.Style.Alpha {
        get { _alpha }
        set { _alpha = newValue }
    }
}
