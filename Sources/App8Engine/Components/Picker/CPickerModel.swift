//
//  CPickerModel.swift
//  App8Engine
//

import Foundation

extension DSL.Model.Component {

    struct Picker {
        typealias C = Content<Picker.Properties, DSL.Model.Style.Picker>
        typealias Entity = ConcreteEntity<C>

        struct Option: Decodable, Sendable {
            let value: String
            let label: String
            /// Optional SF Symbol name
            let icon: String?

            private enum CodingKeys: String, CodingKey {
                case value, label, icon
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                value = try c.decode(String.self, forKey: .value)
                label = try c.decode(String.self, forKey: .label)
                icon = try c.decodeIfPresent(String.self, forKey: .icon)
            }
        }

        enum DisplayMode: String, Decodable, Sendable {
            /// UIMenu context menu (default)
            case menu
            /// UISegmentedControl
            case segmented
        }

        struct Properties: Decodable, Sendable {
            /// Static options
            let options: [Option]?
            /// Current selected value. Supports expressions: "{{selectedColor}}"
            let selectedValue: String?
            /// Variable name for two-way binding
            let bindVariable: String?
            /// Display mode: "menu" (default) or "segmented"
            let displayMode: DisplayMode?
            /// Placeholder text for menu mode
            let placeholder: String?
            /// Whether the picker is enabled. Supports expressions.
            let isEnabled: String?

            private enum CodingKeys: String, CodingKey {
                case options, selectedValue, bindVariable, displayMode, placeholder, isEnabled
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                options = try c.decodeIfPresent([Option].self, forKey: .options)
                selectedValue = try c.decodeIfPresent(String.self, forKey: .selectedValue)
                bindVariable = try c.decodeIfPresent(String.self, forKey: .bindVariable)
                displayMode = try c.decodeIfPresent(DisplayMode.self, forKey: .displayMode)
                placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
                isEnabled = try c.decodeIfPresent(String.self, forKey: .isEnabled)
            }
        }
    }
}
