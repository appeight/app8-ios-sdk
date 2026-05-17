import UIKit

extension DSL.Model.Style {

    struct Label: Decodable, BaseStyleProtocol, StylePointerResolvable {
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        let alpha: CGFloat?
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
