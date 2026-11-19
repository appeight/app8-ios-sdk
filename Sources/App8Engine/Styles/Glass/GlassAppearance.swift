import UIKit

extension DSL.Model.Style {
    /// `style.glassAppearance` (styles.md, "Adaptive glass"): glass follows the
    /// content behind it (`auto`, the default) or is pinned light or dark.
    /// An unknown value is `auto`.
    enum GlassAppearance: String, Decodable, Sendable {
        case auto, light, dark

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = GlassAppearance(rawValue: raw) ?? .auto
        }

        /// The interface style that pins the glass (`.unspecified`: adaptive).
        var interfaceStyle: UIUserInterfaceStyle {
            switch self {
            case .auto: return .unspecified
            case .light: return .light
            case .dark: return .dark
            }
        }
    }
}

/// Adaptive glass below iOS 26 (no system Liquid Glass): the luminance of
/// what is drawn behind a view, sampled from the window, and a light or dark
/// blur chosen from it with hysteresis so it does not flicker while content
/// scrolls past. iOS 26's `UIGlassEffect` adapts on its own.
@MainActor
enum BackdropLuminance {
    /// Dark below this relative luminance, light above `lightAbove`; in between
    /// the current choice holds (same thresholds as the web renderer).
    static let darkBelow: CGFloat = 0.14
    static let lightAbove: CGFloat = 0.24

    /// The next "is dark" for sampled luminance `l`, from the current one.
    static func nextDark(current: Bool?, luminance l: CGFloat) -> Bool {
        guard let current else { return l < (darkBelow + lightAbove) / 2 }
        return current ? l < lightAbove : l < darkBelow
    }

    /// Relative luminance of an sRGB colour (components 0…1).
    static func luminance(r: CGFloat, g: CGFloat, b: CGFloat) -> CGFloat {
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// Mean relative luminance of an image's pixels (drawn into RGBA first,
    /// whatever its own pixel format).
    static func meanLuminance(_ image: CGImage) -> CGFloat? {
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var sum: CGFloat = 0
        for i in 0..<(w * h) {
            sum += luminance(r: CGFloat(pixels[i * 4]) / 255, g: CGFloat(pixels[i * 4 + 1]) / 255, b: CGFloat(pixels[i * 4 + 2]) / 255)
        }
        return sum / CGFloat(w * h)
    }

    /// Mean luminance of the window's content behind `view` (the view itself
    /// left out), or nil off screen. Renders the window's model layer tree
    /// into an 8 × 4 bitmap; hiding the view for that render commits nothing.
    static func sample(behind view: UIView) -> CGFloat? {
        guard let window = view.window, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        let rect = view.convert(view.bounds, to: window)
        let w = 8, h = 4
        // The context owns its buffer: `&array` would only be valid during the
        // initializer, and the render would land elsewhere (always black).
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: CGFloat(w) / rect.width, y: -CGFloat(h) / rect.height)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        let wasHidden = view.isHidden
        view.isHidden = true
        window.layer.render(in: ctx)
        view.isHidden = wasHidden
        guard let data = ctx.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var sum: CGFloat = 0
        for i in 0..<(w * h) {
            sum += luminance(r: CGFloat(pixels[i * 4]) / 255, g: CGFloat(pixels[i * 4 + 1]) / 255, b: CGFloat(pixels[i * 4 + 2]) / 255)
        }
        return sum / CGFloat(w * h)
    }
}
