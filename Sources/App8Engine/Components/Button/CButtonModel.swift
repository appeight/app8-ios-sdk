extension DSL.Model.Component {

    struct Button {
        typealias C = Content<Button.Properties, DSL.Model.Style.Button>
        typealias Entity = ConcreteEntity<C>

        struct Properties: Decodable {
            let text: String
            /// Expression resolving to a Bool. Drives `UIButton.isEnabled` — the
            /// system disabled appearance when a `style.system` config is used, or a
            /// dimmed alpha otherwise. Defaults to enabled.
            let isEnabled: String?
            /// Expression resolving to a Bool. Drives `UIButton.isSelected`. Defaults to false.
            let isSelected: String?

            private enum CodingKeys: String, CodingKey { case text, isEnabled, isSelected }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
                isEnabled = try c.decodeIfPresent(String.self, forKey: .isEnabled)
                isSelected = try c.decodeIfPresent(String.self, forKey: .isSelected)
            }
        }
    }
}
