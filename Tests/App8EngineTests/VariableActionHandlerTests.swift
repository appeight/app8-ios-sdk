//
//  VariableActionHandlerTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

@MainActor
class VariableActionHandlerTests: XCTestCase {
    var variableStore: VariableStore!
    var actionHandler: VariableActionHandler!
    var context: VariableContext!

    override func setUp() async throws {
        try await super.setUp()
        variableStore = VariableStore()
        actionHandler = VariableActionHandler()

        try variableStore.defineVariable(name: "counter", definition: VariableDefinition(type: .number, initialValue: 0))
        try variableStore.defineVariable(name: "message", definition: VariableDefinition(type: .string, initialValue: "Hello"))
        try variableStore.defineVariable(name: "isActive", definition: VariableDefinition(type: .boolean, initialValue: false))
        try variableStore.defineVariable(name: "selectedItems", definition: VariableDefinition(type: .array, initialValue: ["apple"]))
        try variableStore.defineVariable(name: "doubleValue", definition: VariableDefinition(type: .number, initialValue: 1.5))

        context = createContext()
    }

    override func tearDown() async throws {
        variableStore = nil
        actionHandler = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - Update Variable Tests

    func testUpdateVariableWithLiteralValue() throws {
        let action = createUpdateVariableAction(variableName: "message", value: "Updated Message")

        try actionHandler.execute(action: action, store: variableStore, context: context)

        XCTAssertEqual(variableStore.getValue(name: "message") as? String, "Updated Message")
    }

    func testUpdateVariableWithExpressionValue() throws {
        let action = createUpdateVariableAction(variableName: "message", value: "{{message + ' World'}}")

        context = createContext()
        try actionHandler.execute(action: action, store: variableStore, context: context)

        XCTAssertEqual(variableStore.getValue(name: "message") as? String, "Hello World")
    }

    func testUpdateBooleanVariable() throws {
        let action = createUpdateVariableAction(variableName: "isActive", value: true)

        try actionHandler.execute(action: action, store: variableStore, context: context)

        XCTAssertEqual(variableStore.getValue(name: "isActive") as? Bool, true)
    }

    func testUpdateVariableWithConditionalExpression() throws {
        let action = createUpdateVariableAction(variableName: "message", value: "{{isActive ? 'Active' : 'Inactive'}}")

        context = createContext()
        try actionHandler.execute(action: action, store: variableStore, context: context)

        XCTAssertEqual(variableStore.getValue(name: "message") as? String, "Inactive")
    }

    // MARK: - Toggle Array Value Tests

    func testToggleArrayValueAdd() throws {
        let action = createToggleArrayValueAction(variableName: "selectedItems", value: "banana")

        try actionHandler.execute(action: action, store: variableStore, context: context)

        let result = variableStore.getValue(name: "selectedItems") as? [Any]
        let stringResult = result?.compactMap { $0 as? String }.sorted()
        XCTAssertEqual(stringResult, ["apple", "banana"])
    }

    func testToggleArrayValueRemove() throws {
        try variableStore.setValue(name: "selectedItems", value: ["apple", "banana"])

        let action = createToggleArrayValueAction(variableName: "selectedItems", value: "banana")

        try actionHandler.execute(action: action, store: variableStore, context: context)

        let result = variableStore.getValue(name: "selectedItems") as? [String]
        XCTAssertEqual(result, ["apple"])
    }

    func testToggleArrayValueExisting() throws {
        let action = createToggleArrayValueAction(variableName: "selectedItems", value: "apple")

        try actionHandler.execute(action: action, store: variableStore, context: context)

        let result = variableStore.getValue(name: "selectedItems") as? [Any]
        XCTAssertEqual(result?.count, 0)
    }

    // MARK: - Increment Variable Tests

    func testIncrementVariableByDefault() throws {
        let action = createIncrementVariableAction(variableName: "counter", by: nil)

        try actionHandler.execute(action: action, store: variableStore, context: context)

        XCTAssertEqual(variableStore.getValue(name: "counter") as? Int, 1)
    }

    func testIncrementVariableByCustomAmount() throws {
        let action = createIncrementVariableAction(variableName: "counter", by: 5.0)

        try actionHandler.execute(action: action, store: variableStore, context: context)

        XCTAssertEqual(variableStore.getValue(name: "counter") as? Int, 5)
    }

    func testIncrementVariableMultipleTimes() throws {
        let action = createIncrementVariableAction(variableName: "counter", by: 1.0)

        try actionHandler.execute(action: action, store: variableStore, context: context)
        try actionHandler.execute(action: action, store: variableStore, context: context)
        try actionHandler.execute(action: action, store: variableStore, context: context)

        XCTAssertEqual(variableStore.getValue(name: "counter") as? Int, 3)
    }

    func testIncrementDoubleVariable() throws {
        let action = createIncrementVariableAction(variableName: "doubleValue", by: 0.5)

        try actionHandler.execute(action: action, store: variableStore, context: context)

        XCTAssertEqual(variableStore.getValue(name: "doubleValue") as? Double, 2.0)
    }

    func testDecrementVariable() throws {
        try variableStore.setValue(name: "counter", value: 10)
        let action = createIncrementVariableAction(variableName: "counter", by: -3.0)

        try actionHandler.execute(action: action, store: variableStore, context: context)

        XCTAssertEqual(variableStore.getValue(name: "counter") as? Int, 7)
    }

    // MARK: - Update Multiple Variables Tests

    func testUpdateMultipleVariables() throws {
        let action = createUpdateMultipleVariablesAction(updates: [
            "message": "Batch Updated",
            "isActive": true
        ])

        try actionHandler.execute(action: action, store: variableStore, context: context)

        XCTAssertEqual(variableStore.getValue(name: "message") as? String, "Batch Updated")
        XCTAssertEqual(variableStore.getValue(name: "isActive") as? Bool, true)
    }

    func testUpdateMultipleVariablesWithExpressions() throws {
        let action = createUpdateMultipleVariablesAction(updates: [
            "message": "{{message + '!'}}"
        ])

        context = createContext()
        try actionHandler.execute(action: action, store: variableStore, context: context)

        XCTAssertEqual(variableStore.getValue(name: "message") as? String, "Hello!")
    }

    // MARK: - Reset Variables Tests

    func testResetVariables() throws {
        try variableStore.setValue(name: "counter", value: 100)
        try variableStore.setValue(name: "message", value: "Modified")

        XCTAssertEqual(variableStore.getValue(name: "counter") as? Int, 100)
        XCTAssertEqual(variableStore.getValue(name: "message") as? String, "Modified")

        let action = createResetVariablesAction()

        try actionHandler.execute(action: action, store: variableStore, context: context)

        // resetVariables currently clears all variables rather than restoring initial values.
        XCTAssertNil(variableStore.getValue(name: "counter"))
        XCTAssertNil(variableStore.getValue(name: "message"))
    }

    // MARK: - Error Cases

    func testUpdateVariableMissingVariableName() {
        let action = createAction(type: .updateVariable, variableName: nil, value: "test")

        XCTAssertThrowsError(try actionHandler.execute(action: action, store: variableStore, context: context)) { error in
            XCTAssertTrue(error is VariableError)
        }
    }

    func testUpdateVariableMissingValue() {
        let action = createAction(type: .updateVariable, variableName: "message", value: nil)

        XCTAssertThrowsError(try actionHandler.execute(action: action, store: variableStore, context: context)) { error in
            XCTAssertTrue(error is VariableError)
        }
    }

    func testToggleArrayValueMissingValue() {
        let action = createAction(type: .toggleArrayValue, variableName: "selectedItems", value: nil)

        XCTAssertThrowsError(try actionHandler.execute(action: action, store: variableStore, context: context)) { error in
            XCTAssertTrue(error is VariableError)
        }
    }

    func testToggleArrayValueOnNonArray() {
        let action = createToggleArrayValueAction(variableName: "message", value: "test")

        XCTAssertThrowsError(try actionHandler.execute(action: action, store: variableStore, context: context)) { error in
            XCTAssertTrue(error is VariableError)
        }
    }

    // MARK: - Toggle Array Value with matchBy (object arrays)

    func testToggleArrayValueMatchByKeyRemovesObject() throws {
        let items: [[String: Any]] = [
            ["id": "1", "title": "First"],
            ["id": "2", "title": "Second"],
            ["id": "3", "title": "Third"]
        ]
        try variableStore.defineVariable(name: "todos", definition: VariableDefinition(type: .array, initialValue: items))

        let json: [String: Any] = [
            "type": "toggleArrayValue",
            "variableName": "todos",
            "value": "2",
            "matchBy": "id"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let action = try JSONDecoder().decode(DSL.Model.Action.self, from: data)

        try actionHandler.execute(action: action, store: variableStore, context: createContext())

        let result = variableStore.getValue(name: "todos") as? [[String: Any]]
        XCTAssertEqual(result?.count, 2)
        XCTAssertEqual(result?[0]["id"] as? String, "1")
        XCTAssertEqual(result?[1]["id"] as? String, "3")
    }

    func testToggleArrayValueMatchByKeyIsNoOpWhenNotFound() throws {
        // With matchBy set, not-found is a no-op (we can't synthesize an object from a scalar).
        // This avoids mixing object + scalar types in the array.
        let items: [[String: Any]] = [["id": "1", "title": "First"]]
        try variableStore.defineVariable(name: "todos", definition: VariableDefinition(type: .array, initialValue: items))

        let json: [String: Any] = [
            "type": "toggleArrayValue",
            "variableName": "todos",
            "value": "99",  // No object has id=99
            "matchBy": "id"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let action = try JSONDecoder().decode(DSL.Model.Action.self, from: data)

        try actionHandler.execute(action: action, store: variableStore, context: createContext())

        let result = variableStore.getValue(name: "todos") as? [[String: Any]]
        XCTAssertEqual(result?.count, 1, "Array should be unchanged when matchBy target not found")
        XCTAssertEqual(result?[0]["id"] as? String, "1")
    }

    func testToggleArrayValueWithoutMatchByStillWorks() throws {
        let action = createToggleArrayValueAction(variableName: "selectedItems", value: "apple")
        try actionHandler.execute(action: action, store: variableStore, context: createContext())
        let result = variableStore.getValue(name: "selectedItems") as? [String]
        XCTAssertEqual(result?.count, 0)
    }

    // MARK: - appendToArray

    func testAppendToArrayAddsPrimitive() throws {
        try variableStore.defineVariable(name: "nums", definition: VariableDefinition(type: .array, initialValue: [1, 2, 3]))

        let json: [String: Any] = [
            "type": "appendToArray",
            "variableName": "nums",
            "value": 4
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let action = try JSONDecoder().decode(DSL.Model.Action.self, from: data)

        try actionHandler.execute(action: action, store: variableStore, context: createContext())

        let result = variableStore.getValue(name: "nums") as? [Int]
        XCTAssertEqual(result, [1, 2, 3, 4])
    }

    func testAppendToArrayAddsObject() throws {
        let items: [[String: Any]] = [["id": "1", "name": "First"]]
        try variableStore.defineVariable(name: "items", definition: VariableDefinition(type: .array, initialValue: items))

        let newObj: [String: Any] = ["id": "2", "name": "Second"]
        try variableStore.defineVariable(name: "template", definition: VariableDefinition(type: .object, initialValue: newObj))

        let json: [String: Any] = [
            "type": "appendToArray",
            "variableName": "items",
            "value": "{{template}}"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let action = try JSONDecoder().decode(DSL.Model.Action.self, from: data)

        try actionHandler.execute(action: action, store: variableStore, context: createContext())

        let result = variableStore.getValue(name: "items") as? [[String: Any]]
        XCTAssertEqual(result?.count, 2)
        XCTAssertEqual(result?[1]["id"] as? String, "2")
        XCTAssertEqual(result?[1]["name"] as? String, "Second")
    }

    func testAppendToArrayOnEmptyArray() throws {
        try variableStore.defineVariable(name: "list", definition: VariableDefinition(type: .array, initialValue: []))

        let json: [String: Any] = [
            "type": "appendToArray",
            "variableName": "list",
            "value": "first"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let action = try JSONDecoder().decode(DSL.Model.Action.self, from: data)

        try actionHandler.execute(action: action, store: variableStore, context: createContext())

        let result = variableStore.getValue(name: "list") as? [String]
        XCTAssertEqual(result, ["first"])
    }

    func testAppendToArrayThrowsOnNonArray() throws {
        let json: [String: Any] = [
            "type": "appendToArray",
            "variableName": "message",  // defined as string in setUp
            "value": "foo"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let action = try JSONDecoder().decode(DSL.Model.Action.self, from: data)

        XCTAssertThrowsError(try actionHandler.execute(action: action, store: variableStore, context: createContext())) { error in
            XCTAssertTrue(error is VariableError)
        }
    }

    func testAppendToArrayMissingValueThrows() throws {
        try variableStore.defineVariable(name: "nums2", definition: VariableDefinition(type: .array, initialValue: [] as [Int]))
        let json: [String: Any] = [
            "type": "appendToArray",
            "variableName": "nums2"
            // no value
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let action = try JSONDecoder().decode(DSL.Model.Action.self, from: data)
        XCTAssertThrowsError(try actionHandler.execute(action: action, store: variableStore, context: createContext())) { error in
            XCTAssertTrue(error is VariableError)
        }
    }

    func testIncrementNonNumericVariable() {
        let action = createIncrementVariableAction(variableName: "message", by: 1.0)

        XCTAssertThrowsError(try actionHandler.execute(action: action, store: variableStore, context: context)) { error in
            XCTAssertTrue(error is VariableError)
        }
    }

    func testIncrementUndefinedVariable() {
        let action = createIncrementVariableAction(variableName: "undefinedVar", by: 1.0)

        XCTAssertThrowsError(try actionHandler.execute(action: action, store: variableStore, context: context)) { error in
            XCTAssertTrue(error is VariableError)
        }
    }

    // MARK: - Helper Methods

    private func createContext() -> VariableContext {
        return VariableContext(store: variableStore)
    }

    private func createUpdateVariableAction(variableName: String, value: Any) -> DSL.Model.Action {
        return createAction(type: .updateVariable, variableName: variableName, value: value)
    }

    private func createToggleArrayValueAction(variableName: String, value: Any) -> DSL.Model.Action {
        return createAction(type: .toggleArrayValue, variableName: variableName, value: value)
    }

    private func createIncrementVariableAction(variableName: String, by: Double?) -> DSL.Model.Action {
        return createAction(type: .incrementVariable, variableName: variableName, value: nil, by: by)
    }

    private func createUpdateMultipleVariablesAction(updates: [String: Any]) -> DSL.Model.Action {
        return createAction(type: .updateMultipleVariables, updates: updates)
    }

    private func createResetVariablesAction() -> DSL.Model.Action {
        return createAction(type: .resetVariables)
    }

    private func createAction(
        type: DSL.Model.Action.`Type`,
        variableName: String? = nil,
        value: Any? = nil,
        by: Double? = nil,
        updates: [String: Any]? = nil
    ) -> DSL.Model.Action {
        // Create action from JSON since Action is Decodable but not directly constructable
        var json: [String: Any] = ["type": type.rawValue]

        if let variableName = variableName {
            json["variableName"] = variableName
        }
        if let value = value {
            json["value"] = value
        }
        if let by = by {
            json["by"] = by
        }
        if let updates = updates {
            json["updates"] = updates
        }

        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(DSL.Model.Action.self, from: data)
    }
}
