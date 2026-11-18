//
//  DependencyExtractor.swift
//  App8Engine
//

import Foundation

/// Extracts variable names that an expression depends on
public final class DependencyExtractor: Sendable {
    public init() {}

    /// Pseudo-variable that `now()` / `today()` depend on. The engine signals
    /// it when a screen appears and on every `timer` tick, so clock-reading
    /// expressions (and computed variables) re-evaluate then.
    public static let clockDependency = "$now"

    /// Extract all variable names referenced in an expression
    public func extractDependencies(from node: ExpressionNode) -> Set<String> {
        var dependencies = Set<String>()
        extractDependenciesRecursive(from: node, into: &dependencies)
        return dependencies
    }

    private func extractDependenciesRecursive(from node: ExpressionNode, into dependencies: inout Set<String>) {
        switch node {
        case .variable(let name):
            dependencies.insert(name)

        case .binaryOperation(_, let left, let right):
            extractDependenciesRecursive(from: left, into: &dependencies)
            extractDependenciesRecursive(from: right, into: &dependencies)

        case .unaryOperation(_, let operand):
            extractDependenciesRecursive(from: operand, into: &dependencies)

        case .functionCall(let name, let arguments):
            if name == "now" || name == "today" {
                dependencies.insert(Self.clockDependency)
            }
            let higherOrderFunctions: Set<String> = ["filter", "map", "find", "first"]
            if higherOrderFunctions.contains(name), arguments.count >= 2 {
                // Array argument — extract dependencies normally
                extractDependenciesRecursive(from: arguments[0], into: &dependencies)
                // Predicate argument — extract deps but exclude "item" (synthetic loop variable)
                var predicateDeps = Set<String>()
                extractDependenciesRecursive(from: arguments[1], into: &predicateDeps)
                predicateDeps.remove("item")
                dependencies.formUnion(predicateDeps)
            } else {
                for arg in arguments {
                    extractDependenciesRecursive(from: arg, into: &dependencies)
                }
            }

        case .memberAccess(let object, _):
            extractDependenciesRecursive(from: object, into: &dependencies)

        case .arrayAccess(let array, let index):
            extractDependenciesRecursive(from: array, into: &dependencies)
            extractDependenciesRecursive(from: index, into: &dependencies)

        case .ternary(let condition, let trueValue, let falseValue):
            extractDependenciesRecursive(from: condition, into: &dependencies)
            extractDependenciesRecursive(from: trueValue, into: &dependencies)
            extractDependenciesRecursive(from: falseValue, into: &dependencies)

        case .arrayLiteral(let elements):
            for element in elements {
                extractDependenciesRecursive(from: element, into: &dependencies)
            }

        case .objectLiteral(let entries):
            for entry in entries {
                extractDependenciesRecursive(from: entry.value, into: &dependencies)
            }

        case .literal:
            break
        }
    }
}
