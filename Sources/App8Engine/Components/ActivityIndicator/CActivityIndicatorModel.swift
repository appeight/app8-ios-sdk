import Foundation

extension DSL.Model.Component {

    struct ActivityIndicator {
        typealias C = Content<ActivityIndicator.Properties, DSL.Model.Style.ActivityIndicator>
        typealias Entity = ConcreteEntity<C>

        struct Properties: Decodable, Sendable {
            /// Whether the spinner is animating. Supports expressions: "{{isLoading}}"
            let isAnimating: String?
            /// Whether the indicator hides when stopped. Default: true
            let hidesWhenStopped: Bool?

            private enum CodingKeys: String, CodingKey {
                case isAnimating, hidesWhenStopped
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                isAnimating = try c.decodeIfPresent(String.self, forKey: .isAnimating)
                hidesWhenStopped = try c.decodeIfPresent(Bool.self, forKey: .hidesWhenStopped)
            }
        }
    }
}
