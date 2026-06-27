import UIKit

extension DSL.Model {

    /// Universal accessibility metadata, declared per component under
    /// `content.accessibility`. Applies to **every** component type. The engine
    /// already sets `accessibilityIdentifier` from `component.id`; this exposes
    /// the VoiceOver-facing properties an author needs to control.
    ///
    /// String fields carry a literal or `{{expression}}` and resolve reactively.
    /// `traits` is a static list of trait names.
    struct Accessibility: Decodable, Sendable {
        /// Spoken label (string expression). Overrides the default.
        let label: String?
        /// Spoken hint (string expression).
        let hint: String?
        /// Spoken value (string expression), e.g. a slider's current value.
        let value: String?
        /// Accessibility traits, e.g. `["button", "header"]`.
        let traits: [Trait]?
        /// `isAccessibilityElement` override (bool expression).
        let isElement: String?
        /// `accessibilityElementsHidden` override (bool expression).
        let hidden: String?

        var hasBindings: Bool {
            label != nil || hint != nil || value != nil
                || traits != nil || isElement != nil || hidden != nil
        }

        /// Author-facing accessibility trait names mapped to `UIAccessibilityTraits`.
        enum Trait: String, Decodable, Sendable {
            case button, link, header, image, selected, notEnabled = "disabled"
            case adjustable, search = "searchField", staticText, summaryElement
            case updatesFrequently, startsMediaSession, allowsDirectInteraction

            var uiTrait: UIAccessibilityTraits {
                switch self {
                case .button:                   return .button
                case .link:                     return .link
                case .header:                   return .header
                case .image:                    return .image
                case .selected:                 return .selected
                case .notEnabled:               return .notEnabled
                case .adjustable:               return .adjustable
                case .search:                   return .searchField
                case .staticText:               return .staticText
                case .summaryElement:           return .summaryElement
                case .updatesFrequently:        return .updatesFrequently
                case .startsMediaSession:       return .startsMediaSession
                case .allowsDirectInteraction:  return .allowsDirectInteraction
                }
            }
        }

        /// Combined `UIAccessibilityTraits` from the declared `traits` list.
        var combinedTraits: UIAccessibilityTraits? {
            guard let traits, !traits.isEmpty else { return nil }
            return traits.reduce(into: UIAccessibilityTraits.none) { $0.insert($1.uiTrait) }
        }
    }
}
