//
//  ExpressionEvaluator.swift
//  App8Engine
//

import Foundation

/// Evaluates parsed expression nodes against a variable context
@MainActor
public final class ExpressionEvaluator {
    private let allowedFunctions = Set([
        "length", "includes", "match", "filter", "map", "find", "first", "last",
        "parseInt", "parseFloat", "toString",
        "isArray", "keys", "values",
        "round", "floor", "ceil", "abs", "min", "max",
        "formatDate", "formatTime", "formatDuration", "formatMinutes",
        "ageInYears", "daysBetween", "timeAgo", "daysUntil",
        "formatCurrency", "formatNumber", "plural",
        "i18n",
        // String manipulation
        "uppercase", "lowercase", "trim", "replace", "split",
        "substring", "startsWith", "endsWith",
        // Array manipulation
        "sort", "reverse", "join", "concat", "slice"
    ])

    public init() {}

    /// Locale used by `formatDate`/`formatTime`/`formatCurrency`/`formatNumber`.
    /// Defaults to `Locale.current`; `PropertyResolver` overrides it from
    /// `TranslationStore.activeLocaleObject` before each resolve so that the
    /// SDK's `setLocale(...)` override also drives number/date formatting.
    public var locale: Locale = .current

    /// Backs the `i18n(key)` function. Populated by `PropertyResolver` before
    /// each evaluate so the active-locale chain (incl. `Bundle.main` fallback)
    /// applies inside template expressions like `"{{i18n(title)}}"`.
    public var translationLookup: ((String) -> String?)?

    /// AST recursion depth — `evaluate` is the recursion point. The class is
    /// `@MainActor`, so a single counter is safe (no concurrent re-entry).
    private var evalDepth = 0

    /// Heuristic ReDoS guard: true when `pattern` has a quantified group whose
    /// body is also quantified (`(a+)+`, `(.*)*`) — the catastrophic-backtracking shape.
    static func hasNestedQuantifier(_ pattern: String) -> Bool {
        let chars = Array(pattern)
        var groupHasQuantifier: [Bool] = []   // one flag per open '('
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\" { i += 2; continue }   // skip an escaped char
            switch c {
            case "(":
                groupHasQuantifier.append(false)
            case "+", "*", "{":
                if !groupHasQuantifier.isEmpty {
                    groupHasQuantifier[groupHasQuantifier.count - 1] = true
                }
            case ")":
                let innerQuantified = groupHasQuantifier.popLast() ?? false
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                if innerQuantified, let next, next == "+" || next == "*" || next == "{" {
                    return true
                }
            default:
                break
            }
            i += 1
        }
        return false
    }

    public func evaluate(_ node: ExpressionNode, context: VariableContext) throws -> Any? {
        evalDepth += 1
        defer { evalDepth -= 1 }
        guard evalDepth <= EngineLimits.maxExpressionDepth else {
            throw ExpressionError.parseError("expression too deeply nested to evaluate")
        }

        switch node {
        case .literal(let value):
            return value.anyValue

        case .variable(let name):
            if let value = context.getValue(for: name) {
                return value
            }

            // Variable is defined but its value is nil — return nil rather than throwing.
            // This handles computed variables (e.g. first() with no match) and object
            // variables whose value hasn't been populated yet.
            if context.variableExists(name) {
                return nil
            }

            // Check for special variables
            if name == "event" {
                return nil
            }

            throw VariableError.undefinedVariable(name)

        case .binaryOperation(let op, let left, let right):
            return try evaluateBinaryOperation(op, left: left, right: right, context: context)

        case .unaryOperation(let op, let operand):
            return try evaluateUnaryOperation(op, operand: operand, context: context)

        case .functionCall(let name, let arguments):
            return try evaluateFunctionCall(name, arguments: arguments, context: context)

        case .memberAccess(let object, let member):
            return try evaluateMemberAccess(object: object, member: member, context: context)

        case .arrayAccess(let array, let index):
            return try evaluateArrayAccess(array: array, index: index, context: context)

        case .ternary(let condition, let trueValue, let falseValue):
            let conditionValue = try evaluate(condition, context: context)
            let isTrue = toBool(conditionValue)
            return try evaluate(isTrue ? trueValue : falseValue, context: context)
        }
    }

    // MARK: - Binary Operations
    private func evaluateBinaryOperation(_ op: String, left: ExpressionNode, right: ExpressionNode, context: VariableContext) throws -> Any? {
        let leftValue = try evaluate(left, context: context)

        // Short-circuit evaluation for logical operators
        switch op {
        case "&&":
            if !toBool(leftValue) {
                return false
            }
            let rightValue = try evaluate(right, context: context)
            return toBool(rightValue)

        case "||":
            if toBool(leftValue) {
                return true
            }
            let rightValue = try evaluate(right, context: context)
            return toBool(rightValue)

        default:
            let rightValue = try evaluate(right, context: context)

            switch op {
            case "===":
                return isStrictlyEqual(leftValue, rightValue)
            case "!==":
                return !isStrictlyEqual(leftValue, rightValue)
            case "==":
                return isLooselyEqual(leftValue, rightValue)
            case "!=":
                return !isLooselyEqual(leftValue, rightValue)
            case ">":
                return try compare(leftValue, rightValue) > 0
            case ">=":
                return try compare(leftValue, rightValue) >= 0
            case "<":
                return try compare(leftValue, rightValue) < 0
            case "<=":
                return try compare(leftValue, rightValue) <= 0
            case "+":
                return try add(leftValue, rightValue)
            case "-":
                return try subtract(leftValue, rightValue)
            case "*":
                return try multiply(leftValue, rightValue)
            case "/":
                return try divide(leftValue, rightValue)
            case "%":
                return try modulo(leftValue, rightValue)
            default:
                throw ExpressionError.parseError("Unknown operator: \(op)")
            }
        }
    }

    // MARK: - Unary Operations
    private func evaluateUnaryOperation(_ op: String, operand: ExpressionNode, context: VariableContext) throws -> Any? {
        let value = try evaluate(operand, context: context)

        switch op {
        case "!":
            return !toBool(value)
        case "-":
            if let num = toNumber(value) {
                let result = -num
                if result.truncatingRemainder(dividingBy: 1) == 0 {
                    return Int(result)
                }
                return result
            }
            throw ExpressionError.parseError("Cannot negate non-numeric value")
        default:
            throw ExpressionError.parseError("Unknown unary operator: \(op)")
        }
    }

    // MARK: - Function Calls
    private func evaluateFunctionCall(_ name: String, arguments: [ExpressionNode], context: VariableContext) throws -> Any? {
        guard allowedFunctions.contains(name) else {
            throw ExpressionError.parseError("Function '\(name)' is not allowed")
        }

        switch name {
        case "length":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("length() expects 1 argument")
            }
            let value = try evaluate(arguments[0], context: context)

            if let string = value as? String {
                return string.count
            } else if let array = value as? [Any] {
                return array.count
            } else if let array = value as? [Any?] {
                return array.count
            } else if let dict = value as? [String: Any] {
                return dict.count
            } else if let dict = value as? [String: Any?] {
                return dict.count
            }
            return 0

        case "includes":
            guard arguments.count == 2 else {
                throw ExpressionError.parseError("includes() expects 2 arguments")
            }
            let collection = try evaluate(arguments[0], context: context)
            let searchValue = try evaluate(arguments[1], context: context)

            if let string = collection as? String, let searchString = searchValue as? String {
                // Empty search string matches everything (matches JavaScript/Python semantics,
                // and makes live-search expressions trivially work when query is empty).
                if searchString.isEmpty { return true }
                return string.contains(searchString)
            } else if let array = collection as? [Any] {
                return array.contains { isLooselyEqual($0, searchValue) }
            } else if let array = collection as? [Any?] {
                return array.contains { isLooselyEqual($0, searchValue) }
            }
            return false

        case "match":
            guard arguments.count == 2 else {
                throw ExpressionError.parseError("match() expects 2 arguments")
            }
            let string = try evaluate(arguments[0], context: context) as? String ?? ""
            let pattern = try evaluate(arguments[1], context: context) as? String ?? ""

            // Bound the ReDoS surface before compiling an untrusted pattern.
            guard pattern.count <= EngineLimits.maxRegexPatternLength,
                  string.utf16.count <= EngineLimits.maxRegexInputLength else {
                return false
            }
            if Self.hasNestedQuantifier(pattern) { return false }

            do {
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(location: 0, length: string.utf16.count)
                return regex.firstMatch(in: string, options: [], range: range) != nil
            } catch {
                return false
            }

        case "filter":
            guard arguments.count >= 1 else {
                throw ExpressionError.parseError("filter() expects at least 1 argument")
            }
            let array = try evaluate(arguments[0], context: context) as? [Any] ?? []
            guard arguments.count >= 2 else { return array }
            return try array.filter { element in
                toBool(try evaluate(arguments[1], context: context.overlaying("item", value: element)))
            }

        case "map":
            guard arguments.count >= 1 else {
                throw ExpressionError.parseError("map() expects at least 1 argument")
            }
            let array = try evaluate(arguments[0], context: context) as? [Any] ?? []
            guard arguments.count >= 2 else { return array }
            return try array.map { element in
                try evaluate(arguments[1], context: context.overlaying("item", value: element))
            }

        case "find", "first":
            guard arguments.count >= 1 else {
                throw ExpressionError.parseError("\(name)() expects at least 1 argument")
            }
            let array = try evaluate(arguments[0], context: context) as? [Any] ?? []
            guard arguments.count >= 2 else { return array.first }
            return try array.first { element in
                toBool(try evaluate(arguments[1], context: context.overlaying("item", value: element)))
            }

        case "last":
            guard arguments.count >= 1 else {
                throw ExpressionError.parseError("last() expects at least 1 argument")
            }
            let array = try evaluate(arguments[0], context: context) as? [Any] ?? []
            guard arguments.count >= 2 else { return array.last }
            return try array.last { element in
                toBool(try evaluate(arguments[1], context: context.overlaying("item", value: element)))
            }

        case "parseInt":
            guard arguments.count >= 1 else {
                throw ExpressionError.parseError("parseInt() expects at least 1 argument")
            }
            let value = try evaluate(arguments[0], context: context)

            if let num = value as? Int {
                return num
            } else if let num = value as? Double {
                return Int(num)
            } else if let string = value as? String {
                return Int(string) ?? 0
            }
            return 0

        case "parseFloat":
            guard arguments.count >= 1 else {
                throw ExpressionError.parseError("parseFloat() expects at least 1 argument")
            }
            let value = try evaluate(arguments[0], context: context)

            if let num = value as? Double {
                return num
            } else if let num = value as? Int {
                return Double(num)
            } else if let string = value as? String {
                return Double(string) ?? 0.0
            }
            return 0.0

        case "toString":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("toString() expects 1 argument")
            }
            let value = try evaluate(arguments[0], context: context)
            return toString(value)

        case "isArray":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("isArray() expects 1 argument")
            }
            let value = try evaluate(arguments[0], context: context)
            return value is [Any]

        case "keys":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("keys() expects 1 argument")
            }
            let value = try evaluate(arguments[0], context: context)

            if let dict = value as? [String: Any] {
                return Array(dict.keys)
            }
            return [] as [String]

        case "values":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("values() expects 1 argument")
            }
            let value = try evaluate(arguments[0], context: context)

            if let dict = value as? [String: Any] {
                return Array(dict.values)
            }
            return [] as [Any]

        // MARK: - String functions

        case "uppercase":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("uppercase() expects 1 argument")
            }
            return (try evaluate(arguments[0], context: context) as? String)?.uppercased() ?? ""

        case "lowercase":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("lowercase() expects 1 argument")
            }
            return (try evaluate(arguments[0], context: context) as? String)?.lowercased() ?? ""

        case "trim":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("trim() expects 1 argument")
            }
            return (try evaluate(arguments[0], context: context) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        case "replace":
            guard arguments.count == 3 else {
                throw ExpressionError.parseError("replace() expects 3 arguments (string, from, to)")
            }
            let s = try evaluate(arguments[0], context: context) as? String ?? ""
            let from = try evaluate(arguments[1], context: context) as? String ?? ""
            let to = try evaluate(arguments[2], context: context) as? String ?? ""
            guard !from.isEmpty else { return s }
            return s.replacingOccurrences(of: from, with: to)

        case "split":
            guard arguments.count == 2 else {
                throw ExpressionError.parseError("split() expects 2 arguments (string, separator)")
            }
            let s = try evaluate(arguments[0], context: context) as? String ?? ""
            let sep = try evaluate(arguments[1], context: context) as? String ?? ""
            if sep.isEmpty {
                return s.map { String($0) }
            }
            return s.components(separatedBy: sep)

        case "substring":
            guard (2...3).contains(arguments.count) else {
                throw ExpressionError.parseError("substring() expects 2 or 3 arguments (string, start, length?)")
            }
            let s = try evaluate(arguments[0], context: context) as? String ?? ""
            guard let start = toNumber(try evaluate(arguments[1], context: context)) else { return "" }
            let count = s.count
            // Clamp before `Int(...)` — NaN/infinity/out-of-range would trap.
            let startIdx = start.isNaN ? 0 : Int(min(max(start, 0), Double(count)))
            let from = s.index(s.startIndex, offsetBy: startIdx)
            if arguments.count == 3 {
                guard let length = toNumber(try evaluate(arguments[2], context: context)) else { return "" }
                let safeLength = (length.isNaN || length < 0) ? 0 : Int(min(length, Double(count)))
                let endIdx = min(startIdx + safeLength, count)
                let to = s.index(s.startIndex, offsetBy: endIdx)
                return String(s[from..<to])
            }
            return String(s[from...])

        case "startsWith":
            guard arguments.count == 2 else {
                throw ExpressionError.parseError("startsWith() expects 2 arguments")
            }
            let s = try evaluate(arguments[0], context: context) as? String ?? ""
            let prefix = try evaluate(arguments[1], context: context) as? String ?? ""
            return s.hasPrefix(prefix)

        case "endsWith":
            guard arguments.count == 2 else {
                throw ExpressionError.parseError("endsWith() expects 2 arguments")
            }
            let s = try evaluate(arguments[0], context: context) as? String ?? ""
            let suffix = try evaluate(arguments[1], context: context) as? String ?? ""
            return s.hasSuffix(suffix)

        // MARK: - Array functions

        case "sort":
            guard (1...2).contains(arguments.count) else {
                throw ExpressionError.parseError("sort() expects 1 or 2 arguments (array, ascending?)")
            }
            let arr = try evaluate(arguments[0], context: context) as? [Any] ?? []
            let ascending: Bool = arguments.count == 2
                ? (try evaluate(arguments[1], context: context) as? Bool ?? true)
                : true
            return arr.sorted { a, b in
                let cmp = compareForSort(a, b)
                return ascending ? cmp < 0 : cmp > 0
            }

        case "reverse":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("reverse() expects 1 argument")
            }
            let arr = try evaluate(arguments[0], context: context) as? [Any] ?? []
            return Array(arr.reversed())

        case "join":
            guard arguments.count == 2 else {
                throw ExpressionError.parseError("join() expects 2 arguments (array, separator)")
            }
            let arr = try evaluate(arguments[0], context: context) as? [Any] ?? []
            let sep = try evaluate(arguments[1], context: context) as? String ?? ""
            return arr.map { stringify($0) }.joined(separator: sep)

        case "concat":
            guard arguments.count >= 2 else {
                throw ExpressionError.parseError("concat() expects at least 2 arguments")
            }
            var result: [Any] = []
            for arg in arguments {
                if let arr = try evaluate(arg, context: context) as? [Any] {
                    result.append(contentsOf: arr)
                }
            }
            return result

        case "slice":
            guard (2...3).contains(arguments.count) else {
                throw ExpressionError.parseError("slice() expects 2 or 3 arguments (array, start, end?)")
            }
            let arr = try evaluate(arguments[0], context: context) as? [Any] ?? []
            guard let start = toNumber(try evaluate(arguments[1], context: context)) else { return [] as [Any] }
            let startIdx = max(0, min(Int(start), arr.count))
            let endIdx: Int
            if arguments.count == 3 {
                guard let e = toNumber(try evaluate(arguments[2], context: context)) else { return [] as [Any] }
                endIdx = max(startIdx, min(Int(e), arr.count))
            } else {
                endIdx = arr.count
            }
            return Array(arr[startIdx..<endIdx])

        case "round":
            guard (1...2).contains(arguments.count) else {
                throw ExpressionError.parseError("round() expects 1 or 2 arguments")
            }
            let value = try evaluate(arguments[0], context: context)
            if arguments.count == 2 {
                let decimalsValue = try evaluate(arguments[1], context: context)
                if let num = toNumber(value), let decimals = toNumber(decimalsValue) {
                    let factor = pow(10.0, decimals)
                    return (num * factor).rounded() / factor
                }
                return value
            }
            if let num = toNumber(value) {
                return Int(num.rounded())
            }
            return 0

        case "floor":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("floor() expects 1 argument")
            }
            let value = try evaluate(arguments[0], context: context)
            if let num = toNumber(value) {
                return Int(floor(num))
            }
            return 0

        case "ceil":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("ceil() expects 1 argument")
            }
            let value = try evaluate(arguments[0], context: context)
            if let num = toNumber(value) {
                return Int(ceil(num))
            }
            return 0

        case "abs":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("abs() expects 1 argument")
            }
            let value = try evaluate(arguments[0], context: context)
            if let num = toNumber(value) {
                let result = Swift.abs(num)
                if result.truncatingRemainder(dividingBy: 1) == 0 {
                    return Int(result)
                }
                return result
            }
            return 0

        case "min":
            guard arguments.count >= 2 else {
                throw ExpressionError.parseError("min() expects at least 2 arguments")
            }
            var minValue: Double?
            for arg in arguments {
                let value = try evaluate(arg, context: context)
                if let num = toNumber(value) {
                    if let current = minValue {
                        minValue = Swift.min(current, num)
                    } else {
                        minValue = num
                    }
                }
            }
            if let result = minValue {
                if result.truncatingRemainder(dividingBy: 1) == 0 {
                    return Int(result)
                }
                return result
            }
            return 0

        case "max":
            guard arguments.count >= 2 else {
                throw ExpressionError.parseError("max() expects at least 2 arguments")
            }
            var maxValue: Double?
            for arg in arguments {
                let value = try evaluate(arg, context: context)
                if let num = toNumber(value) {
                    if let current = maxValue {
                        maxValue = Swift.max(current, num)
                    } else {
                        maxValue = num
                    }
                }
            }
            if let result = maxValue {
                if result.truncatingRemainder(dividingBy: 1) == 0 {
                    return Int(result)
                }
                return result
            }
            return 0

        // MARK: Formatting — Date & Time

        case "formatDate":
            guard (1...2).contains(arguments.count) else {
                throw ExpressionError.parseError("formatDate() expects 1 or 2 arguments")
            }
            let dateVal = try evaluate(arguments[0], context: context)
            guard let date = parseDate(dateVal) else { return "" }
            let style = arguments.count == 2 ? toString(try evaluate(arguments[1], context: context)) : "medium"
            let fmt = DateFormatter()
            fmt.locale = self.locale
            switch style {
            case "short":        fmt.dateFormat = "MMM d"
            case "medium":       fmt.dateFormat = "MMM d, yyyy"
            case "long":         fmt.dateFormat = "MMMM d, yyyy"
            case "weekday":      fmt.dateFormat = "EEEE, MMM d"
            case "weekdayShort": fmt.dateFormat = "EEE"
            default:             fmt.dateFormat = style
            }
            return fmt.string(from: date)

        case "formatTime":
            guard (1...2).contains(arguments.count) else {
                throw ExpressionError.parseError("formatTime() expects 1 or 2 arguments")
            }
            let dateVal = try evaluate(arguments[0], context: context)
            guard let date = parseDate(dateVal) else { return "" }
            let timeFormat = arguments.count == 2 ? toString(try evaluate(arguments[1], context: context)) : "12h"
            let fmt = DateFormatter()
            fmt.locale = self.locale
            fmt.dateFormat = timeFormat == "24h" ? "HH:mm" : "h:mm a"
            return fmt.string(from: date)

        case "formatDuration":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("formatDuration() expects 1 argument")
            }
            let value = try evaluate(arguments[0], context: context)
            let totalSeconds = Int(toNumber(value) ?? 0)
            let h = totalSeconds / 3600
            let m = (totalSeconds % 3600) / 60
            let s = totalSeconds % 60
            if h > 0 {
                return String(format: "%d:%02d:%02d", h, m, s)
            }
            return String(format: "%d:%02d", m, s)

        case "formatMinutes":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("formatMinutes() expects 1 argument")
            }
            let value = try evaluate(arguments[0], context: context)
            let total = Int(toNumber(value) ?? 0)
            let h = total / 60
            let m = total % 60
            if h == 0 { return "\(total) min" }
            if m == 0 { return "\(h)h" }
            return "\(h)h \(m)min"

        case "ageInYears":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("ageInYears() expects 1 argument")
            }
            let dateVal = try evaluate(arguments[0], context: context)
            guard let birthdate = parseDate(dateVal) else { return 0 }
            let years = Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year ?? 0
            return max(0, years)

        case "daysBetween":
            guard arguments.count == 2 else {
                throw ExpressionError.parseError("daysBetween() expects 2 arguments")
            }
            let startVal = try evaluate(arguments[0], context: context)
            let endVal   = try evaluate(arguments[1], context: context)
            guard let start = parseDate(startVal), let end = parseDate(endVal) else { return 0 }
            let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
            return Swift.abs(days)

        case "timeAgo":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("timeAgo() expects 1 argument")
            }
            let dateVal = try evaluate(arguments[0], context: context)
            guard let date = parseDate(dateVal) else { return "" }
            let seconds = Int(Date().timeIntervalSince(date))
            if seconds < 60 { return "just now" }
            let minutes = seconds / 60
            if minutes < 60 { return "\(minutes) minute\(minutes == 1 ? "" : "s") ago" }
            let hours = minutes / 60
            if hours < 24 { return "\(hours) hour\(hours == 1 ? "" : "s") ago" }
            let days = hours / 24
            if days == 1 { return "yesterday" }
            return "\(days) days ago"

        case "daysUntil":
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("daysUntil() expects 1 argument")
            }
            let dateVal = try evaluate(arguments[0], context: context)
            guard let future = parseDate(dateVal) else { return 0 }
            let today = Calendar.current.startOfDay(for: Date())
            let target = Calendar.current.startOfDay(for: future)
            return Calendar.current.dateComponents([.day], from: today, to: target).day ?? 0

        // MARK: Formatting — Number & Currency

        case "formatCurrency":
            guard (1...2).contains(arguments.count) else {
                throw ExpressionError.parseError("formatCurrency() expects 1 or 2 arguments")
            }
            let value = try evaluate(arguments[0], context: context)
            guard let num = toNumber(value) else { return "" }
            let currFmt = NumberFormatter()
            currFmt.numberStyle = .currency
            currFmt.locale = self.locale
            if arguments.count == 2 {
                let code = toString(try evaluate(arguments[1], context: context))
                currFmt.currencyCode = code
            }
            return currFmt.string(from: NSNumber(value: num)) ?? ""

        case "formatNumber":
            guard (1...2).contains(arguments.count) else {
                throw ExpressionError.parseError("formatNumber() expects 1 or 2 arguments")
            }
            let value = try evaluate(arguments[0], context: context)
            guard let num = toNumber(value) else { return "" }
            let numStyle = arguments.count == 2 ? toString(try evaluate(arguments[1], context: context)) : "decimal"
            if numStyle == "percent" {
                return "\(Int((num * 100).rounded()))%"
            }
            let numFmt = NumberFormatter()
            numFmt.numberStyle = .decimal
            numFmt.locale = self.locale
            return numFmt.string(from: NSNumber(value: num)) ?? toString(value)

        // MARK: Formatting — String

        case "plural":
            guard arguments.count == 3 else {
                throw ExpressionError.parseError("plural() expects 3 arguments: count, singular, plural")
            }
            let countVal    = try evaluate(arguments[0], context: context)
            let singularVal = toString(try evaluate(arguments[1], context: context))
            let pluralVal   = toString(try evaluate(arguments[2], context: context))
            let count = Int(toNumber(countVal) ?? 0)
            return count == 1 ? "\(count) \(singularVal)" : "\(count) \(pluralVal)"

        case "i18n":
            // Inline form of the `{"$i18n": "key"}` marker — same lookup chain.
            // On miss returns the key itself so unlocalised values are visible.
            guard arguments.count == 1 else {
                throw ExpressionError.parseError("i18n() expects 1 argument: key")
            }
            let key = toString(try evaluate(arguments[0], context: context))
            return translationLookup?(key) ?? key

        default:
            throw ExpressionError.parseError("Unknown function: \(name)")
        }
    }

    // MARK: - Member Access
    private func evaluateMemberAccess(object: ExpressionNode, member: String, context: VariableContext) throws -> Any? {
        let objectValue = try evaluate(object, context: context)

        // Handle dictionary access (both [String: Any] and [String: Any?] from getAllValues())
        if let dict = objectValue as? [String: Any] {
            return dict[member]
        } else if let dict = objectValue as? [String: Any?] {
            return dict[member] ?? nil
        }

        // Handle special properties
        if let string = objectValue as? String {
            switch member {
            case "length":
                return string.count
            default:
                break
            }
        } else if let array = objectValue as? [Any] {
            switch member {
            case "length":
                return array.count
            default:
                break
            }
        }

        return nil
    }

    // MARK: - Array Access
    private func evaluateArrayAccess(array: ExpressionNode, index: ExpressionNode, context: VariableContext) throws -> Any? {
        let arrayValue = try evaluate(array, context: context)
        let indexValue = try evaluate(index, context: context)

        guard let array = arrayValue as? [Any] else {
            return nil
        }

        guard let index = toNumber(indexValue).map({ Int($0) }) else {
            throw ExpressionError.parseError("Array index must be a number")
        }

        guard index >= 0 && index < array.count else {
            return nil
        }

        return array[index]
    }

    // MARK: - Helper Methods
    private func toBool(_ value: Any?) -> Bool {
        if let bool = value as? Bool {
            return bool
        }
        if let num = value as? NSNumber {
            return num.boolValue
        }
        if let string = value as? String {
            return !string.isEmpty
        }
        if let array = value as? [Any] {
            return !array.isEmpty
        }
        if let dict = value as? [String: Any] {
            return !dict.isEmpty
        }
        if value == nil || value is NSNull {
            return false
        }
        return true
    }

    private func stringify(_ value: Any?) -> String {
        guard let value = value else { return "" }
        if let s = value as? String { return s }
        if let i = value as? Int { return String(i) }
        if let d = value as? Double {
            // Drop trailing ".0" for whole-number doubles
            return d.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(d))
                : String(d)
        }
        if let b = value as? Bool { return b ? "true" : "false" }
        if value is NSNull { return "" }
        return "\(value)"
    }

    /// Loose comparison for sort: returns -1 if a<b, 0 if equal, 1 if a>b.
    /// Numbers compare numerically, strings compare lexicographically,
    /// mixed types fall back to stringified comparison.
    private func compareForSort(_ a: Any, _ b: Any) -> Int {
        if let na = toNumber(a), let nb = toNumber(b) {
            if na < nb { return -1 }
            if na > nb { return 1 }
            return 0
        }
        let sa = stringify(a)
        let sb = stringify(b)
        if sa < sb { return -1 }
        if sa > sb { return 1 }
        return 0
    }

    private func toNumber(_ value: Any?) -> Double? {
        if let num = value as? Double {
            return num
        }
        if let num = value as? Int {
            return Double(num)
        }
        if let num = value as? NSNumber {
            return num.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private func toString(_ value: Any?) -> String {
        if let string = value as? String {
            return string
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let num = value as? Int {
            return String(num)
        }
        if let num = value as? Double {
            return String(num)
        }
        if value == nil || value is NSNull {
            return ""
        }
        return String(describing: value)
    }

    private func parseDate(_ value: Any?) -> Date? {
        guard let str = value as? String else { return nil }
        // Full datetime with timezone — ISO8601 handles this correctly
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: str) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: str) { return d }
        // Date-only (yyyy-MM-dd): parse in local timezone so that
        // Calendar.startOfDay gives the correct local date, not a UTC-shifted one
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.timeZone = Calendar.current.timeZone
        if let d = dateFmt.date(from: str) { return d }
        return nil
    }

    private func isStrictlyEqual(_ left: Any?, _ right: Any?) -> Bool {
        if left == nil && right == nil { return true }
        if left is NSNull && right is NSNull { return true }
        if left == nil || right == nil { return false }
        if left is NSNull || right is NSNull { return false }

        if let leftString = left as? String, let rightString = right as? String {
            return leftString == rightString
        }
        if let leftBool = left as? Bool, let rightBool = right as? Bool {
            return leftBool == rightBool
        }
        if let leftInt = left as? Int, let rightInt = right as? Int {
            return leftInt == rightInt
        }
        if let leftDouble = left as? Double, let rightDouble = right as? Double {
            return leftDouble == rightDouble
        }
        if let leftArray = left as? [Any], let rightArray = right as? [Any] {
            return leftArray.count == rightArray.count &&
                   zip(leftArray, rightArray).allSatisfy { isStrictlyEqual($0.0, $0.1) }
        }
        if let leftDict = left as? [String: Any], let rightDict = right as? [String: Any] {
            return leftDict.count == rightDict.count &&
                   leftDict.allSatisfy { key, value in
                       rightDict[key].map { isStrictlyEqual(value, $0) } ?? false
                   }
        }

        return false
    }

    private func isLooselyEqual(_ left: Any?, _ right: Any?) -> Bool {
        if left == nil && right == nil { return true }
        if left is NSNull && right is NSNull { return true }
        if (left == nil && right is NSNull) || (left is NSNull && right == nil) { return true }

        if let leftNum = toNumber(left), let rightNum = toNumber(right) {
            return leftNum == rightNum
        }

        if left is String || right is String {
            let leftString = toString(left)
            let rightString = toString(right)
            return leftString == rightString
        }

        if let leftBool = left as? Bool, let rightBool = right as? Bool {
            return leftBool == rightBool
        }

        return false
    }

    private func compare(_ left: Any?, _ right: Any?) throws -> Int {
        if let leftNum = toNumber(left), let rightNum = toNumber(right) {
            if leftNum < rightNum { return -1 }
            if leftNum > rightNum { return 1 }
            return 0
        }

        let leftString = toString(left)
        let rightString = toString(right)
        return leftString.compare(rightString).rawValue
    }

    private func add(_ left: Any?, _ right: Any?) throws -> Any {
        if left is String || right is String {
            return toString(left) + toString(right)
        }

        if let leftNum = toNumber(left), let rightNum = toNumber(right) {
            let result = leftNum + rightNum
            if result.truncatingRemainder(dividingBy: 1) == 0 {
                return Int(result)
            }
            return result
        }

        if let leftArray = left as? [Any], let rightArray = right as? [Any] {
            return leftArray + rightArray
        }

        throw ExpressionError.parseError("Cannot add values of incompatible types")
    }

    private func subtract(_ left: Any?, _ right: Any?) throws -> Any {
        guard let leftNum = toNumber(left), let rightNum = toNumber(right) else {
            throw ExpressionError.parseError("Cannot subtract non-numeric values")
        }

        let result = leftNum - rightNum
        if result.truncatingRemainder(dividingBy: 1) == 0 {
            return Int(result)
        }
        return result
    }

    private func multiply(_ left: Any?, _ right: Any?) throws -> Any {
        guard let leftNum = toNumber(left), let rightNum = toNumber(right) else {
            throw ExpressionError.parseError("Cannot multiply non-numeric values")
        }

        let result = leftNum * rightNum
        if result.truncatingRemainder(dividingBy: 1) == 0 {
            return Int(result)
        }
        return result
    }

    private func divide(_ left: Any?, _ right: Any?) throws -> Any {
        guard let leftNum = toNumber(left), let rightNum = toNumber(right) else {
            throw ExpressionError.parseError("Cannot divide non-numeric values")
        }

        guard rightNum != 0 else {
            throw ExpressionError.parseError("Division by zero")
        }

        return leftNum / rightNum
    }

    private func modulo(_ left: Any?, _ right: Any?) throws -> Any {
        guard let leftNum = toNumber(left), let rightNum = toNumber(right) else {
            throw ExpressionError.parseError("Cannot modulo non-numeric values")
        }

        guard rightNum != 0 else {
            throw ExpressionError.parseError("Modulo by zero")
        }

        let result = leftNum.truncatingRemainder(dividingBy: rightNum)
        if result.truncatingRemainder(dividingBy: 1) == 0 {
            return Int(result)
        }
        return result
    }
}
