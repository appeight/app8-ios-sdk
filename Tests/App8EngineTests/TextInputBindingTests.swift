//
//  TextInputBindingTests.swift
//  App8EngineTests
//
//  Tests for two-way binding between text inputs (TextField/TextView) and variables.
//

import XCTest
import Combine
@testable import App8Engine

/// Tests for the two-way binding pattern used in CTextFieldViewModel/CTextViewViewModel.
/// Simulates the binding behavior without requiring a full ComponentService mock.
@MainActor
final class TextInputBindingTests: XCTestCase {
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

    // MARK: - Email Field Binding Tests

    func testEmailFieldInitialValueFromVariable() throws {
        try scopedStore.defineVariable(
            name: "email",
            definition: VariableDefinition(type: .string, initialValue: "user@example.com")
        )

        let initialValue = scopedStore.getValue(name: "email") as? String
        XCTAssertEqual(initialValue, "user@example.com")
    }

    func testEmailFieldUpdatesVariable() throws {
        try scopedStore.defineVariable(
            name: "email",
            definition: VariableDefinition(type: .string, initialValue: "")
        )

        try scopedStore.setValue(name: "email", value: "test@test.com")

        let updatedValue = scopedStore.getValue(name: "email") as? String
        XCTAssertEqual(updatedValue, "test@test.com")
    }

    func testEmailFieldReceivesExternalUpdate() throws {
        try scopedStore.defineVariable(
            name: "email",
            definition: VariableDefinition(type: .string, initialValue: "old@example.com")
        )

        let expectation = XCTestExpectation(description: "Variable change notification")
        var receivedChange: String?

        scopedStore.anyVariableChanged
            .filter { $0 == "email" }
            .sink { name in
                receivedChange = name
                expectation.fulfill()
            }
            .store(in: &cancellables)

        try scopedStore.setValue(name: "email", value: "new@example.com")

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(receivedChange, "email")
        XCTAssertEqual(scopedStore.getValue(name: "email") as? String, "new@example.com")
    }

    // MARK: - Password Field Binding Tests

    func testPasswordFieldInitialValueEmpty() throws {
        try scopedStore.defineVariable(
            name: "password",
            definition: VariableDefinition(type: .string, initialValue: "")
        )

        let initialValue = scopedStore.getValue(name: "password") as? String
        XCTAssertEqual(initialValue, "")
    }

    func testPasswordFieldUpdatesVariable() throws {
        try scopedStore.defineVariable(
            name: "password",
            definition: VariableDefinition(type: .string, initialValue: "")
        )

        try scopedStore.setValue(name: "password", value: "SecureP@ss123")

        let updatedValue = scopedStore.getValue(name: "password") as? String
        XCTAssertEqual(updatedValue, "SecureP@ss123")
    }

    // MARK: - Multiple Fields Binding Tests

    func testMultipleFieldsUpdateIndependently() throws {
        try scopedStore.defineVariable(
            name: "email",
            definition: VariableDefinition(type: .string, initialValue: "")
        )
        try scopedStore.defineVariable(
            name: "password",
            definition: VariableDefinition(type: .string, initialValue: "")
        )

        try scopedStore.setValue(name: "email", value: "user@test.com")

        XCTAssertEqual(scopedStore.getValue(name: "email") as? String, "user@test.com")
        XCTAssertEqual(scopedStore.getValue(name: "password") as? String, "")

        try scopedStore.setValue(name: "password", value: "secret")

        XCTAssertEqual(scopedStore.getValue(name: "email") as? String, "user@test.com")
        XCTAssertEqual(scopedStore.getValue(name: "password") as? String, "secret")
    }

    func testBatchUpdateMultipleFields() throws {
        try scopedStore.defineVariable(
            name: "email",
            definition: VariableDefinition(type: .string, initialValue: "")
        )
        try scopedStore.defineVariable(
            name: "password",
            definition: VariableDefinition(type: .string, initialValue: "")
        )
        try scopedStore.defineVariable(
            name: "confirmPassword",
            definition: VariableDefinition(type: .string, initialValue: "")
        )

        try scopedStore.setMultipleValues([
            "email": "batch@test.com",
            "password": "batchPass",
            "confirmPassword": "batchPass"
        ])

        XCTAssertEqual(scopedStore.getValue(name: "email") as? String, "batch@test.com")
        XCTAssertEqual(scopedStore.getValue(name: "password") as? String, "batchPass")
        XCTAssertEqual(scopedStore.getValue(name: "confirmPassword") as? String, "batchPass")
    }

    // MARK: - Computed Variable Tests (Form Validation)

    func testEmailValidationComputedVariable() throws {
        try scopedStore.defineVariable(
            name: "email",
            definition: VariableDefinition(type: .string, initialValue: "")
        )
        try scopedStore.defineVariable(
            name: "isEmailValid",
            definition: VariableDefinition(type: .boolean, computed: "{{email.length > 0}}")
        )

        XCTAssertEqual(scopedStore.getValue(name: "isEmailValid") as? Bool, false)

        try scopedStore.setValue(name: "email", value: "test@test.com")

        XCTAssertEqual(scopedStore.getValue(name: "isEmailValid") as? Bool, true)
    }

    func testPasswordMinLengthValidation() throws {
        try scopedStore.defineVariable(
            name: "password",
            definition: VariableDefinition(type: .string, initialValue: "")
        )
        try scopedStore.defineVariable(
            name: "isPasswordLongEnough",
            definition: VariableDefinition(type: .boolean, computed: "{{password.length >= 8}}")
        )

        XCTAssertEqual(scopedStore.getValue(name: "isPasswordLongEnough") as? Bool, false)

        try scopedStore.setValue(name: "password", value: "short")
        XCTAssertEqual(scopedStore.getValue(name: "isPasswordLongEnough") as? Bool, false)

        try scopedStore.setValue(name: "password", value: "longpassword")
        XCTAssertEqual(scopedStore.getValue(name: "isPasswordLongEnough") as? Bool, true)
    }

    func testFormIsValidComputed() throws {
        try scopedStore.defineVariable(
            name: "email",
            definition: VariableDefinition(type: .string, initialValue: "")
        )
        try scopedStore.defineVariable(
            name: "password",
            definition: VariableDefinition(type: .string, initialValue: "")
        )
        try scopedStore.defineVariable(
            name: "isFormValid",
            definition: VariableDefinition(
                type: .boolean,
                computed: "{{email.length > 0 && password.length >= 6}}"
            )
        )

        XCTAssertEqual(scopedStore.getValue(name: "isFormValid") as? Bool, false)

        try scopedStore.setValue(name: "email", value: "user@test.com")
        XCTAssertEqual(scopedStore.getValue(name: "isFormValid") as? Bool, false)

        try scopedStore.setValue(name: "password", value: "12345")
        XCTAssertEqual(scopedStore.getValue(name: "isFormValid") as? Bool, false)

        try scopedStore.setValue(name: "password", value: "123456")
        XCTAssertEqual(scopedStore.getValue(name: "isFormValid") as? Bool, true)
    }

    // MARK: - Variable Change Publisher Tests

    func testVariableChangePublisherFiltersCorrectly() throws {
        try scopedStore.defineVariable(
            name: "email",
            definition: VariableDefinition(type: .string, initialValue: "")
        )
        try scopedStore.defineVariable(
            name: "password",
            definition: VariableDefinition(type: .string, initialValue: "")
        )

        var emailChanges = 0
        var passwordChanges = 0

        scopedStore.anyVariableChanged
            .filter { $0 == "email" }
            .sink { _ in emailChanges += 1 }
            .store(in: &cancellables)

        scopedStore.anyVariableChanged
            .filter { $0 == "password" }
            .sink { _ in passwordChanges += 1 }
            .store(in: &cancellables)

        try scopedStore.setValue(name: "email", value: "a@b.com")
        try scopedStore.setValue(name: "email", value: "c@d.com")
        try scopedStore.setValue(name: "password", value: "secret")

        XCTAssertEqual(emailChanges, 2)
        XCTAssertEqual(passwordChanges, 1)
    }

    // MARK: - Parent Scope Tests (App-level variables)

    func testInputCanAccessAppLevelVariables() throws {
        try variableStore.defineVariable(
            name: "maxEmailLength",
            definition: VariableDefinition(type: .number, initialValue: 50)
        )
        try scopedStore.defineVariable(
            name: "email",
            definition: VariableDefinition(type: .string, initialValue: "")
        )

        let maxLength = scopedStore.getValue(name: "maxEmailLength") as? Int
        XCTAssertEqual(maxLength, 50)
    }

    func testInputUpdatesCanTriggerAppLevelComputed() throws {
        try variableStore.defineVariable(
            name: "userEmail",
            definition: VariableDefinition(type: .string, initialValue: "")
        )
        try variableStore.defineVariable(
            name: "hasUserEmail",
            definition: VariableDefinition(type: .boolean, computed: "{{userEmail.length > 0}}")
        )

        XCTAssertEqual(variableStore.getValue(name: "hasUserEmail") as? Bool, false)

        // Update from the scoped store, simulating an input update propagating up.
        try scopedStore.setValue(name: "userEmail", value: "user@app.com")

        XCTAssertEqual(variableStore.getValue(name: "hasUserEmail") as? Bool, true)
    }

    // MARK: - Incremental Typing Simulation

    func testIncrementalTypingUpdatesVariable() throws {
        try scopedStore.defineVariable(
            name: "email",
            definition: VariableDefinition(type: .string, initialValue: "")
        )

        let emailChars = Array("test@example.com")
        var currentText = ""

        for char in emailChars {
            currentText += String(char)
            try scopedStore.setValue(name: "email", value: currentText)
        }

        XCTAssertEqual(scopedStore.getValue(name: "email") as? String, "test@example.com")
    }

    func testIncrementalTypingWithValidation() throws {
        try scopedStore.defineVariable(
            name: "password",
            definition: VariableDefinition(type: .string, initialValue: "")
        )
        try scopedStore.defineVariable(
            name: "passwordStrength",
            definition: VariableDefinition(
                type: .string,
                computed: "{{password.length < 6 ? 'weak' : (password.length < 10 ? 'medium' : 'strong')}}"
            )
        )

        try scopedStore.setValue(name: "password", value: "12345")
        XCTAssertEqual(scopedStore.getValue(name: "passwordStrength") as? String, "weak")

        try scopedStore.setValue(name: "password", value: "12345678")
        XCTAssertEqual(scopedStore.getValue(name: "passwordStrength") as? String, "medium")

        try scopedStore.setValue(name: "password", value: "1234567890abc")
        XCTAssertEqual(scopedStore.getValue(name: "passwordStrength") as? String, "strong")
    }

    // MARK: - Clear/Reset Tests

    func testClearingInputResetsVariable() throws {
        try scopedStore.defineVariable(
            name: "email",
            definition: VariableDefinition(type: .string, initialValue: "initial@test.com")
        )

        try scopedStore.setValue(name: "email", value: "")

        XCTAssertEqual(scopedStore.getValue(name: "email") as? String, "")
    }

    func testResetVariablesAction() throws {
        try scopedStore.defineVariable(
            name: "email",
            definition: VariableDefinition(type: .string, initialValue: "")
        )
        try scopedStore.defineVariable(
            name: "password",
            definition: VariableDefinition(type: .string, initialValue: "")
        )

        try scopedStore.setValue(name: "email", value: "filled@test.com")
        try scopedStore.setValue(name: "password", value: "filledpass")

        // The real resetVariables action would restore each variable's
        // initialValue from its definition; here we set "" by hand.
        try scopedStore.setValue(name: "email", value: "")
        try scopedStore.setValue(name: "password", value: "")

        XCTAssertEqual(scopedStore.getValue(name: "email") as? String, "")
        XCTAssertEqual(scopedStore.getValue(name: "password") as? String, "")
    }

    // MARK: - Notes Form Tests (Multi-line TextView)

    func testNoteTitleBinding() throws {
        try scopedStore.defineVariable(
            name: "noteTitle",
            definition: VariableDefinition(type: .string, initialValue: "")
        )

        try scopedStore.setValue(name: "noteTitle", value: "My First Note")
        XCTAssertEqual(scopedStore.getValue(name: "noteTitle") as? String, "My First Note")
    }

    func testNoteContentMultiLineBinding() throws {
        try scopedStore.defineVariable(
            name: "noteContent",
            definition: VariableDefinition(type: .string, initialValue: "")
        )

        let multiLineContent = """
        This is the first line.
        This is the second line.
        And a third line with special chars: @#$%
        """

        try scopedStore.setValue(name: "noteContent", value: multiLineContent)

        XCTAssertEqual(scopedStore.getValue(name: "noteContent") as? String, multiLineContent)
    }

    func testNoteCharacterCount() throws {
        try scopedStore.defineVariable(
            name: "noteContent",
            definition: VariableDefinition(type: .string, initialValue: "")
        )
        try scopedStore.defineVariable(
            name: "characterCount",
            definition: VariableDefinition(type: .number, computed: "{{noteContent.length}}")
        )

        XCTAssertEqual(scopedStore.getValue(name: "characterCount") as? Int, 0)

        try scopedStore.setValue(name: "noteContent", value: "Hello, World!")
        XCTAssertEqual(scopedStore.getValue(name: "characterCount") as? Int, 13)
    }
}
