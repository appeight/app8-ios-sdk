//
//  Variable.swift
//  App8Engine
//

import Foundation
import Combine

/// Runtime variable instance
@MainActor
public final class Variable {
    public let name: String
    public let type: VariableType
    public private(set) var value: Any?
    public let isComputed: Bool
    public let expression: String?
    public private(set) var dependencies: Set<String> = []

    /// Publisher for value changes
    private let valueSubject = PassthroughSubject<(oldValue: Any?, newValue: Any?), Never>()
    public var valueChanged: AnyPublisher<(oldValue: Any?, newValue: Any?), Never> {
        valueSubject.eraseToAnyPublisher()
    }

    public init(name: String, definition: VariableDefinition) {
        self.name = name
        self.type = definition.type
        self.isComputed = definition.computed != nil
        self.expression = definition.computed

        if isComputed {
            self.value = nil
        } else {
            self.value = definition.rawInitialValue ?? definition.type.defaultValue()
        }
    }

    /// Set value for non-computed variables
    public func setValue(_ newValue: Any?) throws {
        guard !isComputed else {
            throw VariableError.cannotModifyComputedVariable(name)
        }

        if let newValue = newValue {
            guard type.validate(newValue) else {
                throw VariableError.typeMismatch(
                    variable: name,
                    expected: type,
                    actual: String(describing: Swift.type(of: newValue))
                )
            }
        }

        let oldValue = self.value
        guard !Self.valuesEqual(oldValue, newValue) else { return }
        self.value = newValue
        valueSubject.send((oldValue: oldValue, newValue: newValue))
    }

    /// Set value for computed variables (internal use)
    func setComputedValue(_ newValue: Any?, dependencies: Set<String>) {
        guard isComputed else { return }
        let oldValue = self.value
        self.dependencies = dependencies
        guard !Self.valuesEqual(oldValue, newValue) else { return }
        self.value = newValue
        valueSubject.send((oldValue: oldValue, newValue: newValue))
    }

    /// Set value without validation (for internal batch updates)
    func setValueUnchecked(_ newValue: Any?) {
        let oldValue = self.value
        guard !Self.valuesEqual(oldValue, newValue) else { return }
        self.value = newValue
        valueSubject.send((oldValue: oldValue, newValue: newValue))
    }

    /// Compare two Any? values for equality using known types.
    /// Returns false for unknown types (safe default — always notify).
    private static func valuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case (let l as Bool, let r as Bool): return l == r
        case (let l as Int, let r as Int): return l == r
        case (let l as Double, let r as Double): return l == r
        case (let l as String, let r as String): return l == r
        default: return false
        }
    }
}
