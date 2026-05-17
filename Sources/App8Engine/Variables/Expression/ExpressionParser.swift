//
//  ExpressionParser.swift
//  App8Engine
//

import Foundation

// MARK: - Token Types
enum TokenType: Equatable {
    case literal(LiteralValue)
    case identifier(String)
    case `operator`(String)
    case leftParen
    case rightParen
    case leftBracket
    case rightBracket
    case comma
    case dot
    case question
    case colon
    case eof

    static func == (lhs: TokenType, rhs: TokenType) -> Bool {
        switch (lhs, rhs) {
        case (.leftParen, .leftParen),
             (.rightParen, .rightParen),
             (.leftBracket, .leftBracket),
             (.rightBracket, .rightBracket),
             (.comma, .comma),
             (.dot, .dot),
             (.question, .question),
             (.colon, .colon),
             (.eof, .eof):
            return true
        case (.identifier(let a), .identifier(let b)):
            return a == b
        case (.operator(let a), .operator(let b)):
            return a == b
        case (.literal, .literal):
            return true
        default:
            return false
        }
    }
}

// MARK: - Token
struct Token {
    let type: TokenType
    let position: Int
}

// MARK: - Expression Parser
public final class ExpressionParser: Sendable {
    public init() {}

    public func parse(_ expression: String) throws -> ExpressionNode {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)

        // If the string contains {{ it's either a single expression or an interpolated string.
        if trimmed.contains("{{") {
            return try parseTemplateExpression(trimmed)
        }

        return try parseSingleExpression(trimmed)
    }

    /// Handles strings that contain {{ }} markers — either a pure single expression
    /// like `"{{count}}"` or an interpolated string like `"{{a}} / {{b}}"`.
    /// Interpolated strings are compiled into a `+` concatenation chain so all referenced
    /// variables participate in the dependency graph and update reactively.
    private func parseTemplateExpression(_ str: String) throws -> ExpressionNode {
        var parts: [ExpressionNode] = []
        var remaining = str[...]

        while !remaining.isEmpty {
            if let openRange = remaining.range(of: "{{") {
                // Literal text before the next {{
                let textBefore = String(remaining[..<openRange.lowerBound])
                if !textBefore.isEmpty {
                    parts.append(.literal(.string(textBefore)))
                }
                remaining = remaining[openRange.upperBound...]

                guard let closeRange = remaining.range(of: "}}") else {
                    throw ExpressionError.parseError("Unmatched {{ in expression: \(str)")
                }
                let inner = String(remaining[..<closeRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                remaining = remaining[closeRange.upperBound...]

                parts.append(try parseSingleExpression(inner))
            } else {
                // Trailing literal text
                parts.append(.literal(.string(String(remaining))))
                break
            }
        }

        guard !parts.isEmpty else { throw ExpressionError.emptyExpression }

        // Fold into a left-associative + chain
        return parts.dropFirst().reduce(parts[0]) { acc, next in
            .binaryOperation(operator: "+", left: acc, right: next)
        }
    }

    /// Parses a raw expression string (no {{ }} delimiters).
    private func parseSingleExpression(_ expression: String) throws -> ExpressionNode {
        let tokens = try tokenize(expression)

        if tokens.isEmpty || (tokens.count == 1 && tokens[0].type == .eof) {
            throw ExpressionError.emptyExpression
        }

        var parser = ParserState(tokens: tokens)
        let node = try parser.parseTernary()

        if !parser.isAtEnd() {
            throw ExpressionError.unexpectedToken(position: parser.current().position)
        }

        return node
    }

    // MARK: - Tokenizer
    private func tokenize(_ input: String) throws -> [Token] {
        var tokens: [Token] = []
        var index = input.startIndex

        while index < input.endIndex {
            let char = input[index]

            // Skip whitespace
            if char.isWhitespace {
                index = input.index(after: index)
                continue
            }

            let position = input.distance(from: input.startIndex, to: index)

            switch char {
            case "(":
                tokens.append(Token(type: .leftParen, position: position))
                index = input.index(after: index)

            case ")":
                tokens.append(Token(type: .rightParen, position: position))
                index = input.index(after: index)

            case "[":
                tokens.append(Token(type: .leftBracket, position: position))
                index = input.index(after: index)

            case "]":
                tokens.append(Token(type: .rightBracket, position: position))
                index = input.index(after: index)

            case ",":
                tokens.append(Token(type: .comma, position: position))
                index = input.index(after: index)

            case ".":
                tokens.append(Token(type: .dot, position: position))
                index = input.index(after: index)

            case "?":
                tokens.append(Token(type: .question, position: position))
                index = input.index(after: index)

            case ":":
                tokens.append(Token(type: .colon, position: position))
                index = input.index(after: index)

            case "'", "\"":
                let (string, newIndex) = try parseString(from: input, startingAt: index)
                tokens.append(Token(type: .literal(.string(string)), position: position))
                index = newIndex

            case "0"..."9":
                let (literal, newIndex) = parseNumber(from: input, startingAt: index)
                tokens.append(Token(type: .literal(literal), position: position))
                index = newIndex

            case "!":
                if index < input.index(before: input.endIndex) && input[input.index(after: index)] == "=" {
                    if input.distance(from: index, to: input.endIndex) > 2 && input[input.index(index, offsetBy: 2)] == "=" {
                        tokens.append(Token(type: .operator("!=="), position: position))
                        index = input.index(index, offsetBy: 3)
                    } else {
                        tokens.append(Token(type: .operator("!="), position: position))
                        index = input.index(index, offsetBy: 2)
                    }
                } else {
                    tokens.append(Token(type: .operator("!"), position: position))
                    index = input.index(after: index)
                }

            case "=":
                if index < input.index(before: input.endIndex) && input[input.index(after: index)] == "=" {
                    if input.distance(from: index, to: input.endIndex) > 2 && input[input.index(index, offsetBy: 2)] == "=" {
                        tokens.append(Token(type: .operator("==="), position: position))
                        index = input.index(index, offsetBy: 3)
                    } else {
                        tokens.append(Token(type: .operator("=="), position: position))
                        index = input.index(index, offsetBy: 2)
                    }
                } else {
                    throw ExpressionError.invalidCharacter(char, position: position)
                }

            case "<":
                if index < input.index(before: input.endIndex) && input[input.index(after: index)] == "=" {
                    tokens.append(Token(type: .operator("<="), position: position))
                    index = input.index(index, offsetBy: 2)
                } else {
                    tokens.append(Token(type: .operator("<"), position: position))
                    index = input.index(after: index)
                }

            case ">":
                if index < input.index(before: input.endIndex) && input[input.index(after: index)] == "=" {
                    tokens.append(Token(type: .operator(">="), position: position))
                    index = input.index(index, offsetBy: 2)
                } else {
                    tokens.append(Token(type: .operator(">"), position: position))
                    index = input.index(after: index)
                }

            case "&":
                if index < input.index(before: input.endIndex) && input[input.index(after: index)] == "&" {
                    tokens.append(Token(type: .operator("&&"), position: position))
                    index = input.index(index, offsetBy: 2)
                } else {
                    throw ExpressionError.invalidCharacter(char, position: position)
                }

            case "|":
                if index < input.index(before: input.endIndex) && input[input.index(after: index)] == "|" {
                    tokens.append(Token(type: .operator("||"), position: position))
                    index = input.index(index, offsetBy: 2)
                } else {
                    throw ExpressionError.invalidCharacter(char, position: position)
                }

            case "+", "-", "*", "/", "%":
                tokens.append(Token(type: .operator(String(char)), position: position))
                index = input.index(after: index)

            default:
                if char.isLetter || char == "_" || char == "$" {
                    let (identifier, newIndex) = parseIdentifier(from: input, startingAt: index)
                    if identifier == "true" {
                        tokens.append(Token(type: .literal(.bool(true)), position: position))
                    } else if identifier == "false" {
                        tokens.append(Token(type: .literal(.bool(false)), position: position))
                    } else if identifier == "null" {
                        tokens.append(Token(type: .literal(.null), position: position))
                    } else {
                        tokens.append(Token(type: .identifier(identifier), position: position))
                    }
                    index = newIndex
                } else {
                    throw ExpressionError.invalidCharacter(char, position: position)
                }
            }
        }

        tokens.append(Token(type: .eof, position: input.count))
        return tokens
    }

    private func parseString(from input: String, startingAt index: String.Index) throws -> (String, String.Index) {
        let quote = input[index]
        var currentIndex = input.index(after: index)
        var result = ""

        while currentIndex < input.endIndex {
            let char = input[currentIndex]

            if char == quote {
                return (result, input.index(after: currentIndex))
            } else if char == "\\" && currentIndex < input.index(before: input.endIndex) {
                currentIndex = input.index(after: currentIndex)
                let escapedChar = input[currentIndex]
                switch escapedChar {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "\\": result.append("\\")
                case quote: result.append(quote)
                default: result.append(escapedChar)
                }
                currentIndex = input.index(after: currentIndex)
            } else {
                result.append(char)
                currentIndex = input.index(after: currentIndex)
            }
        }

        throw ExpressionError.unterminatedString
    }

    private func parseNumber(from input: String, startingAt index: String.Index) -> (LiteralValue, String.Index) {
        var currentIndex = index
        var hasDecimal = false

        while currentIndex < input.endIndex {
            let char = input[currentIndex]

            if char.isNumber {
                currentIndex = input.index(after: currentIndex)
            } else if char == "." && !hasDecimal {
                hasDecimal = true
                currentIndex = input.index(after: currentIndex)
            } else {
                break
            }
        }

        let numberString = String(input[index..<currentIndex])

        if hasDecimal {
            return (.double(Double(numberString) ?? 0.0), currentIndex)
        } else {
            return (.int(Int(numberString) ?? 0), currentIndex)
        }
    }

    private func parseIdentifier(from input: String, startingAt index: String.Index) -> (String, String.Index) {
        var currentIndex = index

        while currentIndex < input.endIndex {
            let char = input[currentIndex]

            if char.isLetter || char.isNumber || char == "_" || char == "$" {
                currentIndex = input.index(after: currentIndex)
            } else {
                break
            }
        }

        return (String(input[index..<currentIndex]), currentIndex)
    }
}

// MARK: - Parser State (mutable parsing context)
private struct ParserState {
    let tokens: [Token]
    var currentIndex = 0
    /// Recursion depth — `parseTernary` is the single re-entry point.
    var depth = 0

    mutating func parseTernary() throws -> ExpressionNode {
        depth += 1
        defer { depth -= 1 }
        guard depth <= EngineLimits.maxExpressionDepth else {
            throw ExpressionError.parseError("expression nested too deeply")
        }

        var node = try parseOr()

        if match(.question) {
            let trueValue = try parseTernary()
            try consume(.colon, message: "Expected ':' after true value in ternary expression")
            let falseValue = try parseTernary()
            node = .ternary(condition: node, trueValue: trueValue, falseValue: falseValue)
        }

        return node
    }

    mutating func parseOr() throws -> ExpressionNode {
        var node = try parseAnd()

        while matchOperator("||") {
            let op = previous().type
            let right = try parseAnd()
            if case .operator(let opString) = op {
                node = .binaryOperation(operator: opString, left: node, right: right)
            }
        }

        return node
    }

    mutating func parseAnd() throws -> ExpressionNode {
        var node = try parseEquality()

        while matchOperator("&&") {
            let op = previous().type
            let right = try parseEquality()
            if case .operator(let opString) = op {
                node = .binaryOperation(operator: opString, left: node, right: right)
            }
        }

        return node
    }

    mutating func parseEquality() throws -> ExpressionNode {
        var node = try parseComparison()

        while matchOperator("===", "!==", "==", "!=") {
            let op = previous().type
            let right = try parseComparison()
            if case .operator(let opString) = op {
                node = .binaryOperation(operator: opString, left: node, right: right)
            }
        }

        return node
    }

    mutating func parseComparison() throws -> ExpressionNode {
        var node = try parseAddition()

        while matchOperator(">", ">=", "<", "<=") {
            let op = previous().type
            let right = try parseAddition()
            if case .operator(let opString) = op {
                node = .binaryOperation(operator: opString, left: node, right: right)
            }
        }

        return node
    }

    mutating func parseAddition() throws -> ExpressionNode {
        var node = try parseMultiplication()

        while matchOperator("+", "-") {
            let op = previous().type
            let right = try parseMultiplication()
            if case .operator(let opString) = op {
                node = .binaryOperation(operator: opString, left: node, right: right)
            }
        }

        return node
    }

    mutating func parseMultiplication() throws -> ExpressionNode {
        var node = try parseUnary()

        while matchOperator("*", "/", "%") {
            let op = previous().type
            let right = try parseUnary()
            if case .operator(let opString) = op {
                node = .binaryOperation(operator: opString, left: node, right: right)
            }
        }

        return node
    }

    mutating func parseUnary() throws -> ExpressionNode {
        if matchOperator("!", "-") {
            let op = previous().type
            let operand = try parseUnary()
            if case .operator(let opString) = op {
                return .unaryOperation(operator: opString, operand: operand)
            }
        }

        return try parsePostfix()
    }

    mutating func parsePostfix() throws -> ExpressionNode {
        var node = try parsePrimary()

        while true {
            if match(.dot) {
                if case .identifier(let member) = peek().type {
                    advance()
                    node = .memberAccess(object: node, member: member)
                } else {
                    throw ExpressionError.expectedIdentifier
                }
            } else if match(.leftBracket) {
                let index = try parseTernary()
                try consume(.rightBracket, message: "Expected ']' after array index")
                node = .arrayAccess(array: node, index: index)
            } else if match(.leftParen) {
                if case .memberAccess(let object, let functionName) = node {
                    var arguments: [ExpressionNode] = []

                    if !check(.rightParen) {
                        repeat {
                            arguments.append(try parseTernary())
                        } while match(.comma)
                    }

                    try consume(.rightParen, message: "Expected ')' after function arguments")
                    node = .functionCall(name: functionName, arguments: [object] + arguments)
                } else if case .variable(let functionName) = node {
                    var arguments: [ExpressionNode] = []

                    if !check(.rightParen) {
                        repeat {
                            arguments.append(try parseTernary())
                        } while match(.comma)
                    }

                    try consume(.rightParen, message: "Expected ')' after function arguments")
                    node = .functionCall(name: functionName, arguments: arguments)
                } else {
                    throw ExpressionError.invalidFunctionCall
                }
            } else {
                break
            }
        }

        return node
    }

    mutating func parsePrimary() throws -> ExpressionNode {
        if case .literal(let value) = peek().type {
            advance()
            return .literal(value)
        }

        if case .identifier(let name) = peek().type {
            advance()
            return .variable(name)
        }

        if match(.leftParen) {
            let expr = try parseTernary()
            try consume(.rightParen, message: "Expected ')' after expression")
            return expr
        }

        if match(.leftBracket) {
            var elements: [ExpressionNode] = []

            if !check(.rightBracket) {
                repeat {
                    elements.append(try parseTernary())
                } while match(.comma)
            }

            try consume(.rightBracket, message: "Expected ']' after array elements")

            // Convert to literal array if all elements are literals
            let literalValues: [LiteralValue] = elements.compactMap { node in
                if case .literal(let value) = node {
                    return value
                }
                return nil
            }

            if literalValues.count == elements.count {
                return .literal(.array(literalValues))
            }

            // Otherwise return as-is (will be evaluated at runtime)
            return .literal(.array(literalValues))
        }

        throw ExpressionError.unexpectedToken(position: current().position)
    }

    // MARK: - Helper Methods
    mutating func match(_ types: TokenType...) -> Bool {
        for type in types {
            if check(type) {
                advance()
                return true
            }
        }
        return false
    }

    mutating func matchOperator(_ operators: String...) -> Bool {
        for op in operators {
            if case .operator(let currentOp) = peek().type, currentOp == op {
                advance()
                return true
            }
        }
        return false
    }

    func check(_ type: TokenType) -> Bool {
        if isAtEnd() { return false }

        switch (peek().type, type) {
        case (.eof, .eof):
            return true
        case (.leftParen, .leftParen),
             (.rightParen, .rightParen),
             (.leftBracket, .leftBracket),
             (.rightBracket, .rightBracket),
             (.comma, .comma),
             (.dot, .dot),
             (.question, .question),
             (.colon, .colon):
            return true
        case (.operator(let a), .operator(let b)):
            return a == b
        case (.identifier, .identifier):
            return true
        case (.literal, .literal):
            return true
        default:
            return false
        }
    }

    mutating func consume(_ type: TokenType, message: String) throws {
        if check(type) {
            advance()
            return
        }

        throw ExpressionError.parseError(message)
    }

    mutating func advance() {
        if !isAtEnd() {
            currentIndex += 1
        }
    }

    func isAtEnd() -> Bool {
        return currentIndex >= tokens.count || peek().type == .eof
    }

    func peek() -> Token {
        return tokens[currentIndex]
    }

    func previous() -> Token {
        return tokens[currentIndex - 1]
    }

    func current() -> Token {
        return tokens[currentIndex]
    }
}
