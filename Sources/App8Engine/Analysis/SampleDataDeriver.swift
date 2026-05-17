//
//  SampleDataDeriver.swift
//  App8Engine
//

import Foundation

/// Derives realistic sample data for a screen's required params by analyzing
/// cross-screen navigation actions and resolving datasource values.
struct SampleDataDeriver {

    private let dataSource: App8DataSource
    private let templateResolver: TemplateResolver?
    private let decoder = JSONDecoder()

    init(dataSource: App8DataSource, templateResolver: TemplateResolver? = nil) {
        self.dataSource = dataSource
        self.templateResolver = templateResolver
    }

    /// Derive sample data for required params of a target screen.
    /// Scans all screens for navigation actions pointing to `targetScreenId`,
    /// extracts the `params` mapping, resolves datasource values, and picks the first item.
    func deriveSampleData(
        forScreen targetScreenId: String,
        requiredParams: [ScreenAnalysis.RequiredParam]
    ) async -> [String: Any] {
        guard !requiredParams.isEmpty else { return [:] }

        guard let screenIds = try? await dataSource.getAllScreenIds() ?? nil else {
            return [:]
        }

        for sourceScreenId in screenIds {
            guard let result = await scanScreen(
                sourceScreenId: sourceScreenId,
                targetScreenId: targetScreenId,
                requiredParams: requiredParams
            ) else {
                continue
            }
            if !result.isEmpty { return result }
        }

        return [:]
    }

    // MARK: - Private

    /// Scan a source screen for navigation actions to targetScreenId and try to resolve params.
    private func scanScreen(
        sourceScreenId: String,
        targetScreenId: String,
        requiredParams: [ScreenAnalysis.RequiredParam]
    ) async -> [String: Any]? {
        guard let screenData = try? await dataSource.getScreen(screenId: sourceScreenId) else {
            return nil
        }

        let processedData: Data
        if let resolver = templateResolver {
            let preprocessor = TemplatePreprocessor(resolver: resolver)
            processedData = preprocessor.preprocess(screenData) ?? screenData
        } else {
            processedData = screenData
        }

        guard let json = try? JSONSerialization.jsonObject(with: processedData) as? [String: Any] else {
            return nil
        }

        let navActions = findNavigationActions(in: json, targetScreenId: targetScreenId)

        for action in navActions {
            guard let params = action["params"] as? [String: Any] else { continue }

            if let resolved = await resolveParamsFromDatasource(
                params: params,
                sourceScreenJson: json,
                sourceScreenId: sourceScreenId
            ) {
                return resolved
            }
        }

        return nil
    }

    /// Recursively find all action objects where nextScreen matches the target.
    private func findNavigationActions(in json: Any, targetScreenId: String) -> [[String: Any]] {
        var results: [[String: Any]] = []

        switch json {
        case let dict as [String: Any]:
            if let nextScreen = dict["nextScreen"] as? String,
               nextScreen == targetScreenId,
               dict["type"] as? String == "navigation" {
                results.append(dict)
            }

            for (_, value) in dict {
                results.append(contentsOf: findNavigationActions(in: value, targetScreenId: targetScreenId))
            }

        case let array as [Any]:
            for element in array {
                results.append(contentsOf: findNavigationActions(in: element, targetScreenId: targetScreenId))
            }

        default:
            break
        }

        return results
    }

    /// Given param expressions (e.g., `"{{item.title}}"`) from a navigation action,
    /// find the source screen's collection datasource, load it, and resolve the expressions
    /// against the first item.
    private func resolveParamsFromDatasource(
        params: [String: Any],
        sourceScreenJson: [String: Any],
        sourceScreenId: String
    ) async -> [String: Any]? {
        // `item.*` references mean the param resolves against a collection iteration variable.
        let itemParams = params.filter { _, value in
            guard let str = stringValue(value) else { return false }
            return str.contains("{{item.") || str.contains("{{ item.")
        }

        guard !itemParams.isEmpty else {
            // Params don't reference `item` — they might be direct variable refs.
            // Return the static string values as-is for non-expression params.
            return resolveStaticParams(params)
        }

        guard let content = sourceScreenJson["content"] as? [String: Any],
              let variables = content["variables"] as? [String: Any] else {
            return nil
        }

        // Find a variable backed by an array-typed datasource.
        var datasourceId: String?
        for (_, varDef) in variables {
            guard let def = varDef as? [String: Any],
                  let source = def["source"] as? String,
                  def["type"] as? String == "array" else {
                continue
            }
            datasourceId = source
            break
        }

        guard let dsId = datasourceId else { return nil }

        guard let dsData = try? await dataSource.getDatasource(screenId: sourceScreenId, datasourceId: dsId),
              let dsJson = try? decoder.decode(DatasourceDefinition.self, from: dsData),
              let items = dsJson.rawData as? [Any],
              let firstItem = items.first as? [String: Any] else {
            return nil
        }

        var resolved: [String: Any] = [:]
        for (name, value) in params {
            guard let str = stringValue(value) else {
                resolved[name] = value
                continue
            }
            resolved[name] = resolveExpression(str, item: firstItem)
        }

        return resolved.isEmpty ? nil : resolved
    }

    /// Resolve params that are static values (no `item` references).
    private func resolveStaticParams(_ params: [String: Any]) -> [String: Any] {
        var resolved: [String: Any] = [:]
        for (name, value) in params {
            if let str = stringValue(value) {
                // If it's a pure expression without item refs, use the string as-is
                if !str.contains("{{") {
                    resolved[name] = str
                }
                // Skip expressions we can't resolve without context
            } else {
                resolved[name] = value
            }
        }
        return resolved
    }

    /// Resolve a `{{item.field}}` expression against an item dictionary.
    private func resolveExpression(_ expression: String, item: [String: Any]) -> Any {
        // Simple case: the whole string is a single expression.
        let trimmed = expression.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("{{") && trimmed.hasSuffix("}}") {
            let inner = String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)

            if inner.hasPrefix("item.") {
                let path = String(inner.dropFirst(5))
                return resolveKeyPath(path, in: item) ?? expression
            }
        }

        // String interpolation: "prefix {{item.field}} suffix".
        var result = expression
        var searchStart = result.startIndex

        while searchStart < result.endIndex {
            guard let openRange = result.range(of: "{{", range: searchStart..<result.endIndex),
                  let closeRange = result.range(of: "}}", range: openRange.upperBound..<result.endIndex) else {
                break
            }

            let inner = String(result[openRange.upperBound..<closeRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if inner.hasPrefix("item.") {
                let path = String(inner.dropFirst(5))
                if let value = resolveKeyPath(path, in: item) {
                    let replacement = "\(value)"
                    result.replaceSubrange(openRange.lowerBound..<closeRange.upperBound, with: replacement)
                    searchStart = result.index(openRange.lowerBound, offsetBy: replacement.count)
                    continue
                }
            }

            searchStart = closeRange.upperBound
        }

        return result
    }

    /// Resolve a dot-separated key path against a nested dictionary.
    private func resolveKeyPath(_ path: String, in dict: [String: Any]) -> Any? {
        let components = path.split(separator: ".").map(String.init)
        var current: Any = dict

        for component in components {
            if let d = current as? [String: Any] {
                guard let next = d[component] else { return nil }
                current = next
            } else {
                return nil
            }
        }

        return current
    }

    /// Extract a string from a value, handling AnyCodableValue wrapper.
    private func stringValue(_ value: Any) -> String? {
        if let str = value as? String { return str }
        if let codable = value as? AnyCodableValue, let str = codable.value as? String { return str }
        return nil
    }
}
