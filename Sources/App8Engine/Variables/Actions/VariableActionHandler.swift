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
            try handleIncrementVariable(action: action, store: store, context: context)

        case .toggleArrayValue:
            try handleToggleArrayValue(action: action, store: store, context: context)

        case .appendToArray:
            try handleAppendToArray(action: action, store: store, context: context)

        case .incrementArrayItem:
            try handleIncrementArrayItem(action: action, store: store, context: context)

        case .insertArrayItem:
            try handleInsertArrayItem(action: action, store: store, context: context)

        case .upsertArrayItem:
            try handleUpsertArrayItem(action: action, store: store, context: context)

        case .removeArrayItem:
            try handleRemoveArrayItem(action: action, store: store, context: context)

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
        guard let variableName = action.targetVariable else {
            throw VariableError.undefinedVariable("No variable name specified in updateVariable action")
        }

        guard let value = action.value else {
            throw VariableError.undefinedVariable("No value specified in updateVariable action for '\(variableName)'")
        }

        let resolvedValue = try resolveValue(value.value, context: context)
        if let rawKey = action.key {
            // Object variable: set only this key, keep the others.
            let resolvedKey = try resolveValue(rawKey, context: context)
            let key: String
            if let s = resolvedKey as? String {
                key = s
            } else if let n = resolvedKey as? NSNumber, n.doubleValue == n.doubleValue.rounded(), abs(n.doubleValue) < 1e15 {
                key = String(Int(n.doubleValue))
            } else {
                key = "\(resolvedKey)"
            }
            var map = (store.getValue(name: variableName) as? [String: Any]) ?? [:]
            map[key] = resolvedValue
            try store.setValue(name: variableName, value: map)
            return
        }
        try store.setValue(name: variableName, value: resolvedValue)
    }

    /// `by`: a number or an expression; absent means 1. An expression that is
    /// not a number throws.
    private func incrementAmount(_ action: DSL.Model.Action, context: VariableContext) throws -> Double {
        guard let raw = action.by?.value else { return 1 }
        let resolved = try resolveValue(raw, context: context)
        if let number = resolved as? Double { return number }
        if let number = resolved as? Int { return Double(number) }
        if let number = resolved as? NSNumber { return number.doubleValue }
        if let text = resolved as? String, let number = Double(text.trimmingCharacters(in: .whitespaces)) { return number }
        throw VariableError.typeMismatch(variable: action.targetVariable ?? "by", expected: .number, actual: "by = \(resolved)")
    }

    private func handleIncrementVariable(action: DSL.Model.Action, store: VariableStoreProtocol, context: VariableContext) throws {
        guard let variableName = action.targetVariable else {
            throw VariableError.undefinedVariable("No variable name specified in incrementVariable action")
        }

        let incrementBy = try incrementAmount(action, context: context)
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
            let (sum, overflow) = intValue.addingReportingOverflow(Int(saturating: incrementBy))
            if incrementBy.truncatingRemainder(dividingBy: 1) == 0, !overflow {
                newValue = sum
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

        guard let variableName = action.targetVariable else {
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
        guard let variableName = action.targetVariable else {
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
        guard let variableName = action.targetVariable else {
            throw VariableError.undefinedVariable("No variable name specified in incrementArrayItem action")
        }
        guard let matchKey = action.matchBy else {
            throw VariableError.undefinedVariable("No matchBy specified in incrementArrayItem action for '\(variableName)'")
        }
        guard let value = action.value else {
            throw VariableError.undefinedVariable("No value specified in incrementArrayItem action for '\(variableName)'")
        }
        let field = action.field ?? "quantity"
        let by = try incrementAmount(action, context: context)
        let resolved = try resolveValue(value.value, context: context)
        let object = resolved as? [String: Any]
        // A null / missing match key is a no-op (never matches, never inserts).
        let rawKey: Any?
        if let object { rawKey = object[matchKey] } else { rawKey = resolved }
        guard let key = rawKey, !(key is NSNull) else { return }

        var array = store.getValue(name: variableName) as? [Any] ?? []
        if let index = array.firstIndex(where: { ($0 as? [String: Any])?[matchKey].map { isEqual($0, key) } ?? false }),
           var item = array[index] as? [String: Any] {
            let current = (item[field] as? NSNumber)?.doubleValue ?? 0
            let next = current + by
            if next <= 0 {
                array.remove(at: index)
            } else {
                item[field] = next.wholeIntOrSelf
                array[index] = item
            }
        } else if var item = object, by > 0 {
            guard array.count < EngineLimits.maxArrayVariableCount else { return }
            item[field] = by.wholeIntOrSelf
            array.append(item)
        } else {
            return
        }
        try store.setValue(name: variableName, value: array)
    }

    /// Inserts `value` at `index` (default 0 = prepend). The index clamps to
    /// `[0, count]`; a negative index counts from the end (-1 = append).
    private func handleInsertArrayItem(action: DSL.Model.Action, store: VariableStoreProtocol, context: VariableContext) throws {
        guard let variableName = action.targetVariable else {
            throw VariableError.undefinedVariable("No variable name specified in insertArrayItem action")
        }
        guard let value = action.value else {
            throw VariableError.undefinedVariable("No value specified in insertArrayItem action for '\(variableName)'")
        }
        var array = try currentArray(variableName, store: store)
        guard array.count < EngineLimits.maxArrayVariableCount else {
            logger?.warning("insertArrayItem: '\(variableName)' already at the \(EngineLimits.maxArrayVariableCount)-element cap — insert dropped")
            return
        }
        let resolved = try resolveValue(value.value, context: context)
        var position = 0
        if let raw = action.index?.value, let n = numberValue(try resolveValue(raw, context: context)) {
            let i = Int(saturating: n)
            position = i < 0 ? array.count + 1 + i : i
        }
        position = max(0, min(position, array.count))
        array.insert(resolved, at: position)
        try store.setValue(name: variableName, value: array)
    }

    /// Replaces the first element whose `matchBy` key equals `value[matchBy]`
    /// with `value` exactly, else inserts `value` (`position`: `end` by default,
    /// or `start`). A `value` without the key is a no-op.
    private func handleUpsertArrayItem(action: DSL.Model.Action, store: VariableStoreProtocol, context: VariableContext) throws {
        guard let variableName = action.targetVariable else {
            throw VariableError.undefinedVariable("No variable name specified in upsertArrayItem action")
        }
        guard let matchKey = action.matchBy else {
            throw VariableError.undefinedVariable("No matchBy specified in upsertArrayItem action for '\(variableName)'")
        }
        guard let value = action.value else {
            throw VariableError.undefinedVariable("No value specified in upsertArrayItem action for '\(variableName)'")
        }
        guard let object = try resolveValue(value.value, context: context) as? [String: Any],
              let key = object[matchKey], !(key is NSNull) else { return }
        var array = try currentArray(variableName, store: store)
        if let index = array.firstIndex(where: { ($0 as? [String: Any])?[matchKey].map { isEqual($0, key) } ?? false }) {
            array[index] = object
        } else {
            guard array.count < EngineLimits.maxArrayVariableCount else { return }
            if action.position == "start" {
                array.insert(object, at: 0)
            } else {
                array.append(object)
            }
        }
        try store.setValue(name: variableName, value: array)
    }

    /// `{ matchBy, value }`: removes every element whose `matchBy` key equals
    /// `value` (or `value[matchBy]` when `value` is an object). `{ value }`
    /// alone removes every element equal to it. `{ index }` removes the
    /// element at that position (negative counts from the end).
    private func handleRemoveArrayItem(action: DSL.Model.Action, store: VariableStoreProtocol, context: VariableContext) throws {
        guard let variableName = action.targetVariable else {
            throw VariableError.undefinedVariable("No variable name specified in removeArrayItem action")
        }
        var array = try currentArray(variableName, store: store)
        if let value = action.value {
            let resolved = try resolveValue(value.value, context: context)
            if let matchKey = action.matchBy {
                let rawKey: Any?
                if let object = resolved as? [String: Any] { rawKey = object[matchKey] } else { rawKey = resolved }
                guard let key = rawKey, !(key is NSNull) else { return }
                array.removeAll { ($0 as? [String: Any])?[matchKey].map { isEqual($0, key) } ?? false }
            } else {
                array.removeAll { isEqual($0, resolved) }
            }
        } else if let raw = action.index?.value, let n = numberValue(try resolveValue(raw, context: context)) {
            var i = Int(saturating: n)
            if i < 0 { i += array.count }
            guard array.indices.contains(i) else { return }
            array.remove(at: i)
        } else {
            throw VariableError.undefinedVariable("removeArrayItem on '\(variableName)' needs 'value' or 'index'")
        }
        try store.setValue(name: variableName, value: array)
    }

    /// The array in `name`; nil / undefined value reads as empty.
    private func currentArray(_ name: String, store: VariableStoreProtocol) throws -> [Any] {
        let current = store.getValue(name: name)
        if let array = current as? [Any] { return array }
        if current == nil || current is NSNull { return [] }
        throw VariableError.typeMismatch(variable: name, expected: .array, actual: String(describing: type(of: current as Any)))
    }

    private func numberValue(_ value: Any) -> Double? {
        if let n = value as? NSNumber, !(value is Bool) { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
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

    /// Restores variables to their initial values (it never deletes them).
    ///
    /// Scopes are resolved structurally from the acting component's store chain
    /// `[own store, parent, …, root]` (root = the store without a parent, i.e.
    /// the app store):
    /// - `component`: the acting component's own store only.
    /// - `screen` (default): every store in the chain except the app root
    ///   (if the chain is a single store, that store).
    /// - `app`: the root store only.
    /// - `all`: the whole chain.
    /// Stores are reset root-first so computed variables see fresh parents.
    private func handleResetVariables(action: DSL.Model.Action, store: VariableStoreProtocol) {
        var chain: [VariableStoreProtocol] = []
        var cursor: VariableStoreProtocol? = store
        while let current = cursor, !chain.contains(where: { $0 === current }) {
            chain.append(current)
            cursor = current.getParentStore()
        }

        let targets: [VariableStoreProtocol]
        switch action.scope ?? .screen {
        case .component: targets = [store]
        case .app:       targets = [chain[chain.count - 1]]
        case .all:       targets = chain
        case .screen:    targets = chain.count > 1 ? Array(chain.dropLast()) : chain
        }
        for target in targets.reversed() {
            target.resetToInitialValues()
        }
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
