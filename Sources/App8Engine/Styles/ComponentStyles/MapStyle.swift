import UIKit

extension DSL.Model.Style {

    struct Map: Decodable, BaseStyleProtocol, StylePointerResolvable, Sendable {
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        @Alpha var alpha: CGFloat?
        let transform: View.Transform?

        let corner: Corner?
        let routeColor: String?
        let routeWidth: CGFloat?
        let annotationTintColor: String?

        mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
            _material.resolvePointer(type: .key(.material), resolver: resolver)
        }

        func isResolved() -> Bool {
            material?.isResolved() ?? true
        }

        func unresolvedPointerIds() -> [String] {
            _material.unresolvedPointerIds()
        }
    }
}

extension DSL.Model.Style.Map: DSL.Model.Style.AlphaExpressionHolder {
    var alphaSlot: DSL.Model.Style.Alpha {
        get { _alpha }
        set { _alpha = newValue }
    }
}
