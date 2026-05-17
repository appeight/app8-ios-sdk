//
//  ScopedVariableStoreTests.swift
//  App8EngineTests
//

import XCTest
import Combine
@testable import App8Engine

@MainActor
final class ScopedVariableStoreTests: XCTestCase {
    var appStore: VariableStore!
    var screenStore: ScopedVariableStore!
    var componentStore: ScopedVariableStore!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        appStore = VariableStore()
        screenStore = ScopedVariableStore(parent: appStore)
        componentStore = ScopedVariableStore(parent: screenStore)
        cancellables = []
    }

    override func tearDown() {
        appStore = nil
        screenStore = nil
        componentStore = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Scope Chain Lookup Tests

    func testLocalVariableTakesPrecedence() throws {
        try appStore.defineVariable(name: "value", definition: VariableDefinition(type: .string, initialValue: "app"))
        try screenStore.defineVariable(name: "value", definition: VariableDefinition(type: .string, initialValue: "screen"))
        try componentStore.defineVariable(name: "value", definition: VariableDefinition(type: .string, initialValue: "component"))

        XCTAssertEqual(appStore.getValue(name: "value") as? String, "app")
        XCTAssertEqual(screenStore.getValue(name: "value") as? String, "screen")
        XCTAssertEqual(componentStore.getValue(name: "value") as? String, "component")
    }

    func testParentLookup() throws {
        try appStore.defineVariable(name: "appOnly", definition: VariableDefinition(type: .string, initialValue: "from-app"))

        XCTAssertEqual(screenStore.getValue(name: "appOnly") as? String, "from-app")
        XCTAssertEqual(componentStore.getValue(name: "appOnly") as? String, "from-app")
    }

    func testHasVariableInParentScope() throws {
        try appStore.defineVariable(name: "appVar", definition: VariableDefinition(type: .number, initialValue: 42))

        XCTAssertTrue(appStore.hasVariable(name: "appVar"))
        XCTAssertTrue(screenStore.hasVariable(name: "appVar"))
        XCTAssertTrue(componentStore.hasVariable(name: "appVar"))

        XCTAssertFalse(appStore.hasVariable(name: "nonexistent"))
        XCTAssertFalse(screenStore.hasVariable(name: "nonexistent"))
    }

    func testSetValueInParentScope() throws {
        try appStore.defineVariable(name: "shared", definition: VariableDefinition(type: .number, initialValue: 0))

        try componentStore.setValue(name: "shared", value: 100)

        XCTAssertEqual(appStore.getValue(name: "shared") as? Int, 100)
        XCTAssertEqual(screenStore.getValue(name: "shared") as? Int, 100)
        XCTAssertEqual(componentStore.getValue(name: "shared") as? Int, 100)
    }

    // MARK: - Computed Variables with Scope Chain

    func testComputedVariableAccessingParentScope() throws {
        try appStore.defineVariable(name: "multiplier", definition: VariableDefinition(type: .number, initialValue: 2))
        try screenStore.defineVariable(name: "base", definition: VariableDefinition(type: .number, initialValue: 5))

        try componentStore.defineVariable(
            name: "result",
            definition: VariableDefinition(type: .number, computed: "{{base * multiplier}}")
        )

        XCTAssertEqual(componentStore.getValue(name: "result") as? Int, 10)

        // Update app-level multiplier — computed should reactively update
        try appStore.setValue(name: "multiplier", value: 3)
        XCTAssertEqual(componentStore.getValue(name: "result") as? Int, 15)

        // Update screen-level base — computed should reactively update
        try screenStore.setValue(name: "base", value: 10)
        XCTAssertEqual(componentStore.getValue(name: "result") as? Int, 30)
    }

    // MARK: - Cross-Scope Computed Reactivity (TwoCountersTemplate scenario)

    func testComputedVariableUpdatesWhenParentVariableChanges() throws {
        try screenStore.defineVariable(name: "counter1", definition: VariableDefinition(type: .number, initialValue: 0))
        try componentStore.defineVariable(name: "count", definition: VariableDefinition(type: .number, computed: "{{counter1}}"))

        XCTAssertEqual(componentStore.getValue(name: "count") as? Int, 0)

        try screenStore.setValue(name: "counter1", value: 5)

        XCTAssertEqual(componentStore.getValue(name: "count") as? Int, 5)
    }

    func testTwoIndependentComponentStoresDontInterfere() throws {
        // TwoCountersTemplate: screen has counter1 + counter2, two cards each track one
        try screenStore.defineVariable(name: "counter1", definition: VariableDefinition(type: .number, initialValue: 0))
        try screenStore.defineVariable(name: "counter2", definition: VariableDefinition(type: .number, initialValue: 0))

        let cardA = ScopedVariableStore(parent: screenStore)
        let cardB = ScopedVariableStore(parent: screenStore)

        try cardA.defineVariable(name: "count", definition: VariableDefinition(type: .number, computed: "{{counter1}}"))
        try cardB.defineVariable(name: "count", definition: VariableDefinition(type: .number, computed: "{{counter2}}"))

        // Increment counter1 — only card A should update
        try screenStore.setValue(name: "counter1", value: 3)
        XCTAssertEqual(cardA.getValue(name: "count") as? Int, 3)
        XCTAssertEqual(cardB.getValue(name: "count") as? Int, 0)

        // Increment counter2 — only card B should update
        try screenStore.setValue(name: "counter2", value: 7)
        XCTAssertEqual(cardA.getValue(name: "count") as? Int, 3)
        XCTAssertEqual(cardB.getValue(name: "count") as? Int, 7)
    }

    func testComputedVariableReactiveAcrossThreeScopeLevels() throws {
        // App → Screen → Component: computed in component tracks app-level variable
        try appStore.defineVariable(name: "appCounter", definition: VariableDefinition(type: .number, initialValue: 10))
        try componentStore.defineVariable(name: "doubled", definition: VariableDefinition(type: .number, computed: "{{appCounter * 2}}"))

        XCTAssertEqual(componentStore.getValue(name: "doubled") as? Int, 20)

        try appStore.setValue(name: "appCounter", value: 5)

        XCTAssertEqual(componentStore.getValue(name: "doubled") as? Int, 10)
    }

    // MARK: - getAllValues Tests

    func testGetAllValuesMergesScopes() throws {
        try appStore.defineVariable(name: "appVar", definition: VariableDefinition(type: .string, initialValue: "app"))
        try screenStore.defineVariable(name: "screenVar", definition: VariableDefinition(type: .string, initialValue: "screen"))
        try componentStore.defineVariable(name: "componentVar", definition: VariableDefinition(type: .string, initialValue: "component"))

        let allValues = componentStore.getAllValues()

        XCTAssertEqual(allValues["appVar"] as? String, "app")
        XCTAssertEqual(allValues["screenVar"] as? String, "screen")
        XCTAssertEqual(allValues["componentVar"] as? String, "component")
    }

    func testGetLocalVariablesOnly() throws {
        try appStore.defineVariable(name: "appVar", definition: VariableDefinition(type: .string, initialValue: "app"))
        try screenStore.defineVariable(name: "screenVar", definition: VariableDefinition(type: .string, initialValue: "screen"))

        let localVars = screenStore.getLocalVariables()

        XCTAssertEqual(localVars.count, 1)
        XCTAssertNotNil(localVars["screenVar"])
        XCTAssertNil(localVars["appVar"])
    }

    // MARK: - Reset Tests

    func testResetLocalDoesNotAffectParent() throws {
        try appStore.defineVariable(name: "appVar", definition: VariableDefinition(type: .string, initialValue: "app"))
        try screenStore.defineVariable(name: "screenVar", definition: VariableDefinition(type: .string, initialValue: "screen"))

        screenStore.reset()

        XCTAssertFalse(screenStore.getLocalVariables().keys.contains("screenVar"))
        XCTAssertEqual(screenStore.getValue(name: "appVar") as? String, "app")
    }

    // MARK: - Error Cases

    func testSetValueOnUndefinedVariableInAnyScope() {
        XCTAssertThrowsError(try componentStore.setValue(name: "nonexistent", value: "value")) { error in
            XCTAssertTrue(error is VariableError)
        }
    }

    func testCircularDependencyWithinScope() {
        XCTAssertThrowsError(try {
            try screenStore.defineVariable(name: "a", definition: VariableDefinition(type: .number, computed: "{{b + 1}}"))
            try screenStore.defineVariable(name: "b", definition: VariableDefinition(type: .number, computed: "{{a + 1}}"))
        }()) { error in
            XCTAssertTrue(error is VariableError)
        }
    }

    // MARK: - defineVariables (batch with topological ordering)

    /// Reproducer: calling defineVariable for a computed var BEFORE its sibling dep is defined
    /// throws undefinedVariable — this is the raw failure that defineVariables was built to fix.
    func testComputedBeforeSiblingDep_reproducer() {
        // Define "displayedTasks" (computed, references "currentFilter") before "currentFilter" exists.
        // This matches what happens when Swift iterates the variables dictionary in an order
        // where the computed variable comes first.
        XCTAssertThrowsError(
            try screenStore.defineVariable(
                name: "displayedTasks",
                definition: VariableDefinition(
                    type: .array,
                    computed: "{{currentFilter == 'all' ? tasks : filter(tasks, item.done == false)}}"
                )
            )
        ) { error in
            guard case VariableError.computationError(_, let underlying) = error,
                  case VariableError.undefinedVariable(let name) = underlying else {
                XCTFail("Expected computationError wrapping undefinedVariable, got \(error)")
                return
            }
            XCTAssertEqual(name, "currentFilter")
        }
    }

    /// defineVariables defines in topological order regardless of dictionary iteration order —
    /// replicates the FilterDemoTasks screen scenario exactly.
    func testDefineVariables_filterDemoTasksScenario() throws {
        let tasks: [Any] = [
            ["id": 1, "title": "Fix bug",   "done": false],
            ["id": 2, "title": "Write docs","done": true ],
            ["id": 3, "title": "Deploy",    "done": false],
        ]
        // Definitions in the "bad" order: computed first, then its dependencies.
        // With a plain dictionary this order isn't guaranteed, but we're testing
        // that defineVariables handles any order correctly.
        let definitions: [String: VariableDefinition] = [
            "displayedTasks": VariableDefinition(
                type: .array,
                computed: "{{currentFilter == 'all' ? tasks : filter(tasks, item.done == false)}}"
            ),
            "currentFilter": VariableDefinition(type: .string, initialValue: "all"),
            "tasks":         VariableDefinition(type: .array,  initialValue: tasks),
        ]

        // Should not throw regardless of dictionary iteration order
        XCTAssertNoThrow(try screenStore.defineVariables(definitions))

        // Initial state: currentFilter="all" → displayedTasks = full tasks array
        let displayed = screenStore.getValue(name: "displayedTasks") as? [Any]
        XCTAssertEqual(displayed?.count, 3)

        // Switch to "active" filter → displayedTasks should recompute reactively
        try screenStore.setValue(name: "currentFilter", value: "active")
        let filtered = screenStore.getValue(name: "displayedTasks") as? [Any]
        XCTAssertEqual(filtered?.count, 2)
    }

    /// Computed variable depending on another computed variable in the same batch.
    func testDefineVariables_computedDependsOnComputed() throws {
        let definitions: [String: VariableDefinition] = [
            // "doubled" depends on "base"; "quadrupled" depends on "doubled"
            "quadrupled": VariableDefinition(type: .number, computed: "{{doubled * 2}}"),
            "doubled":    VariableDefinition(type: .number, computed: "{{base * 2}}"),
            "base":       VariableDefinition(type: .number, initialValue: 3),
        ]

        XCTAssertNoThrow(try screenStore.defineVariables(definitions))

        XCTAssertEqual(screenStore.getValue(name: "doubled")    as? Int, 6)
        XCTAssertEqual(screenStore.getValue(name: "quadrupled") as? Int, 12)

        // Reactivity: changing base should cascade through both computed vars
        try screenStore.setValue(name: "base", value: 5)
        XCTAssertEqual(screenStore.getValue(name: "doubled")    as? Int, 10)
        XCTAssertEqual(screenStore.getValue(name: "quadrupled") as? Int, 20)
    }

    /// defineVariables doesn't break when computed vars reference parent-scope variables
    /// (parent-scope deps are not in the batch, so they're ignored during sort and
    /// resolved correctly at evaluation time via the store's scope chain).
    func testDefineVariables_computedReferencingParentScope() throws {
        try appStore.defineVariable(name: "multiplier", definition: VariableDefinition(type: .number, initialValue: 4))

        let definitions: [String: VariableDefinition] = [
            "result": VariableDefinition(type: .number, computed: "{{base * multiplier}}"),
            "base":   VariableDefinition(type: .number, initialValue: 7),
        ]

        XCTAssertNoThrow(try screenStore.defineVariables(definitions))
        XCTAssertEqual(screenStore.getValue(name: "result") as? Int, 28)
    }
}
