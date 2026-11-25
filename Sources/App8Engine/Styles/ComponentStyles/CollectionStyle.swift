import UIKit

extension DSL.Model.Style {

    struct Collection: Decodable, BaseStyleProtocol, StylePointerResolvable, Sendable {
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        @Alpha var alpha: CGFloat?
        let transform: View.Transform?

        let backgroundColor: String?
        let separatorColor: String?
        let separatorInset: CGFloat?

        mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
            _material.resolvePointer(type: .key(.material), resolver: resolver)
        }

        func isResolved() -> Bool {
            material?.isResolved() ?? true
        }
    }
}

extension DSL.Model.Style.Collection: DSL.Model.Style.AlphaExpressionHolder {
    var alphaSlot: DSL.Model.Style.Alpha {
        get { _alpha }
        set { _alpha = newValue }
    }
}
