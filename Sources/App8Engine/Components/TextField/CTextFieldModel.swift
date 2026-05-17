//
//  CTextFieldModel.swift
//  App8Engine
//

import UIKit

extension DSL.Model.Component {

    /// TextField component for single-line text input
    struct TextField {

        typealias C = Content<TextField.Properties, DSL.Model.Style.TextField>
        typealias Entity = ConcreteEntity<C>

        /// TextField properties
        struct Properties: Decodable, Sendable {

            /// Placeholder text shown when field is empty
            let placeholder: String?

            /// Initial/current text value (supports {{expressions}})
            let text: String?

            /// Variable name to bind for two-way sync
            let bindVariable: String?

            /// Keyboard type
            let keyboardType: DSL.Model.Component.KeyboardType?

            /// Text content type for iOS autofill
            let textContentType: DSL.Model.Component.TextContentType?

            /// Return key type
            let returnKeyType: DSL.Model.Component.ReturnKeyType?

            /// Whether text is hidden (for passwords)
            let isSecure: Bool?

            /// Autocapitalization behavior
            let autocapitalization: DSL.Model.Component.AutocapitalizationType?

            /// Whether autocorrection is enabled
            let autocorrection: Bool?

            /// Maximum character length
            let maxLength: Int?

            /// Input mask pattern (e.g., "(###) ###-####" for phone)
            let inputMask: String?

            /// Allowed characters (regex pattern)
            let allowedCharacters: String?

            /// Whether the field is editable
            let isEnabled: Bool?

            /// Clear button mode
            let clearButtonMode: ClearButtonMode?
        }

        /// Clear button display mode
        enum ClearButtonMode: String, Decodable, Sendable {
            case never
            case whileEditing
            case unlessEditing
            case always

            var uiMode: UITextField.ViewMode {
                switch self {
                case .never: return .never
                case .whileEditing: return .whileEditing
                case .unlessEditing: return .unlessEditing
                case .always: return .always
                }
            }
        }
    }
}
