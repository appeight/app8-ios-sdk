import Foundation

/// Pre-processes component JSON, merging template content with instance overrides
/// so the result can be decoded directly as components.
struct TemplatePreprocessor {

    private let resolver: TemplateResolver

    init(resolver: TemplateResolver) {
        self.resolver = resolver
    }

    /// Pre-processes JSON data by resolving all template references.
    /// Returns new Data with templates merged into instances.
    func preprocess(_ data: Data) -> Data? {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return nil
        }

        let processed = processValue(json)

        return try? JSONEncoder().encode(processed)
    }

    /// Recursively processes a JSONValue, merging templates where found.
    private func processValue(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let obj):
            return processObject(obj)
        case .array(let arr):
            return .array(arr.map { processValue($0) })
        default:
            return value
        }
    }

    /// Processes an object, potentially merging with a template.
    private func processObject(_ obj: [String: JSONValue]) -> JSONValue {
        var processed = obj.mapValues { processValue($0) }

        guard case .string(let templateId) = processed["templateId"],
              let templateContent = resolver.resolvedTemplates[templateId] else {
            return .object(processed)
        }

        if processed["type"] == nil,
           let templateType = resolver.getTemplateType(templateId) {
            processed["type"] = templateType.jsonValue
        }

        if case .object(let templateObj) = templateContent {
            let instanceContent: [String: JSONValue]
            if case .object(let content) = processed["content"] {
                instanceContent = content
            } else {
                instanceContent = [:]
            }

            // Deep merge: template is base, instance overrides.
            var mergedContent = deepMerge(base: templateObj, override: .object(instanceContent))

            if case .object(let instanceVariables) = processed["variables"] {
                let normalizedVars = normalizeVariables(instanceVariables)

                let existingVars: [String: JSONValue]
                if case .object(let vars) = mergedContent["variables"] {
                    existingVars = vars
                } else {
                    existingVars = [:]
                }

                // Instance variables completely replace template variables (not deep-merged).
                // Deep-merging VariableDefinition objects would let template fields like
                // "initialValue" bleed into an instance-provided "computed" definition.
                var mergedVars = existingVars
                for (key, value) in normalizedVars {
                    mergedVars[key] = value
                }
                mergedContent["variables"] = .object(mergedVars)
            }

            processed["content"] = .object(mergedContent)
        }

        // templateId and variables are resolved into content above; drop them.
        processed.removeValue(forKey: "templateId")
        processed.removeValue(forKey: "variables")

        return .object(processed)
    }

    // MARK: - Variable Normalization

    /// Normalizes shorthand variable syntax to full VariableDefinition format.
    ///
    /// Shorthand: `"icon": "homes-icon.png"`
    /// Full: `"icon": { "type": "string", "initialValue": "homes-icon.png" }`
    private func normalizeVariables(_ variables: [String: JSONValue]) -> [String: JSONValue] {
        var normalized: [String: JSONValue] = [:]

        for (name, value) in variables {
            switch value {
            case .object(let obj) where obj["type"] != nil:
                normalized[name] = value
            default:
                let varType = inferType(from: value)
                // Expression strings must become `computed` so they evaluate reactively
                // against the parent scope.
                if case .string(let str) = value, str.contains("{{") {
                    normalized[name] = .object([
                        "type": .string(varType),
                        "computed": value
                    ])
                } else {
                    normalized[name] = .object([
                        "type": .string(varType),
                        "initialValue": value
                    ])
                }
            }
        }

        return normalized
    }

    /// Infers the variable type from a JSON value.
    private func inferType(from value: JSONValue) -> String {
        switch value {
        case .string: return "string"
        case .number: return "number"
        case .bool: return "boolean"
        case .array: return "array"
        case .object: return "object"
        case .null: return "string"
        }
    }
}
