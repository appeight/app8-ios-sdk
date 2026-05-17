import UIKit

extension DSL.Model.Style {

    struct Collection: Decodable, BaseStyleProtocol, StylePointerResolvable, Sendable {
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        let alpha: CGFloat?
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
