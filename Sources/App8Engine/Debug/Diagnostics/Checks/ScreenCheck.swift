import Foundation

/// Validates individual screens: loading, decoding, type validation, style pointer resolution.
enum ScreenCheck {

    typealias EC = App8.DiagnosticReport.ErrorCode

    struct Result {
        let sections: [App8.DiagnosticReport.Section]
        let loadedScreenIds: Set<String>
        let failedScreenIds: Set<String>
    }

    static func run(
        screenIds: Set<String>,
        dataSource: App8DataSource,
        resolvedStyles: [String: DSL.Model.Style.`Any`],
        templateResolver: TemplateResolver?,
        resolvePointers: Bool
    ) async -> Result {
        var sections: [App8.DiagnosticReport.Section] = []
        var loadedIds = Set<String>()
        var failedIds = Set<String>()

        for screenId in screenIds.sorted() {
            let screenResult = await checkScreen(
                screenId: screenId,
                dataSource: dataSource,
                resolvedStyles: resolvedStyles,
                templateResolver: templateResolver,
                resolvePointers: resolvePointers
            )
            sections.append(screenResult.section)
            if screenResult.loaded {
                loadedIds.insert(screenId)
            } else {
                failedIds.insert(screenId)
            }
        }

        return Result(sections: sections, loadedScreenIds: loadedIds, failedScreenIds: failedIds)
    }

    private struct ScreenResult {
        let section: App8.DiagnosticReport.Section
        let loaded: Bool
    }

    private static func checkScreen(
        screenId: String,
        dataSource: App8DataSource,
        resolvedStyles: [String: DSL.Model.Style.`Any`],
        templateResolver: TemplateResolver?,
        resolvePointers: Bool
    ) async -> ScreenResult {
        var errors: [App8.ValidationError] = []
        var warnings: [App8.ValidationWarning] = []

        let screenData: Data
        do {
            screenData = try await dataSource.getScreen(screenId: screenId)
        } catch {
            errors.append(App8.ValidationError(
                code: EC.screenLoadFailed,
                message: "Failed to load screen \"\(screenId)\": \(error.localizedDescription). Ensure the screen file exists in the data source.",
                path: "screens/\(screenId)",
                context: ["screenId": screenId, "error": "\(error)"]
            ))
            let section = App8.DiagnosticReport.Section(
                kind: .screens,
                label: "Screen: \(screenId)",
                errors: errors,
                warnings: warnings
            )
            return ScreenResult(section: section, loaded: false)
        }

        var processedData = screenData
        if let resolver = templateResolver {
            let preprocessor = TemplatePreprocessor(resolver: resolver)
            processedData = preprocessor.preprocess(screenData) ?? screenData
        }

        let collector = DecodeErrorCollector()
        DecodeErrorCollector.current = collector

        var component: DSL.Model.Component.`Any`
        do {
            component = try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: processedData)
        } catch {
            DecodeErrorCollector.current = nil
            let detail = [FailableDecodable<DSL.Model.Component.`Any`>].formatDecodingError(error)
            errors.append(App8.ValidationError(
                code: EC.screenDecodeFailed,
                message: "Failed to decode screen \"\(screenId)\": \(detail). Check the JSON structure for this screen.",
                path: "screens/\(screenId)",
                context: ["screenId": screenId, "error": "\(error)"]
            ))
            let section = App8.DiagnosticReport.Section(
                kind: .screens,
                label: "Screen: \(screenId)",
                errors: errors,
                warnings: warnings
            )
            return ScreenResult(section: section, loaded: false)
        }

        DecodeErrorCollector.current = nil

        // Report nested decode failures (children, materials, etc. that silently failed)
        for entry in collector.entries {
            let detail = [FailableDecodable<DSL.Model.Component.`Any`>].formatDecodingError(entry.error)
            warnings.append(App8.ValidationWarning(
                code: EC.screenChildDecodeFailed,
                message: "Screen \"\(screenId)\" has a child component that failed to decode (\(entry.typeName)): \(detail)",
                path: "screens/\(screenId) > \(entry.codingPath)",
                context: ["screenId": screenId, "typeName": entry.typeName, "jsonPath": entry.jsonPath, "error": "\(entry.error)"]
            ))
        }

        if !component.type.isOneOf(.screen, .tabBarScreen) {
            let typeStr: String
            switch component.type {
            case .key(let key): typeStr = key.rawValue
            case .custom(let name): typeStr = name
            }
            warnings.append(App8.ValidationWarning(
                code: EC.screenInvalidType,
                message: "Screen \"\(screenId)\" has type \"\(typeStr)\" instead of \"screen\" or \"tabBarScreen\". It may not render correctly.",
                path: "screens/\(screenId) > type",
                context: ["screenId": screenId, "actualType": typeStr]
            ))
        }

        if resolvePointers {
            component.resolveStylePointers { resolvedStyles[$0]?.asEntity() }
            let unresolvedIds = component.unresolvedPointerIds()
            if !unresolvedIds.isEmpty {
                let idList = unresolvedIds.sorted().map { "\"\($0)\"" }.joined(separator: ", ")
                warnings.append(App8.ValidationWarning(
                    code: EC.screenStyleUnresolved,
                    message: "Screen \"\(screenId)\" has unresolved style pointers after resolution: \(idList). Some styles may be missing from stylesheets.",
                    path: "screens/\(screenId) > style",
                    context: ["screenId": screenId, "unresolvedIds": unresolvedIds.sorted().joined(separator: ", ")]
                ))
            }
        }

        let collectionWarnings = walkForCollectionIssues(component, screenId: screenId, path: "")
        warnings.append(contentsOf: collectionWarnings)

        let section = App8.DiagnosticReport.Section(
            kind: .screens,
            label: "Screen: \(screenId)",
            errors: errors,
            warnings: warnings,
            statusDetail: errors.isEmpty && warnings.isEmpty ? "OK" : nil
        )
        return ScreenResult(section: section, loaded: true)
    }

    private static func walkForCollectionIssues(
        _ component: DSL.Model.Component.`Any`,
        screenId: String,
        path: String
    ) -> [App8.ValidationWarning] {
        var warnings: [App8.ValidationWarning] = []
        let componentPath = path.isEmpty ? component.id : "\(path).\(component.id)"

        if let collectionEntity = component.base as?
            DSL.Model.Component.ConcreteEntity<CollectionContent> {
            let content = collectionEntity.content

            if content.properties.templateKey != nil && content.templates == nil {
                warnings.append(App8.ValidationWarning(
                    code: EC.collectionMissingTemplates,
                    message: "Collection \"\(component.id)\" has templateKey in properties but no templates dict in content. Move templates to the content level (sibling of layout and properties).",
                    path: "screens/\(screenId)/\(componentPath)",
                    context: ["componentId": component.id, "screenId": screenId]
                ))
            }

            // Only warn if neither a global templateKey nor sectionDefinitions cover the template dispatch.
            // When sectionDefinitions are used, each section carries its own templateName/templateKey.
            let hasSectionDefinitions = content.properties.sectionDefinitions != nil
            let allSectionsCovered = hasSectionDefinitions && (content.properties.sectionDefinitions ?? []).allSatisfy {
                $0.templateName != nil || $0.templateKey != nil
            }
            if content.templates != nil && content.properties.templateKey == nil && !allSectionsCovered {
                warnings.append(App8.ValidationWarning(
                    code: EC.collectionMissingTemplateKey,
                    message: "Collection \"\(component.id)\" has a templates dict in content but no templateKey in properties. Add templateKey to properties to select the right template per item.",
                    path: "screens/\(screenId)/\(componentPath)",
                    context: ["componentId": component.id, "screenId": screenId]
                ))
            }

            if let template = content.template {
                warnings += walkForCollectionIssues(template, screenId: screenId, path: componentPath)
            }
            for (key, ref) in content.templates ?? [:] {
                if case .inline(let templateComponent) = ref {
                    warnings += walkForCollectionIssues(templateComponent, screenId: screenId, path: "\(componentPath).templates[\(key)]")
                }
            }
        }

        if let entity = component.asEntity() {
            for child in entity.content.children {
                warnings += walkForCollectionIssues(child, screenId: screenId, path: componentPath)
            }
        }

        return warnings
    }
}
