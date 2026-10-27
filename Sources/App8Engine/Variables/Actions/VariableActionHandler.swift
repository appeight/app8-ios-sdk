//
//  VariableActionHandler.swift
//  App8Engine
//

import Foundation

/// Handles variable-related actions from the DSL
@MainActor
public final class VariableActionHandler {
    private let propertyResolver = PropertyResolver()

    /// Optional logger from owning context.
    weak var logger: A8Log?

    public init() {}

    /// Execute a variable action
    /// - Parameters:
    ///   - action: The action to execute
    ///   - store: The variable store to operate on
    ///   - context: Variable context for resolving expressions in values
    public func execute(action: DSL.Model.Action, store: VariableStoreProtocol, context: VariableContext) throws {
        switch action.type {
        case .updateVariable:
            try handleUpdateVariable(action: action, store: store, context: context)

        case .incrementVariable:
            try handleIncrementVariable(action: action, store: store)

        case .toggleArrayValue:
            try handleToggleArrayValue(action: action, store: store, context: context)

        case .appendToArray:
            try handleAppendToArray(action: action, store: store, context: context)

        case .incrementArrayItem:
            try handleIncrementArrayItem(action: action, store: store, context: context)

        case .updateMultipleVariables:
            try handleUpdateMultipleVariables(action: action, store: store, context: context)

        case .resetVariables:
            handleResetVariables(action: action, store: store)

        default:
            break
        }
    }

    // MARK: - Action Handlers

    private func handleUpdateVariable(action: DSL.Model.Action, store: VariableStoreProtocol, context: VariableContext) throws {
        guard let variableName = action.variableName else {
            throw VariableError.undefinedVariable("No variable name specified in updateVariable action")
        }

        guard let value = action.value else {
            throw VariableError.undefinedVariable("No value specified in updateVariable action for '\(variableName)'")
        }

        let resolvedValue = try resolveValue(value.value, context: context)
        try store.setValue(name: variableName, value: resolvedValue)
    }

    private func handleIncrementVariable(action: DSL.Model.Action, store: VariableStoreProtocol) throws {
        guard let variableName = action.variableName else {
            throw VariableError.undefinedVariable("No variable name specified in incrementVariable action")
        }

        let incrementBy = action.by ?? 1.0
        logger?.debug("handleIncrementVariable: '\(variableName)' by \(incrementBy)")

        // Get current value
        guard let currentValue = store.getValue(name: variableName) else {
            logger?.debug("Variable '\(variableName)' not found in store. hasVariable: \(store.hasVariable(name: variableName))")
            throw VariableError.undefinedVariable(variableName)
        }

        logger?.debug("Current value of '\(variableName)': \(currentValue)")

        let newValue: Any
        if let intValue = currentValue as? Int {
            // Promote to Double when incrementBy is fractional to avoid silent truncation
            // e.g. Int(0) + Int(0.1) = 0, but Double(0) + 0.1 = 0.1
            if incrementBy.truncatingRemainder(dividingBy: 1) == 0 {
                newValue = intValue + Int(incrementBy)
            } else {
                newValue = Double(intValue) + incrementBy
            }
        } else if let doubleValue = currentValue as? Double {
            newValue = doubleValue + incrementBy
        } else if let numberValue = currentValue as? NSNumber {
            newValue = numberValue.doubleValue + incrementBy
        } else {
            throw VariableError.typeMismatch(variable: variableName, expected: .number, actual: String(describing: type(of: currentValue)))
        }

        try store.setValue(name: variableName, value: newValue)
    }

    private func handleToggleArrayValue(action: DSL.Model.Action, store: VariableStoreProtocol, context: VariableContext) throws {
        logger?.debug("handleToggleArrayValue called")

        guard let variableName = action.variableName else {
            throw VariableError.undefinedVariable("No variable name specified in toggleArrayValue action")
        }

        guard let value = action.value else {
            throw VariableError.undefinedVariable("No value specified in toggleArrayValue action for '\(variableName)'")
        }

        logger?.debug("toggleArrayValue: variableName=\(variableName), value=\(value.value)")

        let currentValue = store.getValue(name: variableName)
        logger?.debug("toggleArrayValue: currentValue=\(String(describing: currentValue)), type=\(type(of: currentValue as Any))")

        guard let currentArray = currentValue as? [Any] else {
            logger?.debug("toggleArrayValue: failed to cast to [Any]")
            throw VariableError.typeMismatch(variable: variableName, expected: .array, actual: String(describing: type(of: currentValue as Any)))
        }

        let resolvedValue = try resolveValue(value.value, context: context)
        logger?.debug("toggleArrayValue: resolvedValue=\(resolvedValue)")

        // When matchBy is set, match objects by the specified key (e.g. remove object where obj.id == value)
        var newArray = currentArray
        let foundIndex: Int?
        if let matchKey = action.matchBy {
            foundIndex = currentArray.firstIndex(where: { element in
                guard let dict = element as? [String: Any] else { return false }
                guard let keyValue = dict[matchKey] else { return false }
                return isEqual(keyValue, resolvedValue)
            })
        } else {
            foundIndex = currentArray.firstIndex(where: { isEqual($0, resolvedValue) })
        }

        if let index = foundIndex {
            logger?.debug("toggleArrayValue: removing value at index \(index)")
            newArray.remove(at: index)
        } else if action.matchBy == nil {
            // Primitive arrays only — with matchBy we can't synthesize an object from a scalar
            logger?.debug("toggleArrayValue: adding value")
            newArray.append(resolvedValue)
        } else {
            logger?.debug("toggleArrayValue: matchBy set, key not found — no-op")
            return
        }

        logger?.debug("toggleArrayValue: newArray=\(newArray)")
        try store.setValue(name: variableName, value: newArray)
    }

    private func handleAppendToArray(action: DSL.Model.Action, store: VariableStoreProtocol, context: VariableContext) throws {
        guard let variableName = action.variableName else {
            throw VariableError.undefinedVariable("No variable name specified in appendToArray action")
        }
        guard let value = action.value else {
            throw VariableError.undefinedVariable("No value specified in appendToArray action for '\(variableName)'")
        }

        let resolvedValue = try resolveValue(value.value, context: context)

        // Treat nil / undefined as empty array
        let currentArray: [Any]
        if let existing = store.getValue(name: variableName) as? [Any] {
            currentArray = existing
        } else if store.getValue(name: variableName) == nil {
            currentArray = []
        } else {
            throw VariableError.typeMismatch(
                variable: variableName,
                expected: .array,
                actual: String(describing: type(of: store.getValue(name: variableName) as Any))
            )
        }

        guard currentArray.count < EngineLimits.maxArrayVariableCount else {
            logger?.warning("appendToArray: '\(variableName)' already at the \(EngineLimits.maxArrayVariableCount)-element cap — append dropped")
            return
        }

        var newArray = currentArray
        newArray.append(resolvedValue)
        logger?.debug("appendToArray: appended to '\(variableName)', new count=\(newArray.count)")
        try store.setValue(name: variableName, value: newArray)
    }

    /// Adds `by` (default 1) to `field` (default "quantity") of the object whose
    /// `matchBy` key equals the value's. `value` is either the full object (its
    /// `matchBy` key identifies it, and it's appended with `field = by` when
    /// missing and `by > 0`) or just the key. An item whose field drops to 0 or
    /// below is removed — so one action covers add, +, − and remove.
    private func handleIncrementArrayItem(action: DSL.Model.Action, store: VariableStoreProtocol, context: VariableContext) throws {
        guard let variableName = action.variableName else {
            throw VariableError.undefinedVariable("No variable name specified in incrementArrayItem action")
        }
        guard let matchKey = action.matchBy else {
            throw VariableError.undefinedVariable("No matchBy specified in incrementArrayItem action for '\(variableName)'")
        }
        guard let value = action.value else {
            throw VariableError.undefinedVariable("No value specified in incrementArrayItem action for '\(variableName)'")
        }
        let field = action.field ?? "quantity"
        let by = action.by ?? 1
        let resolved = try resolveValue(value.value, context: context)
        let object = resolved as? [String: Any]
        guard let key = object.map({ $0[matchKey] }) ?? resolved else { return }

        var array = store.getValue(name: variableName) as? [Any] ?? []
        if let index = array.firstIndex(where: { ($0 as? [String: Any])?[matchKey].map { isEqual($0, key) } ?? false }),
           var item = array[index] as? [String: Any] {
            let current = (item[field] as? NSNumber)?.doubleValue ?? 0
            let next = current + by
            if next <= 0 {
                array.remove(at: index)
            } else {
                item[field] = next.truncatingRemainder(dividingBy: 1) == 0 ? Int(next) as Any : next as Any
                array[index] = item
            }
        } else if var item = object, by > 0 {
            guard array.count < EngineLimits.maxArrayVariableCount else { return }
            item[field] = by.truncatingRemainder(dividingBy: 1) == 0 ? Int(by) as Any : by as Any
            array.append(item)
        } else {
            return
        }
        try store.setValue(name: variableName, value: array)
    }

    private func handleUpdateMultipleVariables(action: DSL.Model.Action, store: VariableStoreProtocol, context: VariableContext) throws {
        guard let updates = action.updates else {
            return
        }

        for (variableName, value) in updates {
            let resolvedValue = try resolveValue(value.value, context: context)
            try store.setValue(name: variableName, value: resolvedValue)
        }
    }

    private func handleResetVariables(action: DSL.Model.Action, store: VariableStoreProtocol) {
        store.reset()
    }

    // MARK: - Helpers

    /// Resolves `{{…}}` in a value — also inside object / array values, so an
    /// action can build an object from expressions (e.g. a cart line item).
    private func resolveValue(_ value: Any, context: VariableContext) throws -> Any {
        if let stringValue = value as? String,
           stringValue.contains("{{") && stringValue.contains("}}") {
            return try propertyResolver.resolve(stringValue, context: context)
        }
        if let dict = value as? [String: Any] {
            return try dict.mapValues { try resolveValue($0, context: context) }
        }
        if let array = value as? [Any] {
            return try array.map { try resolveValue($0, context: context) }
        }
        return value
    }

    private func isEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        if let lhsString = lhs as? String, let rhsString = rhs as? String {
            return lhsString == rhsString
        }
        if let lhsInt = lhs as? Int, let rhsInt = rhs as? Int {
            return lhsInt == rhsInt
        }
        if let lhsDouble = lhs as? Double, let rhsDouble = rhs as? Double {
            return lhsDouble == rhsDouble
        }
        if let lhsBool = lhs as? Bool, let rhsBool = rhs as? Bool {
            return lhsBool == rhsBool
        }
        return String(describing: lhs) == String(describing: rhs)
    }
}
