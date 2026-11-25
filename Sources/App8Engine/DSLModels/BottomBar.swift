import Foundation

extension DSL.Model {

    /// `screen.content.bottomBar`: a component pinned to the bottom of the
    /// screen (usually a stack of primary buttons), full width above the
    /// bottom safe area (or the tab bar). The bar's height is added to the
    /// screen's bottom safe area, so scroll content gets the matching inset.
    struct BottomBar: Decodable, Sendable {
        /// The bar's content, pinned to `insets`. Its height is its fitting
        /// height or its own `layout.height`; other layout keys are ignored.
        let component: Component.`Any`?
        /// Space around `component`. Defaults: 12 top, 16 left/right, 8
        /// bottom (from the bottom safe area).
        let insets: EdgeInsets?
        let style: Style?
        /// iOS 26 scroll-edge effect of a `system` bar: `soft` (default) or `hard`.
        let edgeEffect: EdgeEffect?
        /// Boolean or `{{expression}}`. Changes slide + fade the bar (0.33 s).
        let hidden: String?

        struct Style: Decodable, Sendable {
            let background: Background

            enum CodingKeys: String, CodingKey { case background }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                background = (try? c.decodeIfPresent(Background.self, forKey: .background)) ?? .system
            }
        }

        /// `"system"` (default): the platform's bar treatment. Otherwise a
        /// `material` or `fill` style entity, inline or a pointer.
        enum Background: Decodable, Sendable {
            case system
            case style(DSL.Model.Style.`Any`)

            init(from decoder: Decoder) throws {
                if let string = try? decoder.singleValueContainer().decode(String.self), string == "system" {
                    self = .system
                    return
                }
                self = .style(try DSL.Model.Style.`Any`(from: decoder))
            }
        }

        enum EdgeEffect: String, SafeEnumCodable, Sendable {
            case soft, hard
            static let unknownCase: EdgeEffect = .soft
        }

        enum CodingKeys: String, CodingKey {
            case component, insets, style, edgeEffect, hidden
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let raw = try c.decodeIfPresent(JSONValue.self, forKey: .component) {
                let pinned = Self.pinned(raw)
                let data = try JSONEncoder().encode(pinned)
                component = try LenientDocumentDecoding.decodeNested(
                    Component.`Any`.self, from: data, userInfo: decoder.userInfo, at: c.codingPath + [CodingKeys.component])
            } else {
                component = nil
            }
            insets = try c.decodeIfPresent(EdgeInsets.self, forKey: .insets)
            style = try c.decodeIfPresent(Style.self, forKey: .style)
            edgeEffect = try c.decodeIfPresent(EdgeEffect.self, forKey: .edgeEffect)
            hidden = c.decodeFlagIfPresent(forKey: .hidden)
        }

        /// The component with its layout replaced: pinned to all four edges of
        /// the bar's content area, keeping only its own `height`.
        static func pinned(_ raw: JSONValue) -> JSONValue {
            guard case .object(var object) = raw, case .object(var content)? = object["content"] else { return raw }
            var layout: [String: JSONValue] = [
                "leading": .number(0), "trailing": .number(0), "top": .number(0), "bottom": .number(0)
            ]
            if case .object(let original)? = content["layout"], let height = original["height"] {
                layout["height"] = height
            }
            content["layout"] = .object(layout)
            object["content"] = .object(content)
            return .object(object)
        }
    }
}
