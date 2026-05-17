// TODO: Add scroll indicators, bounce, paging configuration.

import UIKit

extension DSL.Model.Style {

    struct ScrollView: Decodable, BaseStyleProtocol, StylePointerResolvable {
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        let alpha: CGFloat?
        let transform: View.Transform?

        mutating func resolveStylePointers(resolver: (String) -> (any Entity)?) {
            _material.resolvePointer(type: .key(.material), resolver: resolver)
        }

        func isResolved() -> Bool {
            material?.isResolved() ?? true
        }
    }
}
