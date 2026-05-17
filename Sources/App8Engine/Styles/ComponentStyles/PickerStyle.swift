import UIKit

extension DSL.Model.Style {

    struct Picker: Decodable, BaseStyleProtocol, StylePointerResolvable {
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        let alpha: CGFloat?
        let transform: View.Transform?

        /// Text style for menu mode button label
        @Wrapped var text: TextModel?

        /// Tint color for the selected segment (segmented mode)
        let selectedSegmentTintColor: String?

        mutating func resolveStylePointers(resolver: (String) -> (any Entity)?) {
            _material.resolvePointer(type: .key(.material), resolver: resolver)
            _text.resolvePointer(type: .key(.text), resolver: resolver)
        }

        func isResolved() -> Bool {
            (material?.isResolved() ?? true) && (text?.isResolved() ?? true)
        }
    }
}
