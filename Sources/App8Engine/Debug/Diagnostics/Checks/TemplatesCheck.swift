import Foundation

/// Validates templates: decoding and inheritance resolution.
enum TemplatesCheck {

    typealias EC = App8.DiagnosticReport.ErrorCode

    struct Result {
        let section: App8.DiagnosticReport.Section
        let templateResolver: TemplateResolver?
    }

    static func run(dataSource: App8DataSource) async -> Result {
        var errors: [App8.ValidationError] = []
        var warnings: [App8.ValidationWarning] = []

        // Load templates (called "components" in the datasource)
        let templatesData: [Data]
        do {
            templatesData = try await dataSource.getComponents()
        } catch {
            errors.append(App8.ValidationError(
                code: EC.templateDecodeFailed,
                message: "Failed to load templates from data source: \(error.localizedDescription).",
                path: "templates",
                context: ["error": "\(error)"]
            ))
            return Result(
                section: .init(kind: .templates, label: "Templates", errors: errors, warnings: warnings),
                templateResolver: nil
            )
        }

        let decoder = JSONDecoder()
        var templateItems: [DSL.Model.Component.Template] = []
        var decodeFailures = 0

        for (i, data) in templatesData.enumerated() {
            do {
                let template = try decoder.decode(DSL.Model.Component.Template.self, from: data)
                templateItems.append(template)
            } catch {
                decodeFailures += 1
                warnings.append(App8.ValidationWarning(
                    code: EC.templateDecodeFailed,
                    message: "Failed to decode template \(i): \(error.localizedDescription). This template will be unavailable.",
                    path: "templates[\(i)]",
                    context: ["error": "\(error)"]
                ))
            }
        }

        var resolver = TemplateResolver(templates: templateItems)
        resolver.resolveAllTemplates()

        for template in templateItems {
            if let parentId = template.templateId, !resolver.hasTemplate(parentId) {
                errors.append(App8.ValidationError(
                    code: EC.templateUnresolvedInheritance,
                    message: "Template \"\(template.id)\" extends \"\(parentId)\" which could not be resolved. Available templates: \(templateItems.map(\.id).joined(separator: ", ")).",
                    path: "templates > \(template.id).templateId",
                    context: [
                        "templateId": template.id,
                        "parentId": parentId,
                        "availableTemplates": templateItems.map(\.id).joined(separator: ", ")
                    ]
                ))
            }
        }

        let detail = "\(templateItems.count) template(s) loaded" +
            (decodeFailures > 0 ? ", \(decodeFailures) decode failure(s)" : "")

        let section = App8.DiagnosticReport.Section(
            kind: .templates,
            label: "Templates",
            errors: errors,
            warnings: warnings,
            statusDetail: detail
        )
        return Result(section: section, templateResolver: resolver)
    }
}
