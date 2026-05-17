//
//  ScreenAnalyzer.swift
//  App8Engine
//

import Foundation

/// Analyzes a screen's variable dependencies by combining expression walking
/// with variable declaration inspection.
struct ScreenAnalyzer {

    private let walker = ScreenExpressionWalker()
    private let decoder = JSONDecoder()

    /// Built-in variable names injected by the engine at runtime (collection iteration, events, etc.)
    private static let builtInNames: Set<String> = [
        "item", "index", "section", "event", "$parent"
    ]

    /// Prefix for internal datasource variables injected by the engine
    private static let datasourcePrefix = "__datasource_"

    /// Analyze a preprocessed screen JSON to determine its variable dependencies.
    /// - Parameters:
    ///   - screenData: The screen JSON data (should be preprocessed with templates already merged)
    ///   - screenId: The screen's identifier
    /// - Returns: A `ScreenAnalysis` describing declared and required variables
    func analyze(screenData: Data, screenId: String) -> ScreenAnalysis {
        let allReferenced = walker.extractReferencedVariables(from: screenData)
        let declaredNames = extractAllDeclaredVariableNames(from: screenData)
        let declaredVariables = extractDeclaredVariables(from: screenData)

        // Referenced but not declared locally and not built-in → required param.
        let requiredParams: [ScreenAnalysis.RequiredParam] = allReferenced
            .filter { name in
                !declaredNames.contains(name)
                && !Self.builtInNames.contains(name)
                && !name.hasPrefix(Self.datasourcePrefix)
            }
            .sorted()
            .map { ScreenAnalysis.RequiredParam(name: $0, inferredType: nil) }

        return ScreenAnalysis(
            screenId: screenId,
            declaredVariables: declaredVariables,
            requiredParams: requiredParams
        )
    }

    // MARK: - Private

    /// Extract declared variable metadata from the screen-level `content.variables` field.
    private func extractDeclaredVariables(from data: Data) -> [ScreenAnalysis.DeclaredVariable] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [String: Any],
              let variables = content["variables"] as? [String: Any] else {
            return []
        }

        return variables.compactMap { name, value -> ScreenAnalysis.DeclaredVariable? in
            guard let varDef = value as? [String: Any] else { return nil }
            let type = varDef["type"] as? String ?? "string"

            let source: ScreenAnalysis.DeclaredVariable.VariableSource
            if let dsSource = varDef["source"] as? String {
                source = .datasource(id: dsSource)
            } else if let computed = varDef["computed"] as? String {
                source = .computed(expression: computed)
            } else {
                source = .initialValue
            }

            return ScreenAnalysis.DeclaredVariable(name: name, type: type, source: source)
        }
        .sorted { $0.name < $1.name }
    }

    /// Collect ALL variable names declared anywhere in the component tree (screen-level + nested children).
    /// This avoids false positives for variables declared in child components.
    private func extractAllDeclaredVariableNames(from data: Data) -> Set<String> {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        var names = Set<String>()
        collectVariableNames(from: json, into: &names)
        return names
    }

    /// Recursively walk the JSON tree collecting variable names from any `variables` dictionaries.
    private func collectVariableNames(from value: Any, into names: inout Set<String>) {
        guard let dict = value as? [String: Any] else {
            if let array = value as? [Any] {
                for element in array {
                    collectVariableNames(from: element, into: &names)
                }
            }
            return
        }

        if let variables = dict["variables"] as? [String: Any] {
            for key in variables.keys {
                names.insert(key)
            }
        }

        if let children = dict["children"] as? [Any] {
            for child in children {
                collectVariableNames(from: child, into: &names)
            }
        }

        if let content = dict["content"] as? [String: Any] {
            collectVariableNames(from: content, into: &names)
        }

        if let sections = dict["sections"] as? [Any] {
            for section in sections {
                collectVariableNames(from: section, into: &names)
            }
        }

        if let itemTemplate = dict["itemTemplate"] as? [String: Any] {
            collectVariableNames(from: itemTemplate, into: &names)
        }

        if let header = dict["header"] as? [String: Any] {
            collectVariableNames(from: header, into: &names)
        }
        if let footer = dict["footer"] as? [String: Any] {
            collectVariableNames(from: footer, into: &names)
        }
    }
}
