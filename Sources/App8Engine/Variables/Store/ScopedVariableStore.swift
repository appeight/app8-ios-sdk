//
//  ScopedVariableStore.swift
//  App8Engine
//

import Foundation
import Combine

/// Variable store with parent scope chain lookup
/// Used for screen and component-level variables that can access parent scopes
@MainActor
public final class ScopedVariableStore: VariableStoreProtocol {
    /// Parent store for scope chain lookup
    public weak var parent: VariableStoreProtocol?

    /// Local variables at this scope level
    private var localVariables: [String: Variable] = [:]
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

    /// Separate cancellable for parent forwarding — replaced on reparent
    private var parentForwardingCancellable: AnyCancellable?

    /// Optional filter for parent variable change propagation.
    /// When set, only variable names for which the closure returns true
    /// (plus the reparent signal "") are forwarded from parent to children.
    private var parentPropagationFilter: ((String) -> Bool)?

    /// Configure which parent variable changes should propagate to this store.
    /// Pass nil to allow all (default behavior). The empty-string reparent signal
    /// always propagates regardless of the filter.
    public func setParentPropagationFilter(_ filter: ((String) -> Bool)?) {
        self.parentPropagationFilter = filter
        subscribeToParent(parent)
    }

    /// Optional logger from owning context. Inherited from parent if parent is a ScopedVariableStore
    /// or a VariableStore with a logger; nil in tests with no context.
    weak var logger: A8Log?

    public init(parent: VariableStoreProtocol? = nil) {
        self.parent = parent
        if let parent = parent as? ScopedVariableStore {
            self.logger = parent.logger
        } else if let parent = parent as? VariableStore {
            self.logger = parent.logger
        }
        subscribeToParent(parent)
    }

    /// Swap the parent store. The existing VM tree and local variables are preserved.
    /// Only the parent lookup chain and change forwarding are updated.
    /// IMPORTANT: newParent must NOT be self or a descendant of self.
    public func reparent(to newParent: VariableStoreProtocol) {
        guard newParent !== self else { return }
        if parent !== newParent {
            self.parent = newParent
            subscribeToParent(newParent)
        }
        // Notify subscribers so views re-resolve expressions with new parent data.
        // Send empty string (not a specific variable name) so name-based filters
        // on other subscribers still work correctly.
        anyVariableChangedSubject.send("")
    }

    private func subscribeToParent(_ parent: VariableStoreProtocol?) {
        parentForwardingCancellable?.cancel()
        parentForwardingCancellable = nil
        guard let parent = parent else { return }
        parentForwardingCancellable = parent.anyVariableChanged
            .filter { [weak self] variableName in
                // Always forward reparent signal
                guard !variableName.isEmpty else { return true }
                // Apply propagation filter if set
                if let filter = self?.parentPropagationFilter {
                    return filter(variableName)
                }
                return true
            }
            .sink { [weak self] variableName in
                // Recompute local computed variables that depend on the changed parent variable.
                // The dependency graph records cross-scope dependencies at defineVariable time,
                // so getDependents("counter1") correctly returns local computed vars like "count".
                if !variableName.isEmpty {
                    try? self?.updateDependentVariables(changedVariable: variableName)
                }
                self?.anyVariableChangedSubject.send(variableName)
            }
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

        if let value = variable.value, !(value is NSNull) {
            if !definition.type.validate(value) {
                let actual = VariableType.inferType(from: value)
                logger?.warning("Variable '\(name)' declared as \(definition.type.rawValue) but received \(actual.rawValue): \(String(describing: value).prefix(200))")
            }
        } else if variable.value == nil || variable.value is NSNull {
            if !variable.isComputed && definition.computed == nil {
                logger?.debug("Variable '\(name)' (\(definition.type.rawValue)) initialized without a value")
            }
        }

        variable.valueChanged
            .sink { [weak self] _ in
                self?.anyVariableChangedSubject.send(name)
            }
            .store(in: &cancellables)

        localVariables[name] = variable
    }

    // MARK: - Value Access (with scope chain lookup)

    public func getValue(name: String) -> Any? {
        if let local = localVariables[name]?.value {
            return local
        }
        return parent?.getValue(name: name)
    }

    public func setValue(name: String, value: Any?) throws {
        if let variable = localVariables[name] {
            try variable.setValue(value)

            if !isUpdating {
                try updateDependentVariables(changedVariable: name)
            }
            return
        }

        if parent?.hasVariable(name: name) == true {
            try parent?.setValue(name: name, value: value)
            return
        }

        throw VariableError.undefinedVariable(name)
    }

    public func setMultipleValues(_ updates: [String: Any?]) throws {
        var localChanges: Set<String> = []
        var parentUpdates: [String: Any?] = [:]

        isUpdating = true

        for (name, value) in updates {
            if let variable = localVariables[name] {
                try variable.setValue(value)
                localChanges.insert(name)
            } else if parent?.hasVariable(name: name) == true {
                parentUpdates[name] = value
            } else {
                throw VariableError.undefinedVariable(name)
            }
        }

        if !parentUpdates.isEmpty {
            try parent?.setMultipleValues(parentUpdates)
        }

        try updateDependentVariablesForMultiple(changedVariables: localChanges)

        isUpdating = false
    }

    public func hasVariable(name: String) -> Bool {
        return localVariables[name] != nil || (parent?.hasVariable(name: name) ?? false)
    }

    public func setExternalValue(name: String, value: Any) {
        if localVariables[name] != nil {
            do {
                try setValue(name: name, value: value)
            } catch {
                logger?.error("ScopedVariableStore.setExternalValue failed for '\(name)': \(error)")
            }
        } else {
            parent?.setExternalValue(name: name, value: value)
        }
    }

    public func getAllValues() -> [String: Any?] {
        var result = parent?.getAllValues() ?? [:]

        for (key, variable) in localVariables {
            result[key] = variable.value
        }

        return result
    }

    public func getAllVariables() -> [String: Variable] {
        var result = parent?.getAllVariables() ?? [:]

        // Local variables override parent
        for (key, variable) in localVariables {
            result[key] = variable
        }

        return result
    }

    /// Get only local variables (not including parent)
    public func getLocalVariables() -> [String: Variable] {
        return localVariables
    }

    public func getParentStore() -> VariableStoreProtocol? {
        return parent
    }

    // MARK: - Reset

    public func reset() {
        localVariables.removeAll()
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
            if let variable = localVariables[variableName], variable.isComputed {
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
            if let variable = localVariables[variableName], variable.isComputed {
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

            // Check local variables first
            if let variable = localVariables[varName], variable.isComputed {
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
