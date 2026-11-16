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

            /// Rotation in degrees, clockwise, about the view's centre: a number
            /// or an expression like "{{ isOpen ? 180 : 0 }}". Accepts the bare
            /// form or the wrapped `{ value, animation }` form (numbers are kept
            /// as their decimal text).
            private(set) var transformRotation: DSL.Model.AnimatedValue<String>?

            /// Dynamic visibility - supports expressions like "{{badge == null}}".
            /// The wrapped `{ value, animation }` form contributes its value here;
            /// the shared binder (`CommonComponentProps`) applies it.
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

extension DSL.Model.Component.View.Properties {
    private enum CodingKeys: String, CodingKey {
        case backgroundColor, cornerRadius, transformScale, transformTranslateX, transformTranslateY, transformRotation, isHidden, alpha
    }

    /// `isHidden` takes a boolean or an expression string, bare or wrapped.
    /// `transformRotation` takes a number or an expression string, bare or wrapped.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        backgroundColor = try c.decodeIfPresent(DSL.Model.AnimatedValue<String>.self, forKey: .backgroundColor)
        cornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius)
        transformScale = try c.decodeIfPresent(DSL.Model.AnimatedValue<String>.self, forKey: .transformScale)
        transformTranslateX = try c.decodeIfPresent(DSL.Model.AnimatedValue<String>.self, forKey: .transformTranslateX)
        transformTranslateY = try c.decodeIfPresent(DSL.Model.AnimatedValue<String>.self, forKey: .transformTranslateY)
        transformRotation = try Self.decodeNumberOrExpression(c, forKey: .transformRotation)
        isHidden = c.decodeFlagIfPresent(forKey: .isHidden)
        alpha = try c.decodeIfPresent(DSL.Model.AnimatedValue<String>.self, forKey: .alpha)
    }

    /// A number-or-expression animated value: the string form as written, a
    /// JSON number as its decimal text.
    private static func decodeNumberOrExpression(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> DSL.Model.AnimatedValue<String>? {
        guard c.contains(key) else { return nil }
        do {
            return try c.decode(DSL.Model.AnimatedValue<String>.self, forKey: key)
        } catch {
            guard let number = try? c.decode(DSL.Model.AnimatedValue<Double>.self, forKey: key) else { throw error }
            return DSL.Model.AnimatedValue(value: String(number.value), animation: number.animation)
        }
    }
}
