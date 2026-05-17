import UIKit

extension DSL.Model.Style {

    struct Text {

        var color: UIColor
        var font: UIFont
        var alignment: NSTextAlignment
        var numberOfLines: Int
        
        /// Warning: modifies alpha of SELF! Do not apply to static properties.
        /// Recommended to use within the `mutated` function argument
        var alpha: CGFloat {
            get {
                color.rgba?.alpha ?? 1.0
            }
            set {
                color = color.withAlphaComponent(newValue)
            }
        }
        
        /// Warning: letter spacing is ignored unless applied to NSAttributedString
        var letterSpacing: CGFloat
        
        /// Warning: line spacing is ignored unless applied to NSAttributedString
        var lineHeight: LineHeight = .auto
        
        /// Warning: `baselineOffset` is ignored unless applied to NSAttributedString
        var baselineOffset: CGFloat = .zero
        
        var lineSpacing: CGFloat {
            let fontPointSize = font.pointSize
            switch lineHeight {
            case .auto:
                return .zero
            case .fixed(let height):
                return height - fontPointSize
            case .multiplier(let percent):
                return font.lineHeight * (percent - 1.0)
            case .fontSizeFraction(let fraction):
                return fontPointSize * (fraction - 1)
            case .interLineSpacing(let interLineSpacing):
                return interLineSpacing
            }
        }
        
        init(_ color: ColorProvider, _ font: UIFont, _ alignment: NSTextAlignment = .left, _ numberOfLines: Int = 0, letterSpacing: CGFloat = 0.0, lineHeight: LineHeight = .auto) {
            self.color = color.color
            self.font = font
            self.alignment = alignment
            self.numberOfLines = numberOfLines
            self.letterSpacing = letterSpacing
            self.lineHeight = lineHeight
        }
        
        func withFont(_ font: UIFont) -> Self {
            var copy = self.copy()
            copy.font = font
            return copy
        }
        
        func aligning(_ alignment: NSTextAlignment) -> Self {
            var copy = self.copy()
            copy.alignment = alignment
            return copy
        }

        func limitingLines(_ numberOfLines: Int) -> Self {
            var copy = self.copy()
            copy.numberOfLines = numberOfLines
            return copy
        }

        func withLineHeight(_ lineHeight: LineHeight) -> Self {
            var copy = self.copy()
            copy.lineHeight = lineHeight
            return copy
        }

        func withLineHeightEqualToFontSize() -> Self {
            var copy = self.copy()
            copy.lineHeight = .fixed(font.pointSize)
            return copy
        }

        func coloring(_ color: UIColor) -> Self {
            var copy = self.copy()
            copy.color = color
            return copy
        }

        func withAlpha(_ alpha: CGFloat) -> Self {
            var copy = self.copy()
            copy.color = color.withAlphaComponent(alpha)
            return copy
        }

        func coloring(_ color: ColorProvider) -> Self {
            return coloring(color.color)
        }

        @MainActor func adjustingFontSize() -> Self {
            let fontSizeMultiplier: CGFloat = (DDFactor.none.value + DDFactor.default.value) / 2
            let fontSize = font.pointSize * fontSizeMultiplier
            return withFont(font.withSize(fontSize))
        }

        func mutated(_ mutations: (Self) -> Void) -> Self {
            let copy = self.copy()
            mutations(copy)
            return copy
        }

        func mutate(_ mutations: (Self) -> Void) {
            mutations(self)
        }

        func attributes() -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            switch lineHeight {
            case .multiplier(let multiplier):
                paragraph.lineHeightMultiple = multiplier
                break
            case .fontSizeFraction(let fraction):
                paragraph.minimumLineHeight = font.pointSize * fraction
                paragraph.maximumLineHeight = font.pointSize * fraction
            case .fixed(let height):
                paragraph.minimumLineHeight = height
                paragraph.maximumLineHeight = height
                break
            default: break
            }
            if numberOfLines == 1 {
                paragraph.lineBreakMode = .byTruncatingTail
            }
            
            return [
                .font: font,
                .foregroundColor: color,
                .kern: letterSpacing,
                .paragraphStyle: paragraph,
                .baselineOffset : baselineOffset]
        }
        
        func copy() -> Self {
            return .init(color, font, alignment, numberOfLines, letterSpacing: letterSpacing, lineHeight: lineHeight)
        }
    }
}

extension DSL.Model.Style.Text {

    enum LineHeight: Hashable {
        case auto
        case multiplier(CGFloat)
        case fontSizeFraction(CGFloat)
        case fixed(CGFloat)
        case interLineSpacing(CGFloat)
    }
}
