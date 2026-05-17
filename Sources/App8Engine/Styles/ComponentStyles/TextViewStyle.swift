import UIKit

extension DSL.Model.Style {

    struct TextView: Decodable, BaseStyleProtocol, StylePointerResolvable, MergeableStyle {

        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        let alpha: CGFloat?
        let transform: View.Transform?

        @Wrapped var text: TextModel?
        @Wrapped var placeholder: TextModel?
        @Wrapped var tintColor: Color.Themed?

        /// Content padding. Defaults: top=12, left=12, bottom=12, right=12.
        let padding: DSL.Model.EdgeInsets?

        mutating func resolveStylePointers(resolver: (String) -> (any Entity)?) {
            _material.resolvePointer(type: .key(.material), resolver: resolver)
            _text.resolvePointer(type: .key(.text), resolver: resolver)
            _placeholder.resolvePointer(type: .key(.text), resolver: resolver)
            _tintColor.resolvePointer(type: .key(.color), resolver: resolver)
        }

        func isResolved() -> Bool {
            (material?.isResolved() ?? true) &&
            (text?.isResolved() ?? true) &&
            (placeholder?.isResolved() ?? true) &&
            (tintColor?.isResolved() ?? true)
        }

        /// Uses self's properties where present, falling back to `base`.
        func merging(withBase base: Any) -> TextView? {
            guard var base = base as? TextView else { return nil }
            if _material.base != nil { base._material = _material }
            if _text.base != nil { base._text = _text }
            if _placeholder.base != nil { base._placeholder = _placeholder }
            if _tintColor.base != nil { base._tintColor = _tintColor }
            return base
        }
    }
}
