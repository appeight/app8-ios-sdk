//
//  VariableStore.swift
//  App8Engine
//

import Foundation
import Combine

/// Main variable storage implementation with dependency tracking
@MainActor
public final class VariableStore: VariableStoreProtocol {
    private var variables: [String: Variable] = [:]
    private let parser = ExpressionParser()
    private let evaluator = ExpressionEvaluator()
    private let dependencyExtractor = DependencyExtractor()
    private var dependencyGraph = DependencyGraph()
    private var isUpdating = false

    private let anyVariableChangedSubject = PassthroughSubject<String, Never>()
    public var anyVariableChanged: AnyPublisher<String, Never> {
        anyVariableChangedSubject.eraseToAnyPublisher()
    }

    private var cancellables = Set<AnyCancellable>()

    /// Optional logger from owning context. Nil when constructed in tests without context.
    weak var logger: A8Log?

    public init() {}

    init(context: App8Context) {
        self.logger = context.logger
    }

    // MARK: - Variable Definition

    public func defineVariable(name: String, definition: VariableDefinition) throws {
        let variable = Variable(name: name, definition: definition)

        if variable.isComputed {
            guard let expression = variable.expression else {
                throw VariableError.invalidExpression("No expression provided for computed variable", underlying: NSError())
            }

            let node = try parser.parse(expression)
            let dependencies = dependencyExtractor.extractDependencies(from: node)

            try checkCircularDependency(name: name, dependencies: dependencies)

            for dependency in dependencies {
                dependencyGraph.addDependency(from: dependency, to: name)
            }

            try updateComputedVariable(variable: variable)
        } else if let rawValue = definition.rawInitialValue as? String, rawValue.contains("{{") {
            // initialValue is an expression string — evaluate it against the current context
            do {
                let node = try parser.parse(rawValue)
                let context = VariableContext(store: self)
                if let evaluatedValue = try evaluator.evaluate(node, context: context) {
                    variable.setValueUnchecked(evaluatedValue)
                }
            } catch {
                logger?.error("Failed to evaluate initialValue expression '\(rawValue)' for '\(name)': \(error)")
            }
        }

        variable.valueChanged
            .sink { [weak self] _ in
                self?.anyVariableChangedSubject.send(name)
            }
            .store(in: &cancellables)

        variables[name] = variable
    }

    // MARK: - Value Access

    public func getValue(name: String) -> Any? {
        return variables[name]?.value
    }

    public func setValue(name: String, value: Any?) throws {
        guard let variable = variables[name] else {
            throw VariableError.undefinedVariable(name)
        }

        try variable.setValue(value)

        if !isUpdating {
            try updateDependentVariables(changedVariable: name)
        }
    }

    public func setMultipleValues(_ updates: [String: Any?]) throws {
        var changedVariables: Set<String> = []

        // Update all variables without triggering dependency updates, then resolve in order
        isUpdating = true

        for (name, value) in updates {
            guard let variable = variables[name] else {
                throw VariableError.undefinedVariable(name)
            }
            try variable.setValue(value)
            changedVariables.insert(name)
        }

        try updateDependentVariablesForMultiple(changedVariables: changedVariables)

        isUpdating = false
    }

    public func hasVariable(name: String) -> Bool {
        return variables[name] != nil
    }

    public func setExternalValue(name: String, value: Any) {
        guard let variable = variables[name] else { return }
        do {
            try variable.setValue(value)
            if !isUpdating {
                try updateDependentVariables(changedVariable: name)
            }
        } catch {
            logger?.error("VariableStore.setExternalValue failed for '\(name)': \(error)")
        }
    }

    public func getAllValues() -> [String: Any?] {
        return variables.reduce(into: [:]) { result, pair in
            result[pair.key] = pair.value.value
        }
    }

    public func getAllVariables() -> [String: Variable] {
        return variables
    }

    public func getParentStore() -> VariableStoreProtocol? {
        return nil
    }

    // MARK: - Reset

    public func reset() {
        variables.removeAll()
        dependencyGraph.reset()
        cancellables.removeAll()
    }

    // MARK: - Computed Variable Updates

    private func updateDependentVariables(changedVariable: String) throws {
        isUpdating = true
        defer { isUpdating = false }

        let dependentVariables = dependencyGraph.getDependents(of: changedVariable)
        let updateOrder = dependencyGraph.getUpdateOrder(for: dependentVariables)

        for variableName in updateOrder {
            if let variable = variables[variableName], variable.isComputed {
                try updateComputedVariable(variable: variable)
            }
        }
    }

    private func updateDependentVariablesForMultiple(changedVariables: Set<String>) throws {
        var allDependentVariables: Set<String> = []

        for changedVariable in changedVariables {
            let dependents = dependencyGraph.getDependents(of: changedVariable)
            allDependentVariables.formUnion(dependents)
        }

        let updateOrder = dependencyGraph.getUpdateOrder(for: allDependentVariables)

        for variableName in updateOrder {
            if let variable = variables[variableName], variable.isComputed {
                try updateComputedVariable(variable: variable)
            }
        }
    }

    private func updateComputedVariable(variable: Variable) throws {
        guard let expression = variable.expression else { return }

        do {
            let node = try parser.parse(expression)
            let dependencies = dependencyExtractor.extractDependencies(from: node)
            let context = VariableContext(store: self)
            let newValue = try evaluator.evaluate(node, context: context)

            variable.setComputedValue(newValue, dependencies: dependencies)
        } catch {
            throw VariableError.computationError(expression, underlying: error)
        }
    }

    // MARK: - Circular Dependency Check

    private func checkCircularDependency(name: String, dependencies: Set<String>) throws {
        var visited = Set<String>()
        var path: [String] = []

        func hasCircularDependency(_ varName: String) -> Bool {
            if path.contains(varName) {
                return true
            }

            if visited.contains(varName) {
                return false
            }

            visited.insert(varName)
            path.append(varName)

            if let variable = variables[varName], variable.isComputed {
                guard let expression = variable.expression else { return false }

                do {
                    let node = try parser.parse(expression)
                    let deps = dependencyExtractor.extractDependencies(from: node)

                    for dep in deps {
                        if hasCircularDependency(dep) {
                            return true
                        }
                    }
                } catch {
                    return false
                }
            }

            path.removeLast()
            return false
        }

        for dependency in dependencies {
            if dependency == name {
                throw VariableError.circularDependency([name])
            }

            path = [name]
            visited = []

            if hasCircularDependency(dependency) {
                throw VariableError.circularDependency(path)
            }
        }
    }
}
