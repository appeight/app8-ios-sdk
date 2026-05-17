import UIKit

extension DSL.Model.Style {

    struct Map: Decodable, BaseStyleProtocol, StylePointerResolvable, Sendable {
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        let alpha: CGFloat?
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
