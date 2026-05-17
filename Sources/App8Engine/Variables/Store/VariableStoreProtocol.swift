//
//  VariableStoreProtocol.swift
//  App8Engine
//

import Foundation
import Combine

/// Protocol for variable storage implementations
@MainActor
public protocol VariableStoreProtocol: AnyObject {
    /// Define a new variable
    func defineVariable(name: String, definition: VariableDefinition) throws

    /// Define multiple variables at once, resolving them in dependency order so that
    /// computed variables always see their sibling dependencies already initialized.
    func defineVariables(_ definitions: [String: VariableDefinition]) throws

    /// Get the value of a variable
    func getValue(name: String) -> Any?

    /// Set the value of a variable
    func setValue(name: String, value: Any?) throws

    /// Set multiple values at once (batch update)
    func setMultipleValues(_ updates: [String: Any?]) throws

    /// Set a variable value from an external source (streaming fast path).
    /// Silently ignores unknown variable names — does not throw.
    func setExternalValue(name: String, value: Any)

    /// Check if a variable exists
    func hasVariable(name: String) -> Bool

    /// Get all variable values
    func getAllValues() -> [String: Any?]

    /// Get all variable instances
    func getAllVariables() -> [String: Variable]

    /// Publisher for any variable changes
    var anyVariableChanged: AnyPublisher<String, Never> { get }

    /// Get parent store (for $parent access in nested scopes)
    func getParentStore() -> VariableStoreProtocol?

    /// Reset the store
    func reset()
}

public extension VariableStoreProtocol {
    /// Default implementation: topologically sorts `definitions` so that each computed
    /// variable is defined only after all of its local sibling dependencies exist.
    /// Non-local dependencies (parent-scope variables) are ignored during sorting since
    /// they are already available in the store's parent at definition time.
    func defineVariables(_ definitions: [String: VariableDefinition]) throws {
        let parser = ExpressionParser()
        let extractor = DependencyExtractor()

        var sorted: [(String, VariableDefinition)] = []
        var visited = Set<String>()

        func visit(_ name: String) {
            guard !visited.contains(name), let definition = definitions[name] else { return }
            visited.insert(name)
            // For computed vars and non-computed vars with expression initialValues,
            // ensure same-batch dependencies are visited first
            let expressionToSort: String?
            if let computed = definition.computed {
                expressionToSort = computed
            } else if let raw = definition.rawInitialValue as? String, raw.contains("{{") {
                expressionToSort = raw
            } else {
                expressionToSort = nil
            }
            if let expression = expressionToSort,
               let node = try? parser.parse(expression) {
                for dep in extractor.extractDependencies(from: node) where definitions[dep] != nil {
                    visit(dep)
                }
            }
            sorted.append((name, definition))
        }

        for name in definitions.keys { visit(name) }

        for (name, definition) in sorted {
            try defineVariable(name: name, definition: definition)
        }
    }
}
