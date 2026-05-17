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
    }
}
