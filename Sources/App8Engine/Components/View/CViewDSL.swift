import Foundation

extension DSL.Model.Component {

    struct View {

        typealias Entity = ConcreteEntity<C>

        typealias C = Content<View.Properties, Style.View>

        struct Properties: CustomDecodable {
            /// Dynamic background color - supports expressions like "{{item.color}}".
            /// Accepts the bare expression form or the wrapped `{ value, animation }` form.
            private(set) var backgroundColor: DSL.Model.AnimatedValue<String>?

            /// Corner radius for the background
            private(set) var cornerRadius: CGFloat?

            /// Dynamic transform scale - supports expressions like "{{max(0.5, min(1, 1 - scrollY / 200))}}".
            /// Accepts the bare expression form or the wrapped `{ value, animation }` form.
            private(set) var transformScale: DSL.Model.AnimatedValue<String>?

            /// Dynamic transform translateX - supports expressions like "{{scrollY * 0.5}}".
            /// Accepts the bare expression form or the wrapped `{ value, animation }` form.
            private(set) var transformTranslateX: DSL.Model.AnimatedValue<String>?

            /// Dynamic transform translateY - supports expressions like "{{min(0, -scrollY * 0.3)}}".
            /// Accepts the bare expression form or the wrapped `{ value, animation }` form.
            private(set) var transformTranslateY: DSL.Model.AnimatedValue<String>?

            /// Dynamic visibility - supports expressions like "{{badge == null}}"
            private(set) var isHidden: String?

            /// Dynamic alpha - supports expressions like "{{min(1, max(0, 1 - scrollY / 80))}}".
            /// Accepts the bare expression form or the wrapped `{ value, animation }` form.
            private(set) var alpha: DSL.Model.AnimatedValue<String>?

            static func decode<CodingKeys: CodingKey>(fromContainer container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Self {
                if container.contains(key) {
                    return try container.decode(Self.self, forKey: key)
                } else {
                    return .init()
                }
            }
        }
    }
}
