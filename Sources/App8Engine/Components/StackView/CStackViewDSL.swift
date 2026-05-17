//
//  CStackViewDSL.swift
//  App8Engine
//

import Foundation

extension DSL.Model.Component {

    struct StackView {

        typealias Entity = ConcreteEntity<C>

        typealias C = Content<StackView.Properties, Style.View>

        struct Properties: CustomDecodable {
            /// Stack axis: "horizontal" | "vertical" (default: "vertical")
            private(set) var axis: String?

            /// Spacing between arranged subviews
            private(set) var spacing: CGFloat?

            /// Alignment: "fill" | "center" | "top" | "bottom" | "leading" | "trailing"
            private(set) var alignment: String?

            /// Distribution: "fill" | "fillEqually" | "fillProportionally" | "equalSpacing" | "equalCentering"
            private(set) var distribution: String?

            /// Background color as a hex string, e.g. "#F2F2F7"
            private(set) var backgroundColor: String?

            /// Corner radius for the background
            private(set) var cornerRadius: CGFloat?

            static func decode<CodingKeys: CodingKey>(fromContainer container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Self {
                if container.contains(key) {
                    return try container.decode(Self.self, forKey: key)
                } else {
                    return .init()
                }
            }
        }
    }
}
