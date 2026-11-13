//
//  VariablePersistence.swift
//  App8Engine
//
//  Keeps app-scope variables declared with `"persist": true` across launches.
//  Storage: UserDefaults suite `app8.<appId>`, key `var.<name>`, value = the
//  variable's JSON (wrapped in a one-element array so scalars are valid JSON).
//

#if canImport(UIKit)
import Combine
import Foundation
import UIKit

@MainActor
final class VariablePersistence {

    static let keyPrefix = "var."
    static let debounceInterval: TimeInterval = 0.5

    let appId: String
    let defaults: UserDefaults
    private weak var store: VariableStore?
    private weak var logger: A8Log?

    /// Names of persisted variables (app scope).
    private(set) var persistedNames: Set<String> = []
    /// Persisted variables changed since the last save.
    private var dirty: Set<String> = []
    private var saveWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    static func suiteName(appId: String) -> String { "app8.\(appId)" }

    init(appId: String, store: VariableStore, logger: A8Log?, defaults: UserDefaults? = nil) {
        self.appId = appId
        self.defaults = defaults ?? UserDefaults(suiteName: Self.suiteName(appId: appId)) ?? .standard
        self.store = store
        self.logger = logger

        store.anyVariableChanged
            .sink { [weak self] name in self?.variableChanged(name) }
            .store(in: &cancellables)
        store.onResetToInitialValues = { [weak self] names in self?.clear(names: names) }

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.flush() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.flush() }
            .store(in: &cancellables)
    }

    // MARK: - Load

    /// Registers `name` as persisted and restores its stored value into the
    /// store (the variable must already be defined, so `resetVariables` still
    /// returns to the declared `initialValue`). A stored value whose JSON type
    /// does not match the declared type is dropped.
    func adopt(name: String, definition: VariableDefinition) {
        guard let store else { return }
        persistedNames.insert(name)
        guard let stored = loadValue(name: name) else { return }
        guard definition.type.validate(stored), !(stored is NSNull) else {
            logger?.warning("variable.persist.typeMismatch: stored value for '\(name)' does not match type '\(definition.type.rawValue)' — dropped, using initialValue")
            defaults.removeObject(forKey: Self.keyPrefix + name)
            return
        }
        store.setExternalValue(name: name, value: stored)
        dirty.remove(name)
    }

    func loadValue(name: String) -> Any? {
        guard let data = defaults.data(forKey: Self.keyPrefix + name) else { return nil }
        guard let wrapped = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [Any],
              let value = wrapped.first else {
            logger?.warning("variable.persist.typeMismatch: stored value for '\(name)' is not valid JSON — dropped")
            defaults.removeObject(forKey: Self.keyPrefix + name)
            return nil
        }
        return value
    }

    // MARK: - Save

    private func variableChanged(_ name: String) {
        guard persistedNames.contains(name) else { return }
        dirty.insert(name)
        scheduleSave()
    }

    private func scheduleSave() {
        guard saveWorkItem == nil else { return }   // at most one save per interval
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: item)
    }

    /// Writes every dirty persisted variable now.
    func flush() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        guard let store, !dirty.isEmpty else { return }
        for name in dirty {
            let value = store.getValue(name: name) ?? NSNull()
            let sanitized = Self.jsonSafe(value)
            if let data = try? JSONSerialization.data(withJSONObject: [sanitized], options: []) {
                defaults.set(data, forKey: Self.keyPrefix + name)
            } else {
                logger?.warning("variable.persist: value of '\(name)' is not JSON-serializable — not saved")
            }
        }
        dirty.removeAll()
    }

    /// `resetVariables` on the app scope: drop the stored values.
    func clear(names: [String]) {
        for name in names where persistedNames.contains(name) {
            dirty.remove(name)
            defaults.removeObject(forKey: Self.keyPrefix + name)
        }
    }

    /// Converts a variable value into something `JSONSerialization` accepts.
    static func jsonSafe(_ value: Any) -> Any {
        switch value {
        case let d as [String: Any]: return d.mapValues { jsonSafe($0) }
        case let a as [Any]: return a.map { jsonSafe($0) }
        case let d as Double where !d.isFinite: return NSNull()
        case is String, is NSNumber, is Bool, is Int, is Double, is NSNull: return value
        case let v as AnyCodableValue: return jsonSafe(v.value)
        default: return String(describing: value)
        }
    }
}
#endif
