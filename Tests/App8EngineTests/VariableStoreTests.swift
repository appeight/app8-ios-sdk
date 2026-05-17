//
//  VariableStoreTests.swift
//  App8EngineTests
//

import XCTest
import Combine
@testable import App8Engine

@MainActor
final class VariableStoreTests: XCTestCase {
    var store: VariableStore!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        store = VariableStore()
        cancellables = []
    }

    override func tearDown() {
        store = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Basic Variable Tests
    func testDefineAndGetVariable() throws {
        let definition = VariableDefinition(type: .string, initialValue: "Hello")
        try store.defineVariable(name: "greeting", definition: definition)

        XCTAssertTrue(store.hasVariable(name: "greeting"))
        XCTAssertEqual(store.getValue(name: "greeting") as? String, "Hello")
    }

    func testSetVariableValue() throws {
        let definition = VariableDefinition(type: .number, initialValue: 10)
        try store.defineVariable(name: "count", definition: definition)

        try store.setValue(name: "count", value: 20)
        XCTAssertEqual(store.getValue(name: "count") as? Int, 20)
    }

    func testUndefinedVariable() {
        XCTAssertFalse(store.hasVariable(name: "undefined"))
        XCTAssertNil(store.getValue(name: "undefined"))

        XCTAssertThrowsError(try store.setValue(name: "undefined", value: "test")) { error in
            XCTAssertTrue(error is VariableError)
            if case .undefinedVariable(let name) = error as? VariableError {
                XCTAssertEqual(name, "undefined")
            }
        }
    }

    func testTypeValidation() throws {
        let definition = VariableDefinition(type: .number, initialValue: 0)
        try store.defineVariable(name: "count", definition: definition)

        try store.setValue(name: "count", value: 42)
        XCTAssertEqual(store.getValue(name: "count") as? Int, 42)

        XCTAssertThrowsError(try store.setValue(name: "count", value: "not a number")) { error in
            XCTAssertTrue(error is VariableError)
        }
    }

    // MARK: - Computed Variable Tests
    func testSimpleComputedVariable() throws {
        let baseDef = VariableDefinition(type: .number, initialValue: 10)
        try store.defineVariable(name: "base", definition: baseDef)

        let computedDef = VariableDefinition(
            type: .number,
            computed: "{{base * 2}}"
        )
        try store.defineVariable(name: "doubled", definition: computedDef)

        XCTAssertEqual(store.getValue(name: "doubled") as? Int, 20)
    }

    func testComputedVariableUpdatesOnDependencyChange() throws {
        let firstNameDef = VariableDefinition(type: .string, initialValue: "John")
        let lastNameDef = VariableDefinition(type: .string, initialValue: "Doe")
        try store.defineVariable(name: "firstName", definition: firstNameDef)
        try store.defineVariable(name: "lastName", definition: lastNameDef)

        let fullNameDef = VariableDefinition(
            type: .string,
            computed: "{{firstName + ' ' + lastName}}"
        )
        try store.defineVariable(name: "fullName", definition: fullNameDef)

        XCTAssertEqual(store.getValue(name: "fullName") as? String, "John Doe")

        try store.setValue(name: "firstName", value: "Jane")
        XCTAssertEqual(store.getValue(name: "fullName") as? String, "Jane Doe")
    }

    func testBooleanComputedVariable() throws {
        let ageDef = VariableDefinition(type: .number, initialValue: 16)
        try store.defineVariable(name: "age", definition: ageDef)

        let isAdultDef = VariableDefinition(
            type: .boolean,
            computed: "{{age >= 18}}"
        )
        try store.defineVariable(name: "isAdult", definition: isAdultDef)

        XCTAssertEqual(store.getValue(name: "isAdult") as? Bool, false)

        try store.setValue(name: "age", value: 20)
        XCTAssertEqual(store.getValue(name: "isAdult") as? Bool, true)
    }

    // MARK: - Circular Dependency Tests
    func testCircularDependencyDetection() {
        XCTAssertThrowsError(try {
            let aDef = VariableDefinition(type: .number, computed: "{{b + 1}}")
            let bDef = VariableDefinition(type: .number, computed: "{{a + 1}}")

            try store.defineVariable(name: "a", definition: aDef)
            try store.defineVariable(name: "b", definition: bDef)
        }()) { error in
            XCTAssertTrue(error is VariableError)
            if case .circularDependency(let path) = error as? VariableError {
                XCTAssertTrue(path.contains("a") || path.contains("b"))
            }
        }
    }

    func testSelfReferencingVariable() {
        XCTAssertThrowsError(try {
            let selfDef = VariableDefinition(type: .number, computed: "{{selfVar + 1}}")
            try store.defineVariable(name: "selfVar", definition: selfDef)
        }()) { error in
            XCTAssertTrue(error is VariableError)
        }
    }

    // MARK: - Observer Tests
    func testVariableObserver() throws {
        let definition = VariableDefinition(type: .string, initialValue: "initial")
        try store.defineVariable(name: "observed", definition: definition)

        let expectation = XCTestExpectation(description: "Variable changed")
        var receivedName: String?

        store.anyVariableChanged
            .sink { name in
                receivedName = name
                expectation.fulfill()
            }
            .store(in: &cancellables)

        try store.setValue(name: "observed", value: "changed")

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedName, "observed")
    }

    // MARK: - Store Operations Tests
    func testGetAllValues() throws {
        try store.defineVariable(name: "name", definition: VariableDefinition(type: .string, initialValue: "John"))
        try store.defineVariable(name: "age", definition: VariableDefinition(type: .number, initialValue: 25))
        try store.defineVariable(name: "isActive", definition: VariableDefinition(type: .boolean, initialValue: true))

        let allValues = store.getAllValues()

        XCTAssertEqual(allValues.count, 3)
        XCTAssertEqual(allValues["name"] as? String, "John")
        XCTAssertEqual(allValues["age"] as? Int, 25)
        XCTAssertEqual(allValues["isActive"] as? Bool, true)
    }

    func testReset() throws {
        try store.defineVariable(name: "test", definition: VariableDefinition(type: .string, initialValue: "value"))

        XCTAssertTrue(store.hasVariable(name: "test"))

        store.reset()

        XCTAssertFalse(store.hasVariable(name: "test"))
        XCTAssertEqual(store.getAllValues().count, 0)
    }

    // MARK: - Array and Object Variable Tests
    func testArrayVariable() throws {
        let arrayDef = VariableDefinition(type: .array, initialValue: ["apple", "banana"])
        try store.defineVariable(name: "fruits", definition: arrayDef)

        XCTAssertEqual(store.getValue(name: "fruits") as? [String], ["apple", "banana"])

        try store.setValue(name: "fruits", value: ["apple", "banana", "cherry"])
        XCTAssertEqual(store.getValue(name: "fruits") as? [String], ["apple", "banana", "cherry"])
    }

    func testObjectVariable() throws {
        let objectDef = VariableDefinition(type: .object, initialValue: ["name": "John", "age": 30])
        try store.defineVariable(name: "user", definition: objectDef)

        let userValue = store.getValue(name: "user") as? [String: Any]
        XCTAssertEqual(userValue?["name"] as? String, "John")
        XCTAssertEqual(userValue?["age"] as? Int, 30)
    }

    func testComputedVariableWithArrayAccess() throws {
        let itemsDef = VariableDefinition(type: .array, initialValue: ["first", "second", "third"])
        try store.defineVariable(name: "items", definition: itemsDef)

        let firstItemDef = VariableDefinition(type: .string, computed: "{{items[0]}}")
        try store.defineVariable(name: "firstItem", definition: firstItemDef)

        XCTAssertEqual(store.getValue(name: "firstItem") as? String, "first")

        try store.setValue(name: "items", value: ["new-first", "second", "third"])
        XCTAssertEqual(store.getValue(name: "firstItem") as? String, "new-first")
    }

    // MARK: - Error Handling Tests
    func testInvalidExpression() {
        XCTAssertThrowsError(try store.defineVariable(
            name: "invalid",
            definition: VariableDefinition(type: .string, computed: "{{(()}}")
        )) { error in
            XCTAssertTrue(error is VariableError || error is ExpressionError)
        }
    }

    func testComputedVariableCannotBeModified() throws {
        let computedDef = VariableDefinition(type: .string, computed: "{{\"constant\"}}")
        try store.defineVariable(name: "computed", definition: computedDef)

        XCTAssertThrowsError(try store.setValue(name: "computed", value: "new value")) { error in
            XCTAssertTrue(error is VariableError)
        }
    }
}
