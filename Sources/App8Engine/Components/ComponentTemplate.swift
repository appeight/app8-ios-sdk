import Foundation

extension DSL.Model.Component {

    /// A template definition that can be referenced by component instances via `templateId`.
    /// Templates support inheritance - a template can reference another template via its own `templateId`.
    public struct Template: Decodable, Sendable, Identifiable {
        /// Unique identifier for this template
        public let id: String

        /// Optional parent template ID for template inheritance
        public let templateId: String?

        /// Component type (button, view, label, etc.)
        public let type: CType

        /// Raw JSON content to be merged with instances
        public let rawContent: RawJSON?

        private enum CodingKeys: String, CodingKey {
            case id, templateId, type, content
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            templateId = try container.decodeIfPresent(String.self, forKey: .templateId)
            type = try container.decode(CType.self, forKey: .type)
            rawContent = try container.decodeIfPresent(RawJSON.self, forKey: .content)
        }

        /// Returns true if this template has no parent (is a base template)
        public var isBaseTemplate: Bool {
            templateId == nil
        }
    }
}
