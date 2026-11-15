import Foundation

extension DSL.Model {

    /// Author-declared analytics binding on a component:
    ///
    /// ```json
    /// "analytics": {
    ///   "tap": "stripe_connect_clicked"
    /// }
    /// ```
    /// or
    /// ```json
    /// "analytics": {
    ///   "tap": { "name": "stripe_connect_clicked", "properties": { "source": "{{source}}" } }
    /// }
    /// ```
    ///
    /// Decodes either form into the same struct. `properties` values support
    /// `{{var}}` interpolation in string positions; non-string scalars pass
    /// through unchanged.
    struct AnalyticsBinding: Decodable, Sendable {
        let name: String
        let properties: [String: AnyCodableValue]?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let shorthand = try? container.decode(String.self) {
                self.name = shorthand
                self.properties = nil
                return
            }
            let full = try container.decode(Full.self)
            self.name = full.name
            self.properties = full.properties
        }

        private struct Full: Decodable {
            let name: String
            let properties: [String: AnyCodableValue]?
        }
    }
}

extension DSL.Model {

    /// Single `Action` or an array of `Action`s under one trigger key. Lets
    /// JSON authors chain multiple effects on one trigger (e.g. emit + navigate)
    /// without changing the action-type system itself.
    struct ActionList: Decodable, Sendable {
        let actions: [Action]

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            do {
                self.actions = try container.decode([Action].self)
                return
            } catch {
                // An array whose element fails: report that element's error
                // (its real path), not "expected an object, found array".
                if (try? container.decode([AnyCodableValue].self)) != nil { throw error }
            }
            let single = try container.decode(Action.self)
            self.actions = [single]
        }

        init(_ actions: [Action]) {
            self.actions = actions
        }
    }
}
