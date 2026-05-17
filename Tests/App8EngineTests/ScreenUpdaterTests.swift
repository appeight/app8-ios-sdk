//
//  ScreenUpdaterTests.swift
//  App8EngineTests
//

import XCTest
import Combine
@testable import App8Engine

/// Tests for state snapshot and restoration logic used by ScreenUpdater.
///
/// These tests validate the variable store lifecycle during streaming updates:
/// snapshotting state, creating a new store with the new definition, and
/// restoring preserved values — without requiring actual rendering.
@MainActor
final class ScreenUpdaterTests: XCTestCase {
    var appStore: VariableStore!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        appStore = VariableStore()
        cancellables = []
    }

    override func tearDown() {
        appStore = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - State Snapshot

    func testStateSnapshotPreservesAllVariableValues() throws {
        let store = ScopedVariableStore(parent: appStore)
        try store.defineVariable(name: "count", definition: VariableDefinition(type: .number, initialValue: 5))
        try store.defineVariable(name: "name", definition: VariableDefinition(type: .string, initialValue: "Alice"))

        let snapshot = store.getAllValues()

        XCTAssertEqual(snapshot["count"] as? Int, 5)
        XCTAssertEqual(snapshot["name"] as? String, "Alice")
    }

    func testStateSnapshotIncludesParentScopeValues() throws {
        try appStore.defineVariable(name: "appVar", definition: VariableDefinition(type: .string, initialValue: "app"))
        let store = ScopedVariableStore(parent: appStore)
        try store.defineVariable(name: "screenVar", definition: VariableDefinition(type: .string, initialValue: "screen"))

        let snapshot = store.getAllValues()

        XCTAssertEqual(snapshot["appVar"] as? String, "app")
        XCTAssertEqual(snapshot["screenVar"] as? String, "screen")
    }

    // MARK: - State Restoration

    func testStateRestorationIntoNewStore() throws {
        let snapshot: [String: Any?] = ["count": 5, "isSelected": true]
        let newStore = ScopedVariableStore(parent: appStore)
        try newStore.defineVariable(name: "count", definition: VariableDefinition(type: .number))
        try newStore.defineVariable(name: "isSelected", definition: VariableDefinition(type: .boolean))

        // Simulate what ScreenUpdater does: restore preserved values
        for (name, value) in snapshot {
            guard newStore.hasVariable(name: name), let value else { continue }
            try newStore.setValue(name: name, value: value)
        }

        XCTAssertEqual(newStore.getValue(name: "count") as? Int, 5)
        XCTAssertEqual(newStore.getValue(name: "isSelected") as? Bool, true)
    }

    func testStateRestorationIgnoresRemovedVariables() throws {
        // Old snapshot has "legacyField" which doesn't exist in new definition — no crash
        let snapshot: [String: Any?] = ["count": 3, "legacyField": "removed"]
        let newStore = ScopedVariableStore(parent: appStore)
        try newStore.defineVariable(name: "count", definition: VariableDefinition(type: .number))

        var restorationError: Error?
        for (name, value) in snapshot {
            guard newStore.hasVariable(name: name), let value else { continue }
            do {
                try newStore.setValue(name: name, value: value)
            } catch {
                restorationError = error
            }
        }

        // "legacyField" is silently skipped (hasVariable returns false), no error
        XCTAssertNil(restorationError)
        XCTAssertEqual(newStore.getValue(name: "count") as? Int, 3)
    }

    func testStateRestorationPreservesNilValues() throws {
        // Variables with nil values should be skipped (not restored)
        let snapshot: [String: Any?] = ["count": nil, "name": "Bob"]
        let newStore = ScopedVariableStore(parent: appStore)
        try newStore.defineVariable(name: "count", definition: VariableDefinition(type: .number, initialValue: 10))
        try newStore.defineVariable(name: "name", definition: VariableDefinition(type: .string))

        for (name, value) in snapshot {
            guard newStore.hasVariable(name: name), let value else { continue }
            try newStore.setValue(name: name, value: value)
        }

        // count was nil in snapshot — initial value (10) should be preserved
        XCTAssertEqual(newStore.getValue(name: "count") as? Int, 10)
        XCTAssertEqual(newStore.getValue(name: "name") as? String, "Bob")
    }

    // MARK: - New Store Variable Initialization

    func testNewStoreDefinesVariablesFromNewDefinition() throws {
        let variables: [String: VariableDefinition] = [
            "score": VariableDefinition(type: .number, initialValue: 0),
            "label": VariableDefinition(type: .string, initialValue: "default")
        ]

        let newStore = ScopedVariableStore(parent: appStore)
        for (name, definition) in variables {
            try newStore.defineVariable(name: name, definition: definition)
        }

        XCTAssertTrue(newStore.hasVariable(name: "score"))
        XCTAssertTrue(newStore.hasVariable(name: "label"))
        XCTAssertEqual(newStore.getValue(name: "score") as? Int, 0)
        XCTAssertEqual(newStore.getValue(name: "label") as? String, "default")
    }

    func testNewStoreHasParentAppStore() throws {
        try appStore.defineVariable(name: "appLevel", definition: VariableDefinition(type: .string, initialValue: "app"))
        let newStore = ScopedVariableStore(parent: appStore)

        XCTAssertEqual(newStore.getValue(name: "appLevel") as? String, "app")
    }
}
