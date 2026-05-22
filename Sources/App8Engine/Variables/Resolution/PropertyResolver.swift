//
//  PropertyResolver.swift
//  App8Engine
//

import Foundation

/// Resolves {{expression}} placeholders in property values.
///
/// Also owns the i18n lookup chain (`LocalizedString` → translated string,
/// then `{{var}}` interpolation on top). When constructed with a
/// `TranslationStore`, lookups follow the store's active-locale rules and
/// number/date formatters in `ExpressionEvaluator` honour the same locale.
@MainActor
public final class PropertyResolver {
    private let parser = ExpressionParser()
    private let evaluator = ExpressionEvaluator()
    private weak var translationStore: TranslationStore?

    public init(translationStore: TranslationStore? = nil) {
        self.translationStore = translationStore
    }

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
        syncEvaluatorLocale()
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

    /// Resolve a `LocalizedString` to a final user-facing string.
    /// Pipeline: i18n lookup → `{{var}}` interpolation on the looked-up text.
    ///
    /// `.literal` values go straight to `resolveToString`, preserving existing
    /// behaviour. `.key` values look up via the `TranslationStore`'s fallback
    /// chain (active → language-only → app default); a miss returns the key
    /// itself so authors immediately see which key is unlocalised.
    public func resolveLocalizedToString(_ value: LocalizedString, context: VariableContext) throws -> String {
        switch value {
        case .literal(let s):
            return try resolveToString(s, context: context)
        case .key(let k):
            let raw = translationStore?.lookup(key: k) ?? k
            return try resolveToString(raw, context: context)
        }
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

    /// Push state from the TranslationStore into the shared evaluator before
    /// each evaluate: (a) active locale for `formatDate`/`formatCurrency`/etc.
    /// honouring `setLocale(...)`, and (b) translation lookup closure for the
    /// `i18n(key)` function so template expressions can i18n variable values.
    private func syncEvaluatorLocale() {
        guard let store = translationStore else { return }
        evaluator.locale = store.activeLocaleObject
        evaluator.translationLookup = { [weak store] key in store?.lookup(key: key) }
    }

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
