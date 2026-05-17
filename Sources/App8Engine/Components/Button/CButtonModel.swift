extension DSL.Model.Component {

    struct Button {
        typealias C = Content<Button.Properties, DSL.Model.Style.Button>
        typealias Entity = ConcreteEntity<C>

        struct Properties: Decodable {
            let text: String

            private enum CodingKeys: String, CodingKey { case text }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
            }
        }
    }
}
