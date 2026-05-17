import UIKit

extension DSL.Model.Style {

    struct TextModel: Decodable, StylePointerResolvable {
        let fontSize: CGFloat
        let fontWeight: Font.Weight?
        let alignment: Alignment?
        let lineHeight: LineHeight?
        let letterSpacing: LetterSpacing?
        let numberOfLines: Int?

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
        }

        enum Alignment: Int, Codable {
            case left, center, right, justified, natural
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
