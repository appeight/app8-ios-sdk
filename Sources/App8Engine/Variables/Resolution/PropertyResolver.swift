//
//  PropertyResolver.swift
//  App8Engine
//

import Foundation

/// Resolves {{expression}} placeholders in property values
@MainActor
public final class PropertyResolver {
    private let parser = ExpressionParser()
    private let evaluator = ExpressionEvaluator()

    public init() {}

    /// Check if a string contains expression placeholders
    public func containsExpression(_ string: String) -> Bool {
        return string.contains("{{") && string.contains("}}")
    }

    /// Resolve all expressions in a string value
    /// - Parameters:
    ///   - value: The string potentially containing {{expression}} placeholders
    ///   - context: Variable context for evaluation
    /// - Returns: Resolved string with expressions evaluated
    public func resolve(_ value: String, context: VariableContext) throws -> Any {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        // A single whole-string expression returns the raw result, not stringified
        if trimmed.hasPrefix("{{") && trimmed.hasSuffix("}}") {
            let innerContent = String(trimmed.dropFirst(2).dropLast(2))
            if !innerContent.contains("{{") && !innerContent.contains("}}") {
                let node = try parser.parse(value)
                return try evaluator.evaluate(node, context: context) ?? NSNull()
            }
        }

        return try resolveInterpolated(value, context: context)
    }

    /// Resolve expressions and always return a string (for text properties)
    public func resolveToString(_ value: String, context: VariableContext) throws -> String {
        let result = try resolve(value, context: context)
        return stringify(result)
    }

    /// Resolve a value that might be Any type
    public func resolveAny(_ value: Any, context: VariableContext) throws -> Any {
        if let stringValue = value as? String {
            if containsExpression(stringValue) {
                return try resolve(stringValue, context: context)
            }
            return stringValue
        }

        if let arrayValue = value as? [Any] {
            return try arrayValue.map { try resolveAny($0, context: context) }
        }

        if let dictValue = value as? [String: Any] {
            return try dictValue.mapValues { try resolveAny($0, context: context) }
        }

        return value
    }

    // MARK: - Private

    private func resolveInterpolated(_ value: String, context: VariableContext) throws -> String {
        var result = ""
        var remaining = value[...]

        while let startRange = remaining.range(of: "{{") {
            result += remaining[..<startRange.lowerBound]

            let afterStart = remaining[startRange.upperBound...]
            guard let endRange = afterStart.range(of: "}}") else {
                // No closing }}, treat rest as literal
                result += remaining[startRange.lowerBound...]
                remaining = remaining[remaining.endIndex...]
                break
            }

            let expression = String(afterStart[..<endRange.lowerBound])
            let fullExpression = "{{\(expression)}}"

            do {
                let node = try parser.parse(fullExpression)
                let evaluated = try evaluator.evaluate(node, context: context)
                result += stringify(evaluated)
            } catch {
                // On error, keep the original expression
                result += fullExpression
            }

            remaining = afterStart[endRange.upperBound...]
        }

        result += remaining

        return result
    }

    private func stringify(_ value: Any?) -> String {
        guard let value = value else { return "" }

        if value is NSNull { return "" }

        if let string = value as? String {
            return string
        }

        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }

        if let int = value as? Int {
            return String(int)
        }

        if let double = value as? Double {
            if double.truncatingRemainder(dividingBy: 1) == 0 {
                return String(Int(double))
            }
            return String(double)
        }

        return String(describing: value)
    }
}
