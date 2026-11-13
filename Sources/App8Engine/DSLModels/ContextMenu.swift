//
//  ContextMenu.swift
//  App8Engine
//
//  `content.contextMenu`: a long-press preview plus menu items (iOS
//  `UIContextMenuInteraction`). See app8-dsl docs/context-menu.md.
//

import Foundation

extension DSL.Model {

    /// A reference type so `Component.Content` (copied by value into every view
    /// model) stays small: the preview embeds a whole component tree.
    final class ContextMenu: Decodable, @unchecked Sendable {
        let preview: Preview?
        let items: [Item]
        let onPreviewTap: [Action]
        /// Bool or expression. Default true.
        let isEnabled: String?

        private enum CodingKeys: String, CodingKey {
            case preview, items, onPreviewTap, isEnabled
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            preview = try c.decodeIfPresent(Preview.self, forKey: .preview)
            items = (try c.decodeIfPresent(SafeArrayDecodable<Item>.self, forKey: .items))?.wrappedValue ?? []
            onPreviewTap = (try c.decodeIfPresent(ActionList.self, forKey: .onPreviewTap))?.actions ?? []
            isEnabled = try c.decodeLenientBoolExpression(forKey: .isEnabled)
        }

        struct Preview: Decodable, Sendable {
            let component: Component.`Any`
            let width: Double?
            let height: Double?

            private enum CodingKeys: String, CodingKey { case component, width, height }

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                width = try c.decodeIfPresent(Double.self, forKey: .width)
                height = try c.decodeIfPresent(Double.self, forKey: .height)
                if let decoded = try? c.decode(Component.`Any`.self, forKey: .component) {
                    component = decoded
                    return
                }
                // `{ "templateId": "X" }` (no `id`, maybe no `type`): give it a
                // stable id and decode it as a pointer the renderer resolves.
                var raw = try c.decode([String: JSONValue].self, forKey: .component)
                if raw["id"] == nil { raw["id"] = .string("contextMenuPreview") }
                if raw["type"] == nil { raw["type"] = .string("view") }
                let data = try JSONEncoder().encode(JSONValue.object(raw))
                let nested = JSONDecoder()
                nested.userInfo = decoder.userInfo
                component = try nested.decode(Component.`Any`.self, from: data)
            }
        }

        struct Item: Decodable, Sendable {
            let id: String
            let title: String
            let subtitle: String?
            let icon: String?
            let destructive: Bool
            let isEnabled: String?
            let hidden: String?
            let actions: [Action]

            private enum CodingKeys: String, CodingKey {
                case id, title, subtitle, icon, destructive, isEnabled, hidden, actions
            }

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(String.self, forKey: .id)
                title = try c.decode(String.self, forKey: .title)
                subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
                icon = try c.decodeIfPresent(String.self, forKey: .icon)
                destructive = try c.decodeIfPresent(Bool.self, forKey: .destructive) ?? false
                isEnabled = try c.decodeLenientBoolExpression(forKey: .isEnabled)
                hidden = try c.decodeLenientBoolExpression(forKey: .hidden)
                actions = (try c.decodeIfPresent(ActionList.self, forKey: .actions))?.actions ?? []
            }
        }
    }
}

extension KeyedDecodingContainer {
    /// A `boolean/expression` field: a JSON bool becomes `"true"` / `"false"`.
    func decodeLenientBoolExpression(forKey key: Key) throws -> String? {
        if let bool = try? decodeIfPresent(Bool.self, forKey: key) {
            return bool ? "true" : "false"
        }
        return try decodeIfPresent(String.self, forKey: key)
    }
}
