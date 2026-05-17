//
//  SchemaValidator.swift
//  App8Engine
//

import Foundation

/// JSON Schema validator (subset of Draft-07)
///
/// Supported keywords:
/// - `type`: string, number, integer, boolean, array, object, null
/// - `properties`: object property schemas
/// - `items`: array item schema
/// - `required`: required property names
/// - `enum`: allowed values
/// - `minLength`, `maxLength`: string length constraints
/// - `minimum`, `maximum`: number range constraints
/// - `minItems`, `maxItems`: array size constraints
public enum SchemaValidator {

    /// Validate data against a JSON Schema
    /// - Parameters:
    ///   - data: The data to validate (Any)
    ///   - schema: The JSON Schema (JSONValue)
    /// - Throws: SchemaValidationError if validation fails
    public static func validate(data: Any, against schema: JSONValue) throws {
        try validateValue(data, schema: schema, path: "$")
    }

    private static func validateValue(_ value: Any, schema: JSONValue, path: String, depth: Int = 0) throws {
        guard case .object(let schemaObj) = schema else {
            throw SchemaValidationError.invalidSchema("Schema must be an object at \(path)")
        }
        guard depth < EngineLimits.maxJSONDepth else {
            throw SchemaValidationError.invalidValue(
                path: path,
                reason: "Data nested too deeply to validate")
        }

        if let typeValue = schemaObj["type"] {
            try validateType(value, type: typeValue, path: path)
        }

        if let enumValue = schemaObj["enum"] {
            try validateEnum(value, enum: enumValue, path: path)
        }

        if let str = value as? String {
            if let minLength = schemaObj["minLength"], case .number(let min) = minLength {
                if str.count < Int(min) {
                    throw SchemaValidationError.invalidValue(
                        path: path,
                        reason: "String length \(str.count) is less than minimum \(Int(min))"
                    )
                }
            }
            if let maxLength = schemaObj["maxLength"], case .number(let max) = maxLength {
                if str.count > Int(max) {
                    throw SchemaValidationError.invalidValue(
                        path: path,
                        reason: "String length \(str.count) exceeds maximum \(Int(max))"
                    )
                }
            }
        }

        if let num = asNumber(value) {
            if let minimum = schemaObj["minimum"] {
                let min = numberValue(minimum) ?? 0
                if num < min {
                    throw SchemaValidationError.invalidValue(
                        path: path,
                        reason: "Value \(num) is less than minimum \(min)"
                    )
                }
            }
            if let maximum = schemaObj["maximum"] {
                let max = numberValue(maximum) ?? 0
                if num > max {
                    throw SchemaValidationError.invalidValue(
                        path: path,
                        reason: "Value \(num) exceeds maximum \(max)"
                    )
                }
            }
        }

        if let obj = value as? [String: Any] {
            if let required = schemaObj["required"], case .array(let requiredArr) = required {
                for reqItem in requiredArr {
                    if case .string(let propName) = reqItem {
                        if obj[propName] == nil {
                            throw SchemaValidationError.missingRequired(path: path, property: propName)
                        }
                    }
                }
            }

            if let properties = schemaObj["properties"], case .object(let propsSchema) = properties {
                for (propName, propSchema) in propsSchema {
                    if let propValue = obj[propName] {
                        try validateValue(propValue, schema: propSchema, path: "\(path).\(propName)", depth: depth + 1)
                    }
                }
            }
        }

        if let arr = value as? [Any] {
            if let minItems = schemaObj["minItems"], case .number(let min) = minItems {
                if arr.count < Int(min) {
                    throw SchemaValidationError.invalidValue(
                        path: path,
                        reason: "Array has \(arr.count) items, minimum is \(Int(min))"
                    )
                }
            }

            if let maxItems = schemaObj["maxItems"], case .number(let max) = maxItems {
                if arr.count > Int(max) {
                    throw SchemaValidationError.invalidValue(
                        path: path,
                        reason: "Array has \(arr.count) items, maximum is \(Int(max))"
                    )
                }
            }

            if let items = schemaObj["items"] {
                for (index, item) in arr.enumerated() {
                    try validateValue(item, schema: items, path: "\(path)[\(index)]", depth: depth + 1)
                }
            }
        }
    }

    private static func validateType(_ value: Any, type: JSONValue, path: String) throws {
        let expectedType: String
        if case .string(let t) = type {
            expectedType = t
        } else {
            return // Non-string type value, skip validation
        }

        let actualType = jsonType(of: value)

        // Integer satisfies the "number" type
        if expectedType == "number" && actualType == "integer" {
            return
        }

        if expectedType != actualType {
            throw SchemaValidationError.typeMismatch(
                path: path,
                expected: expectedType,
                actual: actualType
            )
        }
    }

    private static func validateEnum(_ value: Any, enum enumValue: JSONValue, path: String) throws {
        guard case .array(let allowedValues) = enumValue else { return }

        for allowed in allowedValues {
            if valuesEqual(value, allowed) {
                return
            }
        }

        throw SchemaValidationError.invalidValue(
            path: path,
            reason: "Value not in allowed enum values"
        )
    }

    private static func jsonType(of value: Any) -> String {
        switch value {
        case is String:
            return "string"
        case is Bool:
            return "boolean"
        case is Int:
            return "integer"
        case is Double, is Float:
            return "number"
        case is [Any]:
            return "array"
        case is [String: Any]:
            return "object"
        case is NSNull:
            return "null"
        default:
            if let _ = value as? NSNumber {
                return "number"
            }
            return "unknown"
        }
    }

    private static func asNumber(_ value: Any) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let f = value as? Float { return Double(f) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func numberValue(_ json: JSONValue) -> Double? {
        switch json {
        case .number(let n): return n
        default: return nil
        }
    }

    private static func valuesEqual(_ value: Any, _ jsonValue: JSONValue) -> Bool {
        switch jsonValue {
        case .string(let s):
            return (value as? String) == s
        case .number(let n):
            if let vi = value as? Int { return Double(vi) == n }
            if let vd = value as? Double { return vd == n }
            return false
        case .bool(let b):
            return (value as? Bool) == b
        case .null:
            return value is NSNull
        default:
            return false
        }
    }
}
