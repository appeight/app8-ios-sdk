import UIKit

extension DSL.Model.Style {

    struct Label: Decodable, BaseStyleProtocol, StylePointerResolvable {
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        @Alpha var alpha: CGFloat?
        let transform: View.Transform?
        @Wrapped var text: TextModel?

        mutating func resolveStylePointers(resolver: (String) -> (any Entity)?) {
            _material.resolvePointer(type: .key(.material), resolver: resolver)
            _text.resolvePointer(type: .key(.text), resolver: resolver)
        }

        func isResolved() -> Bool {
            (material?.isResolved() ?? true) && (text?.isResolved() ?? true)
        }
    }
}

extension DSL.Model.Style.Label: DSL.Model.Style.AlphaExpressionHolder {
    var alphaSlot: DSL.Model.Style.Alpha {
        get { _alpha }
        set { _alpha = newValue }
    }
}
