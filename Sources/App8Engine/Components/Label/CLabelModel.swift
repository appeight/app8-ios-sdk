extension DSL.Model.Component {

    struct Label {
        typealias C = Content<Label.Properties, DSL.Model.Style.Label>
        typealias Entity = ConcreteEntity<C>

        struct Properties: Decodable {
            let text: String
            /// Dynamic background color — accepts the bare expression form or
            /// the wrapped `{ value, animation }` form for per-property animation.
            let backgroundColor: DSL.Model.AnimatedValue<String>?
            /// Dynamic visibility — supports expressions like "{{!isChecked}}"
            let isHidden: String?
            /// Number of lines (0 = unlimited)
            let numberOfLines: Int?
            /// Per-character-range style overrides on top of the base text style.
            /// Used for inline rich text (e.g. a swashed first letter, a colored
            /// keyword inside a sentence) without splitting into sibling labels.
            let spans: [Span]?

            private enum CodingKeys: String, CodingKey {
                case text, backgroundColor, isHidden, numberOfLines, spans
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
                backgroundColor = try c.decodeIfPresent(DSL.Model.AnimatedValue<String>.self, forKey: .backgroundColor)
                isHidden = try c.decodeIfPresent(String.self, forKey: .isHidden)
                numberOfLines = try c.decodeIfPresent(Int.self, forKey: .numberOfLines)
                spans = try c.decodeIfPresent([Span].self, forKey: .spans)
            }

            /// Inline style override for a character range on a label.
            /// `from` is inclusive, `to` is exclusive. Indices are UTF-16
            /// offsets — for ASCII / BMP-only text these match `text.count`.
            /// Out-of-range indices are clamped silently at render time.
            struct Span: Decodable {
                let from: Int
                let to: Int
                let fontFamily: String?
                let color: String?
            }
        }
    }
}
