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

            /// Badge background on every tab (hex).
            let badgeColor: String?

            /// Badge text color (hex).
            let badgeTextColor: String?

            /// `barStyle`: a text bar or a component template (tab-bar-screen.md).
            let barStyle: DSL.Model.TabBarContent.BarStyle?

            /// Platform bar: the selected item's highlight colour (hex with alpha, or an expression). Since 0.7.9.
            let selectionIndicatorColor: String?

            // MARK: - EntityContent conformance

            var properties: EmptyProperties { EmptyProperties() }
            var style: EmptyStyle? {
                get { EmptyStyle() }
                set {}
            }
            var layout: DSL.Model.Layout? { nil }
            var actions: [DSL.Model.ActionTrigger: [DSL.Model.Action]]? { nil }
            var analytics: [DSL.Model.ActionTrigger: DSL.Model.AnalyticsBinding]? { nil }
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
                case badgeColor
                case badgeTextColor
                case barStyle
                case selectionIndicatorColor
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                tabs = try container.decode([DSL.Model.Tab].self, forKey: .tabs)
                initialTab = try container.decodeIfPresent(String.self, forKey: .initialTab)
                tintColor = try container.decodeIfPresent(String.self, forKey: .tintColor)
                unselectedColor = try container.decodeIfPresent(String.self, forKey: .unselectedColor)
                badgeColor = try container.decodeIfPresent(String.self, forKey: .badgeColor)
                badgeTextColor = try container.decodeIfPresent(String.self, forKey: .badgeTextColor)
                barStyle = try? container.decodeIfPresent(DSL.Model.TabBarContent.BarStyle.self, forKey: .barStyle)
                selectionIndicatorColor = try? container.decodeIfPresent(String.self, forKey: .selectionIndicatorColor)
            }
        }

        struct EmptyProperties: Decodable, Sendable {}

        struct EmptyStyle: Decodable, Sendable, DSL.Model.Style.StylePointerResolvable {
            mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {}
            func isResolved() -> Bool { true }
        }
    }
}
