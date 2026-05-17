import UIKit

extension DSL.Model.Style {

    struct Icon: Decodable, BaseStyleProtocol, StylePointerResolvable {
        let contentMode: View.ContentMode?
        @Wrapped var material: Material?
        let alpha: CGFloat?
        let transform: View.Transform?

        @Wrapped var tint: Color.Themed?
        let renderingMode: Icon.RenderingMode?

        let fontId: String?
        let symbolFontSize: CGFloat?

        @Wrapped var color: Color.Themed?
        @Wrapped var hierarchicalColor: Color.Themed?

        /// Decoded from the `"icon"` key — enables the named-style pointer pattern:
        /// `"style": { "icon": { "id": "myIconStyle", "type": "icon" } }`
        private var iconPointer: `Any`?

        private enum CodingKeys: String, CodingKey {
            case contentMode, material, alpha, transform
            case tint, renderingMode, fontId, symbolFontSize
            case color, hierarchicalColor
            case iconPointer = "icon"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            contentMode        = try c.decodeIfPresent(View.ContentMode.self, forKey: .contentMode)
            _material          = try c.decode(Wrapped<Material>.self, forKey: .material)
            alpha              = try c.decodeIfPresent(CGFloat.self, forKey: .alpha)
            transform          = try c.decodeIfPresent(View.Transform.self, forKey: .transform)
            _tint              = try c.decode(Wrapped<Color.Themed>.self, forKey: .tint)
            renderingMode      = try c.decodeIfPresent(RenderingMode.self, forKey: .renderingMode)
            fontId             = try c.decodeIfPresent(String.self, forKey: .fontId)
            symbolFontSize     = try c.decodeIfPresent(CGFloat.self, forKey: .symbolFontSize)
            _color             = try c.decode(Wrapped<Color.Themed>.self, forKey: .color)
            _hierarchicalColor = try c.decode(Wrapped<Color.Themed>.self, forKey: .hierarchicalColor)
            iconPointer        = try c.decodeIfPresent(`Any`.self, forKey: .iconPointer)
        }

        mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
            if var ref = iconPointer {
                // Called twice: first resolves the top-level pointer → entity,
                // second recurses into the entity's nested color/material pointers.
                ref.resolveStylePointers(resolver: resolver)
                ref.resolveStylePointers(resolver: resolver)
                iconPointer = ref
                let resolved: ConcreteEntity<Icon>? = ref.asConcreteEntity()
                if let resolved {
                    self = resolved.content
                    return
                }
            }

            _material.resolvePointer(type: .key(.material), resolver: resolver)
            _color.resolvePointer(type: .key(.color), resolver: resolver)
            _tint.resolvePointer(type: .key(.color), resolver: resolver)
            _hierarchicalColor.resolvePointer(type: .key(.color), resolver: resolver)
        }

        func isResolved() -> Bool {
            (iconPointer?.asPointer() == nil) && (material?.isResolved() ?? true)
        }

        func unresolvedPointerIds() -> [String] {
            (iconPointer?.unresolvedPointerIds() ?? []) +
            _material.unresolvedPointerIds() +
            _tint.unresolvedPointerIds() +
            _color.unresolvedPointerIds() +
            _hierarchicalColor.unresolvedPointerIds()
        }

        enum RenderingMode: String, Decodable {
            case original, template

            var ui: UIImage.RenderingMode {
                switch self {
                case .original:
                    return .alwaysOriginal
                case .template:
                    return .alwaysTemplate
                }
            }
        }
    }
}
