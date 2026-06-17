import UIKit

extension DSL.Model.Style {

    struct Button: Decodable, BaseStyleProtocol, StylePointerResolvable {
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        let alpha: CGFloat?
        let transform: View.Transform?
        @Wrapped var text: TextModel?
        /// Native `UIButton.Configuration` styling. When present, the button renders
        /// via the system configuration path instead of the Material path.
        @Wrapped var system: SystemButton?

        mutating func resolveStylePointers(resolver: (String) -> (any Entity)?) {
            _material.resolvePointer(type: .key(.material), resolver: resolver)
            _text.resolvePointer(type: .key(.text), resolver: resolver)
            _system.resolvePointer(type: .key(.systemButton), resolver: resolver)
        }

        func isResolved() -> Bool {
            (material?.isResolved() ?? true)
                && (text?.isResolved() ?? true)
                && (system?.isResolved() ?? true)
        }
    }
}
