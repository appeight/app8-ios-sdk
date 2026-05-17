import UIKit

extension UIFont {

    func withTraits(traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        // `withSymbolicTraits` is nil when the font can't apply the trait.
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        // size 0 means keep the size as it is
        return UIFont(descriptor: descriptor, size: 0)
    }

    func bold() -> UIFont {
        return withTraits(traits: .traitBold)
    }

    func italic() -> UIFont {
        return withTraits(traits: .traitItalic)
    }

    var weight: UIFont.Weight? {
        let attributes = fontDescriptor.fontAttributes
        let traits = (attributes[.traits] as? [UIFontDescriptor.TraitKey: Any]) ?? [:]
        if let weight = traits[.weight] as? CGFloat {
            return UIFont.Weight(rawValue: weight)
        } else {
            return nil
        }
    }
}
