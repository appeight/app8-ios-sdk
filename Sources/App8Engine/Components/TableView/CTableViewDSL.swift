//
//  CTableViewDSL.swift
//  App8Engine
//
//  DSL model for a static grouped table view component.
//  All sections and rows are defined inline in JSON — no external datasource needed.
//

import UIKit

extension DSL.Model.Component {

    struct TableView {
        typealias Entity = ConcreteEntity<Content>

        // MARK: - Section

        /// A static section with an optional header/footer and an array of rows.
        struct Section: Decodable, Sendable {
            let id: String
            let header: String?
            let footer: String?
            @SafeArrayDecodable var rows: [Row] = []
        }

        // MARK: - Row

        /// A static row: fixed height, optional tap action, DSL children rendered into the cell.
        struct Row: Decodable, Sendable {
            let id: String
            let height: CGFloat?
            /// When true the cell background is transparent (no card). Useful for footer-style rows.
            let clearBackground: Bool?
            let actions: [DSL.Model.ActionTrigger: [DSL.Model.Action]]?
            /// Author-declared analytics bindings keyed by trigger. Symmetric
            /// with `Component.actions` / `Component.analytics`. Only `.tap` is
            /// meaningful at the row level today.
            let analytics: [DSL.Model.ActionTrigger: DSL.Model.AnalyticsBinding]?
            @SafeArrayDecodable var children: [DSL.Model.Component.`Any`] = []

            private enum CodingKeys: CodingKey {
                case id, height, clearBackground, actions, analytics, children
            }

            // ActionTrigger is not CodingKey so [ActionTrigger: Action] can't be decoded
            // by synthesis. Mirror the pattern from Base.swift: decode as [String: ActionList],
            // then convert keys to ActionTrigger.
            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id             = try c.decode(String.self, forKey: .id)
                height         = try c.decodeIfPresent(CGFloat.self, forKey: .height)
                clearBackground = try c.decodeIfPresent(Bool.self, forKey: .clearBackground)
                if let raw = try c.decodeIfPresent([String: DSL.Model.ActionList].self, forKey: .actions) {
                    var converted: [DSL.Model.ActionTrigger: [DSL.Model.Action]] = [:]
                    for (key, value) in raw {
                        if let trigger = DSL.Model.ActionTrigger(rawValue: key) {
                            converted[trigger] = value.actions
                        }
                    }
                    actions = converted.isEmpty ? nil : converted
                } else {
                    actions = nil
                }
                if let raw = try c.decodeIfPresent([String: DSL.Model.AnalyticsBinding].self, forKey: .analytics) {
                    var converted: [DSL.Model.ActionTrigger: DSL.Model.AnalyticsBinding] = [:]
                    for (key, value) in raw {
                        if let trigger = DSL.Model.ActionTrigger(rawValue: key) {
                            converted[trigger] = value
                        }
                    }
                    analytics = converted.isEmpty ? nil : converted
                } else {
                    analytics = nil
                }
                if let decoded = try c.decodeIfPresent(SafeArrayDecodable<DSL.Model.Component.`Any`>.self, forKey: .children) {
                    _children = decoded
                }
            }
        }

        // MARK: - Content

        struct Content: DSL.Model.Component.EntityContent,
                        DSL.Model.StatefulContent,
                        DSL.Model.VariablesHolder,
                        DSL.Model.EventTriggersHolder {

            // MARK: Properties

            struct Properties: Decodable, Sendable {
                /// UITableView style. Defaults to .insetGrouped.
                let tableStyle: TableStyle?
                /// Whether to show the scroll indicator. Defaults to true.
                let showsIndicator: Bool?
                /// Leading inset for row separators. Defaults to 0.
                let separatorInset: CGFloat?
            }

            enum TableStyle: String, SafeEnumCodable, Sendable {
                case plain, grouped, insetGrouped
                static var unknownCase: Self { .insetGrouped }

                var ui: UITableView.Style {
                    switch self {
                    case .plain:        return .plain
                    case .grouped:      return .grouped
                    case .insetGrouped: return .insetGrouped
                    }
                }
            }

            // MARK: EntityContent / StatefulContent / VariablesHolder fields

            let properties: Properties
            var style: DSL.Model.Style.View?
            let layout: DSL.Model.Layout?
            let variables: [String: VariableDefinition]?
            let actions: [DSL.Model.ActionTrigger: [DSL.Model.Action]]?
            let analytics: [DSL.Model.ActionTrigger: DSL.Model.AnalyticsBinding]?
            let defaultStateName: String?
            var states: [String: DSL.Model.State<Properties, DSL.Model.Style.View>]?
            let triggers: [DSL.Model.Trigger: String]?
            let onEvent: [DSL.Model.EventTrigger]?
            /// Standard children — unused for tableView but required by EntityContent.
            @SafeArrayDecodable var children: [DSL.Model.Component.`Any`] = []

            // MARK: Table-specific

            @SafeArrayDecodable var sections: [Section] = []

            // MARK: EntityContent protocol

            mutating func resolveStateStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
                style?.resolveStylePointers(resolver: resolver)
                guard var statesDict = states else { return }
                for (stateName, var state) in statesDict {
                    if var stateStyle = state.style as? DSL.Model.Style.StylePointerResolvable {
                        stateStyle.resolveStylePointers(resolver: resolver)
                        state.setResolvedStyle(stateStyle)
                        statesDict[stateName] = state
                    }
                }
                states = statesDict
            }
        }
    }
}
