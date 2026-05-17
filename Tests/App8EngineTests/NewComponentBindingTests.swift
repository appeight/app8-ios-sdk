//
//  NewComponentBindingTests.swift
//  App8Engine
//

import XCTest
import Combine
@testable import App8Engine

@MainActor
final class NewComponentBindingTests: XCTestCase {

    var variableStore: VariableStore!
    var scopedStore: ScopedVariableStore!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        variableStore = VariableStore()
        scopedStore = ScopedVariableStore(parent: variableStore)
        cancellables = []
    }

    override func tearDown() {
        variableStore = nil
        scopedStore = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Toggle Binding

    func testToggleVariableInitialValue() throws {
        try scopedStore.defineVariable(
            name: "darkMode",
            definition: VariableDefinition(type: .boolean, initialValue: true)
        )

        let value = scopedStore.getValue(name: "darkMode") as? Bool
        XCTAssertEqual(value, true)
    }

    func testToggleVariableUpdate() throws {
        try scopedStore.defineVariable(
            name: "darkMode",
            definition: VariableDefinition(type: .boolean, initialValue: false)
        )

        try scopedStore.setValue(name: "darkMode", value: true)
        XCTAssertEqual(scopedStore.getValue(name: "darkMode") as? Bool, true)
    }

    func testToggleVariableChangeNotification() throws {
        try scopedStore.defineVariable(
            name: "darkMode",
            definition: VariableDefinition(type: .boolean, initialValue: false)
        )

        let expectation = XCTestExpectation(description: "Toggle variable changed")
        var receivedName: String?

        scopedStore.anyVariableChanged
            .filter { $0 == "darkMode" }
            .sink { name in
                receivedName = name
                expectation.fulfill()
            }
            .store(in: &cancellables)

        try scopedStore.setValue(name: "darkMode", value: true)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedName, "darkMode")
        XCTAssertEqual(scopedStore.getValue(name: "darkMode") as? Bool, true)
    }

    // MARK: - Slider Binding

    func testSliderVariableInitialValue() throws {
        try scopedStore.defineVariable(
            name: "volume",
            definition: VariableDefinition(type: .number, initialValue: 50)
        )

        let value = scopedStore.getValue(name: "volume") as? Int
        XCTAssertEqual(value, 50)
    }

    func testSliderVariableUpdate() throws {
        try scopedStore.defineVariable(
            name: "volume",
            definition: VariableDefinition(type: .number, initialValue: 50)
        )

        try scopedStore.setValue(name: "volume", value: 75.0)
        let value = scopedStore.getValue(name: "volume")

        // Could be Double after setValue
        if let doubleVal = value as? Double {
            XCTAssertEqual(doubleVal, 75.0, accuracy: 0.01)
        } else if let intVal = value as? Int {
            XCTAssertEqual(intVal, 75)
        } else {
            XCTFail("Expected number value, got \(type(of: value))")
        }
    }

    func testSliderVariableChangeNotification() throws {
        try scopedStore.defineVariable(
            name: "volume",
            definition: VariableDefinition(type: .number, initialValue: 50)
        )

        let expectation = XCTestExpectation(description: "Slider variable changed")

        scopedStore.anyVariableChanged
            .filter { $0 == "volume" }
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        try scopedStore.setValue(name: "volume", value: 80.0)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Picker Binding

    func testPickerVariableInitialValue() throws {
        try scopedStore.defineVariable(
            name: "selectedColor",
            definition: VariableDefinition(type: .string, initialValue: "blue")
        )

        XCTAssertEqual(scopedStore.getValue(name: "selectedColor") as? String, "blue")
    }

    func testPickerVariableUpdate() throws {
        try scopedStore.defineVariable(
            name: "selectedColor",
            definition: VariableDefinition(type: .string, initialValue: "blue")
        )

        try scopedStore.setValue(name: "selectedColor", value: "red")
        XCTAssertEqual(scopedStore.getValue(name: "selectedColor") as? String, "red")
    }

    func testPickerVariableChangeNotification() throws {
        try scopedStore.defineVariable(
            name: "selectedColor",
            definition: VariableDefinition(type: .string, initialValue: "blue")
        )

        let expectation = XCTestExpectation(description: "Picker variable changed")
        var receivedValue: String?

        scopedStore.anyVariableChanged
            .filter { $0 == "selectedColor" }
            .compactMap { [weak self] _ -> String? in
                self?.scopedStore.getValue(name: "selectedColor") as? String
            }
            .sink { value in
                receivedValue = value
                expectation.fulfill()
            }
            .store(in: &cancellables)

        try scopedStore.setValue(name: "selectedColor", value: "green")

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValue, "green")
    }

    // MARK: - PageControl Binding

    func testPageControlVariableUpdate() throws {
        try scopedStore.defineVariable(
            name: "currentPage",
            definition: VariableDefinition(type: .number, initialValue: 0)
        )

        try scopedStore.setValue(name: "currentPage", value: 3)
        XCTAssertEqual(scopedStore.getValue(name: "currentPage") as? Int, 3)
    }

    // MARK: - DatePicker Binding

    func testDatePickerVariableInitialValue() throws {
        try scopedStore.defineVariable(
            name: "eventDate",
            definition: VariableDefinition(type: .string, initialValue: "2026-04-04")
        )

        XCTAssertEqual(scopedStore.getValue(name: "eventDate") as? String, "2026-04-04")
    }

    func testDatePickerVariableUpdate() throws {
        try scopedStore.defineVariable(
            name: "eventDate",
            definition: VariableDefinition(type: .string, initialValue: "2026-04-04")
        )

        try scopedStore.setValue(name: "eventDate", value: "2026-12-25")
        XCTAssertEqual(scopedStore.getValue(name: "eventDate") as? String, "2026-12-25")
    }

    func testDatePickerVariableChangeNotification() throws {
        try scopedStore.defineVariable(
            name: "eventDate",
            definition: VariableDefinition(type: .string, initialValue: "2026-04-04")
        )

        let expectation = XCTestExpectation(description: "Date variable changed")

        scopedStore.anyVariableChanged
            .filter { $0 == "eventDate" }
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        try scopedStore.setValue(name: "eventDate", value: "2026-06-15")

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(scopedStore.getValue(name: "eventDate") as? String, "2026-06-15")
    }

    // MARK: - Cross-component: Scoped store inherits from parent

    func testScopedStoreInheritsParentVariables() throws {
        try variableStore.defineVariable(
            name: "appTheme",
            definition: VariableDefinition(type: .string, initialValue: "dark")
        )

        XCTAssertEqual(scopedStore.getValue(name: "appTheme") as? String, "dark")
    }
}
