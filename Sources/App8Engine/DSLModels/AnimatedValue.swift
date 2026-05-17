import Foundation

extension DSL.Model {

    /// Wraps a value of type `T` with an optional `Animation`. Accepts two JSON
    /// shapes: a bare `T` (legacy, no animation) or `{ "value": ..., "animation": ... }`.
    struct AnimatedValue<T: Decodable & Sendable>: Decodable, Sendable {
        let value: T
        let animation: Animation?

        init(value: T, animation: Animation? = nil) {
            self.value = value
            self.animation = animation
        }

        private enum CodingKeys: String, CodingKey { case value, animation }

        init(from decoder: any Decoder) throws {
            // Detect the wrapped form by the `value` key (`animation` is optional
            // so can't be probed). Otherwise decode T directly.
            if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
               keyed.contains(.value) {
                self.value = try keyed.decode(T.self, forKey: .value)
                self.animation = try keyed.decodeIfPresent(Animation.self, forKey: .animation)
                return
            }

            let single = try decoder.singleValueContainer()
            self.value = try single.decode(T.self)
            self.animation = nil
        }
    }
}
