//
//  CShimmerModel.swift
//  App8Engine
//

import Foundation

extension DSL.Model.Component {

    struct Shimmer {
        typealias C = Content<Shimmer.Properties, DSL.Model.Style.View>
        typealias Entity = ConcreteEntity<C>

        enum Direction: String, Decodable, Sendable {
            case leftToRight, rightToLeft, topToBottom
        }

        struct Properties: Decodable, Sendable {
            /// Whether shimmer animation is active. Expression: "{{isLoading}}"
            let isAnimating: String?
            /// Duration of one shimmer pass in seconds. Default: 1.5
            let duration: Double?
            /// Shimmer direction. Default: leftToRight
            let direction: Direction?

            private enum CodingKeys: String, CodingKey {
                case isAnimating, duration, direction
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                isAnimating = try c.decodeIfPresent(String.self, forKey: .isAnimating)
                duration = try c.decodeIfPresent(Double.self, forKey: .duration)
                direction = try c.decodeIfPresent(Direction.self, forKey: .direction)
            }
        }
    }
}
