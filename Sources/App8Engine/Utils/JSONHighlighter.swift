import UIKit

enum JSONHighlighter {

    /**
     Highlights JSON string with syntax coloring.

     - Parameter raw: The raw JSON string to highlight
     - Parameter fontSize: Font size for the monospaced font (default: 11)
     - Parameter textAlpha: Alpha value for the text color (default: 0.7)
     - Returns: An attributed string with syntax highlighting, or nil if parsing fails
     */
    static func highlightedJSON(
        from raw: String?,
        fontSize: CGFloat = 11,
        textAlpha: CGFloat = 0.7
    ) -> NSAttributedString? {
        guard
            let raw,
            let data = raw.data(using: .utf8),
            let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
            let prettyString = String(data: prettyData, encoding: .utf8)
        else {
            return raw.map { NSAttributedString(string: $0) }
        }

        let result = NSMutableAttributedString(string: prettyString)
        let fullRange = NSRange(location: 0, length: result.length)

        result.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), range: fullRange)
        result.addAttribute(.foregroundColor, value: UIColor.white.withAlphaComponent(textAlpha), range: fullRange)

        func color(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
            UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        }

        let keyColor   = color(0xE5C07B) // yellow-ish
        let stringColor = color(0x98C379) // green-ish
        let numberColor = color(0xD19A66) // orange-ish
        let boolColor  = color(0x56B6C2) // cyan-ish
        let nullColor  = color(0x5C6370, alpha: 0.8) // gray

        let regexes: [(NSRegularExpression, UIColor)] = [
            (try! NSRegularExpression(pattern: "\"([^\"]+)\"\\s*:"), keyColor),        // keys
            (try! NSRegularExpression(pattern: ":\\s*\"([^\"]*)\""), stringColor),     // string values
            (try! NSRegularExpression(pattern: ":\\s*(-?\\d+(?:\\.\\d+)?)"), numberColor), // numbers
            (try! NSRegularExpression(pattern: "\\b(true|false)\\b"), boolColor),      // booleans
            (try! NSRegularExpression(pattern: "\\bnull\\b"), nullColor)               // nulls
        ]

        for (regex, color) in regexes {
            for match in regex.matches(in: prettyString, range: fullRange) {
                result.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }

        return result
    }
}
