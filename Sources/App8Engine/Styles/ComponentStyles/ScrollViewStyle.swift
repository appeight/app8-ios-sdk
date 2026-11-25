// TODO: Add scroll indicators, bounce, paging configuration.

import UIKit

extension DSL.Model.Style {

    struct ScrollView: Decodable, BaseStyleProtocol, StylePointerResolvable {
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        @Alpha var alpha: CGFloat?
        let transform: View.Transform?

        mutating func resolveStylePointers(resolver: (String) -> (any Entity)?) {
            _material.resolvePointer(type: .key(.material), resolver: resolver)
        }

        func isResolved() -> Bool {
            material?.isResolved() ?? true
        }
    }
}

extension DSL.Model.Style.ScrollView: DSL.Model.Style.AlphaExpressionHolder {
    var alphaSlot: DSL.Model.Style.Alpha {
        get { _alpha }
        set { _alpha = newValue }
    }
}
