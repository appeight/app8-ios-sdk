import UIKit

extension DSL.Model {

    /// Component state definition with optional overrides.
    /// `animation` is a `DSL.Model.Animation` reference (inline or pointer).
    struct State<Properties: Decodable & Sendable, Style: Decodable & Sendable>: StateProtocol {
        /// Properties override - nil means keep base properties, explicit value overrides
        let properties: Properties?
        var style: Style?
        let layout: Layout?
        let childStates: [String: String]?
        let animation: Animation?
        /// `properties.isHidden` of this state (any component type).
        let hiddenFlag: String?

        private enum CodingKeys: String, CodingKey {
            case properties, style, layout, childStates, animation
        }

        private enum PropertyKeys: String, CodingKey { case isHidden }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            hiddenFlag = HiddenFlagDecoding.decode(from: c, propertiesKey: .properties)
            do {
                properties = try c.decodeIfPresent(Properties.self, forKey: .properties)
            } catch {
                // A state that only toggles `isHidden` (`"properties": { "isHidden": true }`)
                // need not satisfy the component's own required properties.
                let keys = (try? c.nestedContainer(keyedBy: AnyStateKey.self, forKey: .properties))?.allKeys.map(\.stringValue)
                guard hiddenFlag != nil, keys == ["isHidden"] else { throw error }
                properties = nil
            }
            style = try c.decodeIfPresent(Style.self, forKey: .style)
            layout = try c.decodeIfPresent(Layout.self, forKey: .layout)
            childStates = try c.decodeIfPresent([String: String].self, forKey: .childStates)
            animation = try c.decodeIfPresent(Animation.self, forKey: .animation)
        }
    }

    private struct AnyStateKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
