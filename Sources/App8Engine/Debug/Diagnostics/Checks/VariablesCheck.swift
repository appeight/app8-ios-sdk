import Foundation

/// Validates variables defined in screens: type/initialValue matching, computed expression parsing, datasource refs.
enum VariablesCheck {

    typealias EC = App8.DiagnosticReport.ErrorCode

    static func run(
        screenIds: Set<String>,
        dataSource: App8DataSource,
        templateResolver: TemplateResolver?,
        validateDatasources: Bool
    ) async -> App8.DiagnosticReport.Section {
        var errors: [App8.ValidationError] = []
        var warnings: [App8.ValidationWarning] = []
        let parser = ExpressionParser()
        let decoder = JSONDecoder()

        for screenId in screenIds.sorted() {
            guard let data = try? await dataSource.getScreen(screenId: screenId) else { continue }

            var processedData = data
            if let resolver = templateResolver {
                let preprocessor = TemplatePreprocessor(resolver: resolver)
                processedData = preprocessor.preprocess(data) ?? data
            }

            guard let extraction = try? decoder.decode(VariablesExtractor.self, from: processedData) else { continue }
            guard let variables = extraction.content?.variables else { continue }

            for (name, definition) in variables {
                let varPath = "screens/\(screenId) > variables.\(name)"

                if let initialValue = definition.rawInitialValue {
                    if !definition.type.validate(initialValue) {
                        let inferredType = VariableType.inferType(from: initialValue)
                        errors.append(App8.ValidationError(
                            code: EC.varTypeMismatch,
                            message: "Variable \"\(name)\" has initialValue of type \(inferredType.rawValue) but declared type is \(definition.type.rawValue). Change initialValue to match the declared type or change type to \"\(inferredType.rawValue)\".",
                            path: varPath,
                            context: [
                                "variableName": name,
                                "declaredType": definition.type.rawValue,
                                "inferredType": inferredType.rawValue
                            ]
                        ))
                    }
                }

                if let expression = definition.computed {
                    do {
                        _ = try parser.parse(expression)
                    } catch {
                        errors.append(App8.ValidationError(
                            code: EC.varExpressionInvalid,
                            message: "Variable \"\(name)\" has invalid computed expression: \(error.localizedDescription). Fix the expression syntax.",
                            path: "\(varPath).computed",
                            context: ["variableName": name, "expression": expression, "error": "\(error)"]
                        ))
                    }
                }

                // Ambiguous preview: both value and source set — value silently wins
                if let preview = definition.preview, preview.value != nil && preview.source != nil {
                    warnings.append(App8.ValidationWarning(
                        code: EC.varPreviewAmbiguous,
                        message: "Variable \"\(name)\" preview defines both 'value' and 'source'. The literal 'value' takes precedence and 'source' is ignored. Remove one to make the intent explicit.",
                        path: "\(varPath).preview",
                        context: ["variableName": name]
                    ))
                }

                // Preview missing for schema (input) variables — skip source-based vars, they're populated automatically
                if definition.schema != nil && definition.preview == nil && definition.source == nil {
                    warnings.append(App8.ValidationWarning(
                        code: EC.varSchemaMissingPreview,
                        message: "Variable \"\(name)\" has a schema but no preview defined. Add a preview so standalone renderScreen() calls can inject a sample value.",
                        path: "\(varPath).preview",
                        context: ["variableName": name, "schema": definition.schema!]
                    ))
                }

                if validateDatasources, let source = definition.source {
                    do {
                        _ = try await dataSource.getDatasource(screenId: screenId, datasourceId: source)
                    } catch {
                        errors.append(App8.ValidationError(
                            code: EC.varDatasourceUnreachable,
                            message: "Screen \"\(screenId)\" variable \"\(name)\" references datasource \"\(source)\" which could not be loaded: \(error.localizedDescription). The screen will fail to render without this data.",
                            path: "\(varPath).source",
                            context: ["screenId": screenId, "variableName": name, "datasourceId": source, "error": "\(error)"]
                        ))
                    }
                }
            }
        }

        let section = App8.DiagnosticReport.Section(
            kind: .variables,
            label: "Variables",
            errors: errors,
            warnings: warnings,
            statusDetail: errors.isEmpty && warnings.isEmpty ? "all variables valid" : nil
        )
        return section
    }

    /// Lightweight decoder to extract just variables from a screen JSON.
    private struct VariablesExtractor: Decodable {
        struct ContentExtractor: Decodable {
            let variables: [String: VariableDefinition]?
        }
        let content: ContentExtractor?
    }
}
