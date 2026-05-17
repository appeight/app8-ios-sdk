//
//  CToggleModel.swift
//  App8Engine
//

import Foundation

extension DSL.Model.Component {

    struct Toggle {
        typealias C = Content<Toggle.Properties, DSL.Model.Style.Toggle>
        typealias Entity = ConcreteEntity<C>

        struct Properties: Decodable, Sendable {
            /// Current on/off state. Supports expressions: "{{darkMode}}"
            let isOn: String?
            /// Variable name for two-way binding
            let bindVariable: String?
            /// Whether the toggle is enabled. Supports expressions.
            let isEnabled: String?

            private enum CodingKeys: String, CodingKey {
                case isOn, bindVariable, isEnabled
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                isOn = try c.decodeIfPresent(String.self, forKey: .isOn)
                bindVariable = try c.decodeIfPresent(String.self, forKey: .bindVariable)
                isEnabled = try c.decodeIfPresent(String.self, forKey: .isEnabled)
            }
        }
    }
}
