import UIKit

extension DSL.Model.Style {

    public struct Color {
        static let white = UIColor.white
        static let black = UIColor.black

        static func make(hex: String) -> UIColor? {
            return UIColor(withHexString: hex)
        }
    }
}

// MARK: - RGBA

extension DSL.Model.Style.Color {

    struct RGBA {
        let red, green, blue, alpha: CGFloat

        init?(hex: String) {
            let c = Hex(hex)
            red = CGFloat(c.r)
            green = CGFloat(c.g)
            blue = CGFloat(c.b)
            alpha = CGFloat(c.a)
        }
        
        init?(color: UIColor) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
            self.red = r
            self.green = g
            self.blue = b
            self.alpha = a
        }
    }
}

// MARK: - UIColor convenience

extension UIColor {
    
    convenience init(rgba: DSL.Model.Style.Color.RGBA) {
        self.init(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
    }
    
    convenience init?(withHexString hex: String) {
        let c = DSL.Model.Style.Color.Hex(hex)
        self.init(
            red: CGFloat(c.r),
            green: CGFloat(c.g),
            blue: CGFloat(c.b),
            alpha: CGFloat(c.a)
        )
    }
    
    /// Hex string in the form `#RRGGBB` or `#RRGGBBAA`.
    /// Returns `nil` when the colour cannot be expressed in sRGB.
    var hexString: String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }

        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        let ai = Int(round(a * 255))

        return a < 1.0 - .ulpOfOne
            ? String(format: "#%02X%02X%02X%02X", ri, gi, bi, ai)
            : String(format: "#%02X%02X%02X",     ri, gi, bi)
    }
    
    var rgba: DSL.Model.Style.Color.RGBA? {
        .init(color: self)
    }
    
    var debugHexString: String {
        if let hex = hexString {
            return hex
        } else {
            return "Invalid Hex"
        }
    }
}

// MARK: - Color provider

public protocol ColorProvider {
    var color: UIColor { get }
}

extension UIColor: ColorProvider {
    public var color: UIColor { self }
}
