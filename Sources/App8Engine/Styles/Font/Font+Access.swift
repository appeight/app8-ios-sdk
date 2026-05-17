import UIKit

extension DSL.Model.Style.Font {

    static func system(_ size: CGFloat, _ weight: UIFont.Weight, italic: Bool = false) -> UIFont {
        return getSystem(size: size, weight: weight, italic: italic)
    }

    static func getSync(_ familyName: String, _ size: CGFloat, _ weight: UIFont.Weight, italic: Bool = false) -> UIFont {
        let font = Self.get(familyName: familyName, size: size, weight: weight, italic: italic)
        return font ?? system(size, weight)
    }
}

// MARK: Font family

public protocol FontFamilyProtocol {
    func font(forWeight weight: UIFont.Weight, size: CGFloat, italic: Bool) -> UIFont?
}

// MARK: Cache

extension DSL.Model.Style.Font {

    private static let cache = Cache<Int, UIFont>()

    private static func getSystem(size: CGFloat, weight: UIFont.Weight, italic: Bool = false) -> UIFont {
        if let font = get(familyName: "system", size: size, weight: weight, italic: italic) {
            return font
        } else {
            var hasher = Hasher()
            hasher.combine(size)
            hasher.combine(weight)
            hasher.combine(italic)
            hasher.combine("system")
            let hash = hasher.finalize()
            var font = UIFont.systemFont(ofSize: size, weight: weight)
            if italic {
                font = font.italic()
            }
            cache[hash] = font
            return font
        }
    }
    
    private static func get(familyName: String, size: CGFloat, weight: UIFont.Weight, italic: Bool = false) -> UIFont? {
        var hasher = Hasher()
        hasher.combine(size)
        hasher.combine(weight)
        hasher.combine(italic)
        hasher.combine(familyName)
        let hash = hasher.finalize()
        if let font = cache[hash] {
            return font
        }
        else if var font = UIFont(name: familyName, size: size) {
            if italic {
                font = font.italic()
            }
            cache[hash] = font
            return font
        }
        return nil
    }
}

// MARK: - FontProvider

extension DSL.Model.Style.Font {

    public protocol Provider {
        var font: UIFont { get }
    }
}

extension UIFont: DSL.Model.Style.Font.Provider {
    public var font: UIFont { return self }
}
