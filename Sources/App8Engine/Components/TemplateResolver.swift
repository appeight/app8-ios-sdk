import Foundation

/// Resolves component templates with multi-pass algorithm for nested inheritance.
///
/// Templates can inherit from other templates via `templateId`. The resolver handles
/// arbitrary ordering of templates in the JSON by using a multi-pass approach:
/// - Base templates (no parent) are resolved immediately
/// - Child templates wait for their parent to be resolved
/// - Resolution continues until no more progress is made
struct TemplateResolver: Sendable {

    /// Input templates (may have nested references)
    private let templates: [DSL.Model.Component.Template]

    /// Dictionary of resolved template content [templateId: mergedContent]
    private(set) var resolvedTemplates: [String: JSONValue] = [:]

    /// Dictionary of template types [templateId: CType]
    private var templateTypes: [String: DSL.Model.Component.CType] = [:]

    init(templates: [DSL.Model.Component.Template]) {
        self.templates = templates
        for template in templates {
            templateTypes[template.id] = template.type
        }
    }

    /// Resolve all templates using multi-pass algorithm.
    /// Handles arbitrary ordering and nested template inheritance.
    mutating func resolveAllTemplates() {
        var madeProgress = true

        while madeProgress {
            madeProgress = false

            for template in templates {
                guard resolvedTemplates[template.id] == nil else { continue }

                if let resolved = resolveTemplate(template) {
                    resolvedTemplates[template.id] = resolved
                    madeProgress = true
                }
            }
        }
    }

    /// Attempt to resolve a single template.
    /// Returns nil if parent template is not yet resolved.
    private func resolveTemplate(_ template: DSL.Model.Component.Template) -> JSONValue? {
        guard let parentId = template.templateId else {
            return template.rawContent?.value ?? .object([:])
        }

        guard let parentContent = resolvedTemplates[parentId] else {
            return nil // parent not yet resolved, try again next pass
        }

        guard case .object(let parentObj) = parentContent else {
            return nil
        }

        if let rawContent = template.rawContent {
            return .object(deepMerge(base: parentObj, override: rawContent.value))
        }

        return parentContent
    }

    /// Get the component type for a template by ID.
    func getTemplateType(_ templateId: String) -> DSL.Model.Component.CType? {
        templateTypes[templateId]
    }

    /// Check if a template exists.
    func hasTemplate(_ templateId: String) -> Bool {
        resolvedTemplates[templateId] != nil
    }
}
