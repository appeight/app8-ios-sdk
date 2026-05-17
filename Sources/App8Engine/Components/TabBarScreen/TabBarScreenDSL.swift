//
//  TabBarScreenDSL.swift
//  App8Engine
//

import Foundation

extension DSL.Model.Component {

    struct TabBarScreen {

        typealias Entity = ConcreteEntity<C>

        typealias C = TabBarScreenContent

        struct TabBarScreenContent: EntityContent {
            typealias Properties = EmptyProperties
            typealias Style = EmptyStyle

            let tabs: [DSL.Model.Tab]

            /// ID of initially selected tab.
            let initialTab: String?

            /// Tint color for selected tab items (hex string).
            let tintColor: String?

            /// Color for unselected tab items (hex string).
            let unselectedColor: String?

            // MARK: - EntityContent conformance

            var properties: EmptyProperties { EmptyProperties() }
            var style: EmptyStyle? {
                get { EmptyStyle() }
                set {}
            }
            var layout: DSL.Model.Layout? { nil }
            var actions: [DSL.Model.ActionTrigger: DSL.Model.Action]? { nil }
            var children: [DSL.Model.Component.`Any`] {
                get { [] }
                set {}
            }

            mutating func resolveStateStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {}

            enum CodingKeys: String, CodingKey {
                case tabs
                case initialTab
                case tintColor
                case unselectedColor
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                tabs = try container.decode([DSL.Model.Tab].self, forKey: .tabs)
                initialTab = try container.decodeIfPresent(String.self, forKey: .initialTab)
                tintColor = try container.decodeIfPresent(String.self, forKey: .tintColor)
                unselectedColor = try container.decodeIfPresent(String.self, forKey: .unselectedColor)
            }
        }

        struct EmptyProperties: Decodable, Sendable {}

        struct EmptyStyle: Decodable, Sendable, DSL.Model.Style.StylePointerResolvable {
            mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {}
            func isResolved() -> Bool { true }
        }
    }
}
