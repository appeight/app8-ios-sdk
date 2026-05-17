import Foundation

extension DSL.Model.Component {

    struct DatePicker {
        typealias C = Content<DatePicker.Properties, DSL.Model.Style.DatePicker>
        typealias Entity = ConcreteEntity<C>

        enum Mode: String, Decodable, Sendable {
            case date, time, dateAndTime, countdownTimer
        }

        enum DisplayStyle: String, Decodable, Sendable {
            case compact, inline, wheels
        }

        struct Properties: Decodable, Sendable {
            /// Selected date in ISO8601 or "yyyy-MM-dd" format. Supports expressions.
            let selectedDate: String?
            /// Variable name for two-way binding
            let bindVariable: String?
            /// Picker mode: "date" (default), "time", "dateAndTime", "countdownTimer"
            let datePickerMode: Mode?
            /// Display style: "compact" (default), "inline", "wheels"
            let displayStyle: DisplayStyle?
            /// Minimum selectable date (ISO8601 or "yyyy-MM-dd")
            let minimumDate: String?
            /// Maximum selectable date (ISO8601 or "yyyy-MM-dd")
            let maximumDate: String?
            /// Whether the picker is enabled. Supports expressions.
            let isEnabled: String?

            private enum CodingKeys: String, CodingKey {
                case selectedDate, bindVariable, datePickerMode, displayStyle
                case minimumDate, maximumDate, isEnabled
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                selectedDate = try c.decodeIfPresent(String.self, forKey: .selectedDate)
                bindVariable = try c.decodeIfPresent(String.self, forKey: .bindVariable)
                datePickerMode = try c.decodeIfPresent(Mode.self, forKey: .datePickerMode)
                displayStyle = try c.decodeIfPresent(DisplayStyle.self, forKey: .displayStyle)
                minimumDate = try c.decodeIfPresent(String.self, forKey: .minimumDate)
                maximumDate = try c.decodeIfPresent(String.self, forKey: .maximumDate)
                isEnabled = try c.decodeIfPresent(String.self, forKey: .isEnabled)
            }
        }
    }
}
