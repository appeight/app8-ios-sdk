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

            init(value: String, label: String, icon: String? = nil) {
                self.value = value
                self.label = label
                self.icon = icon
            }

            /// Builds an option from an expression result element: a
            /// `{value, label, icon}` object, or a bare scalar (value = label).
            init?(any raw: Any) {
                func string(_ v: Any?) -> String? {
                    switch v {
                    case let s as String: return s
                    case let b as Bool: return b ? "true" : "false"
                    case let n as NSNumber:
                        let d = n.doubleValue
                        return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
                    default: return nil
                    }
                }
                if let dict = raw as? [String: Any] {
                    guard let value = string(dict["value"]) ?? string(dict["label"]) else { return nil }
                    self.init(value: value, label: string(dict["label"]) ?? value, icon: dict["icon"] as? String)
                } else if let value = string(raw) {
                    self.init(value: value, label: value)
                } else {
                    return nil
                }
            }

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
            /// `options` written as an expression (`"{{item.variants}}"`) giving
            /// an array of `{value, label}` objects. Resolved at runtime.
            let optionsExpression: String?
            /// With an object variable in `bindVariable`: the key the selection
            /// is written under. Supports expressions (`"{{item.handle}}"`).
            let bindKey: String?
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
                case options, selectedValue, bindVariable, bindKey, displayMode, placeholder, isEnabled
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                if let expression = try? c.decodeIfPresent(String.self, forKey: .options) {
                    options = nil
                    optionsExpression = expression
                } else {
                    options = try c.decodeIfPresent([Option].self, forKey: .options)
                    optionsExpression = nil
                }
                bindKey = try c.decodeIfPresent(String.self, forKey: .bindKey)
                selectedValue = try c.decodeIfPresent(String.self, forKey: .selectedValue)
                bindVariable = try c.decodeIfPresent(String.self, forKey: .bindVariable)
                displayMode = try c.decodeIfPresent(DisplayMode.self, forKey: .displayMode)
                placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
                isEnabled = try c.decodeIfPresent(String.self, forKey: .isEnabled)
            }
        }
    }
}
