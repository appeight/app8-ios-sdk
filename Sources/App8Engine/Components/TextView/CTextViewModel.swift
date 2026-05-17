//
//  CTextViewModel.swift
//  App8Engine
//

import UIKit

extension DSL.Model.Component {

    /// TextView component for multi-line text input
    struct TextView {

        typealias C = Content<TextView.Properties, DSL.Model.Style.TextView>
        typealias Entity = ConcreteEntity<C>

        /// TextView properties
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

            /// Autocapitalization behavior
            let autocapitalization: DSL.Model.Component.AutocapitalizationType?

            /// Whether autocorrection is enabled
            let autocorrection: Bool?

            /// Maximum character length
            let maxLength: Int?

            /// Whether the field is editable
            let isEnabled: Bool?

            /// Whether scrolling is enabled
            let scrollEnabled: Bool?

            /// Whether the text view should auto-grow with content
            let autoGrow: Bool?

            /// Maximum height when autoGrow is enabled
            let maxHeight: CGFloat?

            /// Minimum height
            let minHeight: CGFloat?
        }
    }
}
