import UIKit

extension UIColor {

    /// algorithm from: http://www.w3.org/WAI/ER/WD-AERT/#color-contrast
    var isLight: Bool {
        guard let components = cgColor.components else { return false }
        let brightness = ((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000
        return brightness >= 0.5
    }
    
    var brightness: CGFloat {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return b }
        return b
    }
    
    /**
     Adjusts luminance of HSL-formatted color by a given value.
        - parameter lumValue: The value to adjust the luminance by, in the range of -1..1.
        - returns: A new color with luminance adjusted by the given value, clamped to range of 0...1.
     */
    func adjustingBrightness(by bValue: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: s, brightness: (b + bValue).clamped(to: 0 ... 1), alpha: a)
    }
    
    func adjustingBrightness(bAdjustment: (CGFloat) -> CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        let adjustedValue = bAdjustment(b).clamped(to: 0 ... 1)
        if adjustedValue == b {
            return self
        } else {
            return UIColor(hue: h, saturation: s, brightness: adjustedValue, alpha: a)
        }
    }
}
