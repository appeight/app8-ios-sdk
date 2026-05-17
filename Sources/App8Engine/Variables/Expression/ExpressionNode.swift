//
//  ExpressionNode.swift
//  App8Engine
//

import Foundation

/// AST node types for parsed expressions
public indirect enum ExpressionNode: Sendable {
    case literal(LiteralValue)
    case variable(String)
    case binaryOperation(operator: String, left: ExpressionNode, right: ExpressionNode)
    case unaryOperation(operator: String, operand: ExpressionNode)
    case functionCall(name: String, arguments: [ExpressionNode])
    case memberAccess(object: ExpressionNode, member: String)
    case arrayAccess(array: ExpressionNode, index: ExpressionNode)
    case ternary(condition: ExpressionNode, trueValue: ExpressionNode, falseValue: ExpressionNode)
}

/// Wrapper for literal values to make ExpressionNode Sendable
public enum LiteralValue: Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case null
    case array([LiteralValue])

    /// Convert to Any for evaluation
    public var anyValue: Any {
        switch self {
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .null: return NSNull()
        case .array(let values): return values.map { $0.anyValue }
        }
    }

    /// Create from Any value
    public static func from(_ value: Any) -> LiteralValue {
        switch value {
        case let b as Bool:
            return .bool(b)
        case let i as Int:
            return .int(i)
        case let d as Double:
            return .double(d)
        case let s as String:
            return .string(s)
        case is NSNull:
            return .null
        case let arr as [Any]:
            return .array(arr.map { from($0) })
        default:
            // Try to convert other number types
            if let n = value as? NSNumber {
                if CFNumberIsFloatType(n) {
                    return .double(n.doubleValue)
                } else {
                    return .int(n.intValue)
                }
            }
            return .string(String(describing: value))
        }
    }
}
