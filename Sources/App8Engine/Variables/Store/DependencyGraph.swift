//
//  DependencyGraph.swift
//  App8Engine
//

import Foundation

/// Tracks dependencies between computed variables for update ordering
@MainActor
public final class DependencyGraph {
    /// Maps a variable to its dependents (variables that depend on it)
    private var dependents: [String: Set<String>] = [:]

    /// Maps a variable to its dependencies (variables it depends on)
    private var dependencies: [String: Set<String>] = [:]

    public init() {}

    /// Add a dependency relationship: `to` depends on `from`
    /// When `from` changes, `to` needs to be updated
    public func addDependency(from: String, to: String) {
        dependents[from, default: []].insert(to)
        dependencies[to, default: []].insert(from)
    }

    /// Remove all dependencies for a variable
    public func removeDependencies(for variable: String) {
        for (key, _) in dependents {
            dependents[key]?.remove(variable)
        }

        if let deps = dependencies[variable] {
            for dep in deps {
                dependents[dep]?.remove(variable)
            }
        }
        dependencies.removeValue(forKey: variable)
    }

    /// Get all variables that transitively depend on a given variable
    public func getDependents(of variable: String) -> Set<String> {
        var result = Set<String>()
        var queue = [variable]
        var visited = Set<String>()

        while !queue.isEmpty {
            let current = queue.removeFirst()

            if visited.contains(current) {
                continue
            }
            visited.insert(current)

            if let deps = dependents[current] {
                for dep in deps {
                    result.insert(dep)
                    queue.append(dep)
                }
            }
        }

        return result
    }

    /// Get the correct update order for a set of variables using topological sort
    public func getUpdateOrder(for variables: Set<String>) -> [String] {
        var result: [String] = []
        var visited = Set<String>()
        var visiting = Set<String>()

        func topologicalSort(_ variable: String) {
            if visited.contains(variable) {
                return
            }

            if visiting.contains(variable) {
                // Circular dependency detected, skip to avoid infinite loop
                return
            }

            visiting.insert(variable)

            // Visit dependencies before the variable itself
            if let deps = dependencies[variable] {
                for dependency in deps {
                    if variables.contains(dependency) {
                        topologicalSort(dependency)
                    }
                }
            }

            visiting.remove(variable)
            visited.insert(variable)
            result.append(variable)
        }

        for variable in variables {
            topologicalSort(variable)
        }

        return result
    }

    /// Clear all dependencies
    public func reset() {
        dependents.removeAll()
        dependencies.removeAll()
    }
}
