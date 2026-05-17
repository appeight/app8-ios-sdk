import Foundation

extension DSL.Model.Component {

    struct PageControl {
        typealias C = Content<PageControl.Properties, DSL.Model.Style.PageControl>
        typealias Entity = ConcreteEntity<C>

        struct Properties: Decodable, Sendable {
            /// Number of pages. Supports expressions: "{{totalPhotos}}"
            let numberOfPages: String?
            /// Current page index. Supports expressions: "{{currentIndex}}"
            let currentPage: String?
            /// Variable name for two-way binding
            let bindVariable: String?
            /// Whether to hide when there is only one page. Default: true
            let hidesForSinglePage: Bool?

            private enum CodingKeys: String, CodingKey {
                case numberOfPages, currentPage, bindVariable, hidesForSinglePage
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                numberOfPages = try c.decodeIfPresent(String.self, forKey: .numberOfPages)
                currentPage = try c.decodeIfPresent(String.self, forKey: .currentPage)
                bindVariable = try c.decodeIfPresent(String.self, forKey: .bindVariable)
                hidesForSinglePage = try c.decodeIfPresent(Bool.self, forKey: .hidesForSinglePage)
            }
        }
    }
}
