//
//  VariableError.swift
//  App8Engine
//

import Foundation

/// Errors that can occur during variable operations
public enum VariableError: LocalizedError, Sendable {
    case undefinedVariable(String)
    case typeMismatch(variable: String, expected: VariableType, actual: String)
    case cannotModifyComputedVariable(String)
    case circularDependency([String])
    case invalidExpression(String, underlying: Error)
    case computationError(String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .undefinedVariable(let name):
            return "Undefined variable: '\(name)'"
        case .typeMismatch(let variable, let expected, let actual):
            return "Type mismatch for variable '\(variable)': expected \(expected), got \(actual)"
        case .cannotModifyComputedVariable(let name):
            return "Cannot modify computed variable: '\(name)'"
        case .circularDependency(let path):
            return "Circular dependency detected: \(path.joined(separator: " -> "))"
        case .invalidExpression(let expr, let error):
            return "Invalid expression '\(expr)': \(error.localizedDescription)"
        case .computationError(let expr, let error):
            return "Computation error for '\(expr)': \(error.localizedDescription)"
        }
    }
}

/// Errors that can occur during datasource loading
public enum DatasourceError: LocalizedError, Sendable {
    case notFound(screenId: String, datasourceId: String)
    case invalidFormat(datasourceId: String, underlying: Error)
    case typeMismatch(datasourceId: String, expected: VariableType, actual: String)
    case notImplemented

    public var errorDescription: String? {
        switch self {
        case .notFound(let screenId, let datasourceId):
            return "Datasource '\(datasourceId)' not found for screen '\(screenId)'"
        case .invalidFormat(let datasourceId, let error):
            return "Invalid format for datasource '\(datasourceId)': \(error.localizedDescription)"
        case .typeMismatch(let datasourceId, let expected, let actual):
            return "Type mismatch for datasource '\(datasourceId)': expected \(expected), got \(actual)"
        case .notImplemented:
            return "Datasource loading not implemented in data source"
        }
    }
}

/// Errors during JSON Schema validation
public enum SchemaValidationError: LocalizedError, Sendable {
    case invalidSchema(String)
    case typeMismatch(path: String, expected: String, actual: String)
    case missingRequired(path: String, property: String)
    case invalidValue(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidSchema(let msg):
            return "Invalid schema: \(msg)"
        case .typeMismatch(let path, let expected, let actual):
            return "Type mismatch at '\(path)': expected \(expected), got \(actual)"
        case .missingRequired(let path, let property):
            return "Missing required property '\(property)' at '\(path)'"
        case .invalidValue(let path, let reason):
            return "Invalid value at '\(path)': \(reason)"
        }
    }
}

/// Errors during expression parsing
public enum ExpressionError: LocalizedError, Sendable {
    case emptyExpression
    case invalidCharacter(Character, position: Int)
    case unterminatedString
    case unexpectedToken(position: Int)
    case expectedIdentifier
    case invalidFunctionCall
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .emptyExpression:
            return "Empty expression"
        case .invalidCharacter(let char, let position):
            return "Invalid character '\(char)' at position \(position)"
        case .unterminatedString:
            return "Unterminated string literal"
        case .unexpectedToken(let position):
            return "Unexpected token at position \(position)"
        case .expectedIdentifier:
            return "Expected identifier after '.'"
        case .invalidFunctionCall:
            return "Invalid function call"
        case .parseError(let message):
            return message
        }
    }
}
