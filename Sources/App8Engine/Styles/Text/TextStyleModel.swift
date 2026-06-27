import UIKit

extension DSL.Model.Style {

    struct TextModel: Decodable, StylePointerResolvable {
        let fontSize: CGFloat
        let fontWeight: Font.Weight?
        let alignment: Alignment?
        let lineHeight: LineHeight?
        let letterSpacing: LetterSpacing?
        let numberOfLines: Int?

        /// How text is truncated/wrapped when it overflows. Defaults to UIKit's
        /// behavior (`.byTruncatingTail`) when omitted.
        let lineBreakMode: LineBreakMode?
        /// Draws a single underline under the text.
        let underline: Bool?
        /// Draws a single strikethrough line through the text.
        let strikethrough: Bool?

        /// Shrinks the font to fit the label's width instead of truncating.
        /// Most effective with a constrained `numberOfLines` (e.g. 1).
        let adjustsFontSizeToFitWidth: Bool?

        /// Smallest multiple of the font size autoshrink may use (0–1).
        /// Only consulted when `adjustsFontSizeToFitWidth` is true; without it
        /// UILabel won't shrink at all. Defaults to 0.5 when omitted.
        let minimumScaleFactor: CGFloat?

        /// Flat shortcut for a registered font's PostScript name. Wins over
        /// `font.family.displayName` when set. Use this for simple "just give
        /// me this exact custom font" cases; use `font` when the DSL needs to
        /// describe a full family (foundry, license, faces, variable axes).
        let fontFamily: String?

        @Wrapped var color: Color.Themed?
        @Wrapped var font: DSL.Model.Style.Font?
        
        mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
            _color.resolvePointer(type: .key(.color), resolver: resolver)
            _font.resolvePointer(type: .key(.font), resolver: resolver)
        }
        
        func isResolved() -> Bool {
            return [
                color?.isResolved() ?? false,
                font.isNotNil
            ].allSatisfy { $0 }
        }

        func unresolvedPointerIds() -> [String] {
            _color.unresolvedPointerIds() + _font.unresolvedPointerIds()
        }
        
        struct LineHeight: Decodable {
            let type: `Type`
            let value: CGFloat

            enum `Type`: String, Decodable {
                case auto
                case multiplier
                case fontSizeFraction
                case fixed
                case interLineSpacing
            }
        }

        struct LetterSpacing: Decodable {
            let type: `Type`
            let value: CGFloat

            enum `Type`: String, Decodable {
                case auto
                case fixed
            }

            init(type: `Type`, value: CGFloat) {
                self.type = type
                self.value = value
            }

            private enum CodingKeys: String, CodingKey { case type, value }

            init(from decoder: any Decoder) throws {
                // Shorthand: a bare number is fixed letter spacing in points
                // (`"letterSpacing": -1.5` ⇒ `{ "type": "fixed", "value": -1.5 }`).
                if let single = try? decoder.singleValueContainer(),
                   let number = try? single.decode(CGFloat.self) {
                    self.type = .fixed
                    self.value = number
                    return
                }
                // Object form: `{ "type": "fixed" | "auto", "value": <number> }`.
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.type = try c.decode(`Type`.self, forKey: .type)
                self.value = (try c.decodeIfPresent(CGFloat.self, forKey: .value)) ?? 0
            }
        }

        enum Alignment: Int, Codable {
            case left, center, right, justified, natural
        }

        /// Author-facing line-break modes mapped to `NSLineBreakMode`.
        enum LineBreakMode: String, Decodable {
            case wordWrap, charWrap, clip
            case truncateHead, truncateTail, truncateMiddle

            var ui: NSLineBreakMode {
                switch self {
                case .wordWrap:        return .byWordWrapping
                case .charWrap:        return .byCharWrapping
                case .clip:            return .byClipping
                case .truncateHead:    return .byTruncatingHead
                case .truncateTail:    return .byTruncatingTail
                case .truncateMiddle:  return .byTruncatingMiddle
                }
            }
        }
    }
}

extension DSL.Model.Style.TextModel {

    /// Resolves the UIFont for this text style. Lookup order:
    /// 1. `fontFamily` (PostScript name) — exact name registered with the process font manager.
    /// 2. `font.family.displayName` when `isSystemFont == false`.
    /// 3. Fallback: `UIFont.systemFont(ofSize:weight:)` using `fontWeight`.
    func resolveUIFont() -> UIFont {
        let weight = fontWeight?.uiFontWeight ?? .regular
        if let name = fontFamily, let custom = UIFont(name: name, size: fontSize) {
            return custom
        }
        if let family = font?.family, family.isSystemFont == false,
           let custom = UIFont(name: family.displayName, size: fontSize) {
            return custom
        }
        return UIFont.systemFont(ofSize: fontSize, weight: weight)
    }
}
