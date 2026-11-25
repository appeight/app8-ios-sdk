import UIKit

extension DSL.Model.Style {

    /// `style.alpha` of every component style: a number, or an expression
    /// (`"{{ready ? 1 : 0.35}}"`) resolved in the component's scope and
    /// re-evaluated when a variable it reads changes (styles.md, since 0.7.17).
    ///
    /// Before 0.7.17 only a number decoded: an expression failed the style's
    /// decoding, which dropped the component, or failed the whole screen where
    /// the component was not in a lenient list (a bottom bar), and the screen
    /// silently never opened.
    @propertyWrapper
    struct Alpha: Decodable, Sendable {
        /// The number, or the expression's last resolved value (nil until resolved).
        var wrappedValue: CGFloat?
        /// The `{{…}}` expression, resolved per component by `CBaseViewModel`.
        private(set) var expression: String?

        init(wrappedValue: CGFloat?) {
            self.wrappedValue = wrappedValue
            expression = nil
        }

        init(from decoder: any Decoder) throws {
            expression = nil
            wrappedValue = nil
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { return }
            if let number = try? c.decode(Double.self) {
                wrappedValue = CGFloat(number)
            } else if let string = try? c.decode(String.self) {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if let number = Double(trimmed) {
                    wrappedValue = CGFloat(number)
                } else if trimmed.contains("{{") {
                    expression = trimmed
                }
            }
            // Anything else leaves alpha unset; it never fails the style.
        }
    }

    /// A component style whose `alpha` may hold an expression.
    protocol AlphaExpressionHolder {
        var alphaSlot: Alpha { get set }
    }
}

/// A missing `alpha` key decodes as unset (property-wrapper decoding needs this).
extension KeyedDecodingContainer {
    func decode(_ type: DSL.Model.Style.Alpha.Type, forKey key: Key) throws -> DSL.Model.Style.Alpha {
        try decodeIfPresent(type, forKey: key) ?? DSL.Model.Style.Alpha(wrappedValue: nil)
    }
}
