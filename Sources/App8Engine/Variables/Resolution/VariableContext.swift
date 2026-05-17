//
//  VariableContext.swift
//  App8Engine
//

import Foundation

/// Context for expression evaluation - provides variable values
@MainActor
public struct VariableContext {
    private let store: VariableStoreProtocol
    private let overlays: [String: Any?]

    public init(store: VariableStoreProtocol) {
        self.store = store
        self.overlays = [:]
    }

    private init(store: VariableStoreProtocol, overlays: [String: Any?]) {
        self.store = store
        self.overlays = overlays
    }

    /// Returns a new context with `name` bound to `value`, shadowing any store variable.
    /// Used by higher-order functions (filter, map, find, first) to bind the loop variable `item`.
    public func overlaying(_ name: String, value: Any?) -> VariableContext {
        var next = overlays
        next[name] = value
        return VariableContext(store: store, overlays: next)
    }

    /// Get value for a variable name
    /// Supports `$parent` to access parent scope values
    public func getValue(for name: String) -> Any? {
        // Overlay takes precedence over store (used for loop variables like `item`)
        if overlays.keys.contains(name) {
            return overlays[name]!  // safe: key confirmed present; inner Any? may be nil
        }

        // Handle $parent access - returns parent scope as a dictionary
        if name == "$parent" {
            if let parentStore = store.getParentStore() {
                return parentStore.getAllValues()
            }
            return nil
        }

        return store.getValue(name: name)
    }

    /// Check whether a variable is defined (even if its current value is nil)
    public func variableExists(_ name: String) -> Bool {
        if overlays.keys.contains(name) { return true }
        return store.hasVariable(name: name)
    }

    /// Get all variable values
    public func getAllValues() -> [String: Any?] {
        return store.getAllValues()
    }
}
