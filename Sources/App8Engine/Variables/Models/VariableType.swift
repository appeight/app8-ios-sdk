//
//  VariableType.swift
//  App8Engine
//

import Foundation

/// Variable type definition for the DSL variable system
public enum VariableType: String, Codable, Sendable {
    case boolean
    case string
    case number
    case array
    case object

    /// Validates that a value matches this type
    public func validate(_ value: Any?) -> Bool {
        guard let value = value else { return true }

        switch self {
        case .boolean:
            return value is Bool
        case .string:
            return value is String
        case .number:
            return value is NSNumber || value is Int || value is Double || value is Float
        case .array:
            return value is Array<Any>
        case .object:
            return value is [String: Any]
        }
    }

    /// Returns the default value for this type
    public func defaultValue() -> Any {
        switch self {
        case .boolean:
            return false
        case .string:
            return ""
        case .number:
            return 0
        case .array:
            return [] as [Any]
        case .object:
            return [:] as [String: Any]
        }
    }

    /// Infer the type from a runtime value
    public static func inferType(from value: Any?) -> VariableType {
        guard let value = value else { return .string }

        if value is Bool {
            return .boolean
        } else if value is String {
            return .string
        } else if value is NSNumber || value is Int || value is Double || value is Float {
            return .number
        } else if value is Array<Any> {
            return .array
        } else if value is [String: Any] {
            return .object
        }

        return .string
    }
}
