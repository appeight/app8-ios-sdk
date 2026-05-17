//
//  CSliderModel.swift
//  App8Engine
//

import Foundation

extension DSL.Model.Component {

    struct Slider {
        typealias C = Content<Slider.Properties, DSL.Model.Style.Slider>
        typealias Entity = ConcreteEntity<C>

        struct Properties: Decodable, Sendable {
            /// Current value. Supports expressions: "{{volume}}"
            let value: String?
            /// Minimum value. Default: 0
            let minimumValue: Float?
            /// Maximum value. Default: 1
            let maximumValue: Float?
            /// Optional step size for snapping
            let step: Float?
            /// Variable name for two-way binding
            let bindVariable: String?
            /// Whether the slider is enabled. Supports expressions.
            let isEnabled: String?

            private enum CodingKeys: String, CodingKey {
                case value, minimumValue, maximumValue, step, bindVariable, isEnabled
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                value = try c.decodeIfPresent(String.self, forKey: .value)
                minimumValue = try c.decodeIfPresent(Float.self, forKey: .minimumValue)
                maximumValue = try c.decodeIfPresent(Float.self, forKey: .maximumValue)
                step = try c.decodeIfPresent(Float.self, forKey: .step)
                bindVariable = try c.decodeIfPresent(String.self, forKey: .bindVariable)
                isEnabled = try c.decodeIfPresent(String.self, forKey: .isEnabled)
            }
        }
    }
}
