//
//  TextInputValidationTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

final class TextInputValidationTests: XCTestCase {

    // MARK: - Input Mask Tests

    func testFormatWithMask_PhoneNumber() {
        let result = TextInputValidation.formatWithMask(
            text: "1234567890",
            mask: "(###) ###-####"
        )
        XCTAssertEqual(result, "(123) 456-7890")
    }

    func testFormatWithMask_PartialInput() {
        let result = TextInputValidation.formatWithMask(
            text: "123",
            mask: "(###) ###-####"
        )
        XCTAssertEqual(result, "(123")
    }

    func testFormatWithMask_EmptyInput() {
        let result = TextInputValidation.formatWithMask(
            text: "",
            mask: "(###) ###-####"
        )
        XCTAssertEqual(result, "")
    }

    func testFormatWithMask_ExcessDigits() {
        // Extra digits beyond mask should be ignored
        let result = TextInputValidation.formatWithMask(
            text: "12345678901234",
            mask: "(###) ###-####"
        )
        XCTAssertEqual(result, "(123) 456-7890")
    }

    func testFormatWithMask_WithNonDigits() {
        // Non-digits in input should be filtered out
        let result = TextInputValidation.formatWithMask(
            text: "1a2b3c4d5e6f7g8h9i0j",
            mask: "(###) ###-####"
        )
        XCTAssertEqual(result, "(123) 456-7890")
    }

    func testFormatWithMask_CreditCard() {
        let result = TextInputValidation.formatWithMask(
            text: "1234567890123456",
            mask: "#### #### #### ####"
        )
        XCTAssertEqual(result, "1234 5678 9012 3456")
    }

    func testFormatWithMask_Date() {
        let result = TextInputValidation.formatWithMask(
            text: "12252024",
            mask: "##/##/####"
        )
        XCTAssertEqual(result, "12/25/2024")
    }

    func testFormatWithMask_SSN() {
        let result = TextInputValidation.formatWithMask(
            text: "123456789",
            mask: "###-##-####"
        )
        XCTAssertEqual(result, "123-45-6789")
    }

    // MARK: - Extract Digits Tests

    func testExtractDigits_OnlyDigits() {
        let result = TextInputValidation.extractDigits("1234567890")
        XCTAssertEqual(result, "1234567890")
    }

    func testExtractDigits_MixedContent() {
        let result = TextInputValidation.extractDigits("(123) 456-7890")
        XCTAssertEqual(result, "1234567890")
    }

    func testExtractDigits_NoDigits() {
        let result = TextInputValidation.extractDigits("abc-def")
        XCTAssertEqual(result, "")
    }

    func testExtractDigits_Empty() {
        let result = TextInputValidation.extractDigits("")
        XCTAssertEqual(result, "")
    }

    // MARK: - Input Allowed Tests - Max Length

    func testIsInputAllowed_WithinMaxLength() {
        let result = TextInputValidation.isInputAllowed(
            "abc",
            in: NSRange(location: 0, length: 0),
            currentText: "hello",
            maxLength: 10,
            allowedPattern: nil
        )
        XCTAssertTrue(result)
    }

    func testIsInputAllowed_ExceedsMaxLength() {
        let result = TextInputValidation.isInputAllowed(
            "world!",
            in: NSRange(location: 5, length: 0),
            currentText: "hello",
            maxLength: 10,
            allowedPattern: nil
        )
        XCTAssertFalse(result)
    }

    func testIsInputAllowed_ExactlyMaxLength() {
        let result = TextInputValidation.isInputAllowed(
            "12345",
            in: NSRange(location: 5, length: 0),
            currentText: "hello",
            maxLength: 10,
            allowedPattern: nil
        )
        XCTAssertTrue(result)
    }

    func testIsInputAllowed_ReplacingText() {
        // Replacing 3 chars with 5 chars: 10 - 3 + 5 = 12 > 10
        let result = TextInputValidation.isInputAllowed(
            "12345",
            in: NSRange(location: 0, length: 3),
            currentText: "helloworld",
            maxLength: 10,
            allowedPattern: nil
        )
        XCTAssertFalse(result)
    }

    func testIsInputAllowed_DeletingText() {
        // Deleting (empty replacement) should always be allowed
        let result = TextInputValidation.isInputAllowed(
            "",
            in: NSRange(location: 0, length: 5),
            currentText: "hello",
            maxLength: 10,
            allowedPattern: nil
        )
        XCTAssertTrue(result)
    }

    // MARK: - Input Allowed Tests - Allowed Pattern

    func testIsInputAllowed_MatchesPattern() {
        // Only digits allowed
        let result = TextInputValidation.isInputAllowed(
            "123",
            in: NSRange(location: 0, length: 0),
            currentText: "",
            maxLength: nil,
            allowedPattern: "^[0-9]+$"
        )
        XCTAssertTrue(result)
    }

    func testIsInputAllowed_DoesNotMatchPattern() {
        // Only digits allowed, but letters entered
        let result = TextInputValidation.isInputAllowed(
            "abc",
            in: NSRange(location: 0, length: 0),
            currentText: "",
            maxLength: nil,
            allowedPattern: "^[0-9]+$"
        )
        XCTAssertFalse(result)
    }

    func testIsInputAllowed_LettersOnlyPattern() {
        let result = TextInputValidation.isInputAllowed(
            "Hello",
            in: NSRange(location: 0, length: 0),
            currentText: "",
            maxLength: nil,
            allowedPattern: "^[a-zA-Z]+$"
        )
        XCTAssertTrue(result)
    }

    func testIsInputAllowed_AlphanumericPattern() {
        let result = TextInputValidation.isInputAllowed(
            "abc123",
            in: NSRange(location: 0, length: 0),
            currentText: "",
            maxLength: nil,
            allowedPattern: "^[a-zA-Z0-9]+$"
        )
        XCTAssertTrue(result)
    }

    func testIsInputAllowed_EmptyInputBypassesPattern() {
        // Empty input (deletion) should be allowed regardless of pattern
        let result = TextInputValidation.isInputAllowed(
            "",
            in: NSRange(location: 0, length: 1),
            currentText: "a",
            maxLength: nil,
            allowedPattern: "^[0-9]+$"
        )
        XCTAssertTrue(result)
    }

    func testIsInputAllowed_InvalidRegexAllowsAll() {
        // Invalid regex pattern should allow all input
        let result = TextInputValidation.isInputAllowed(
            "anything",
            in: NSRange(location: 0, length: 0),
            currentText: "",
            maxLength: nil,
            allowedPattern: "[invalid regex("
        )
        XCTAssertTrue(result)
    }

    // MARK: - Combined Constraints Tests

    func testIsInputAllowed_BothConstraints_Pass() {
        let result = TextInputValidation.isInputAllowed(
            "123",
            in: NSRange(location: 0, length: 0),
            currentText: "",
            maxLength: 10,
            allowedPattern: "^[0-9]+$"
        )
        XCTAssertTrue(result)
    }

    func testIsInputAllowed_MaxLengthFails_PatternPasses() {
        let result = TextInputValidation.isInputAllowed(
            "12345678901",
            in: NSRange(location: 0, length: 0),
            currentText: "",
            maxLength: 10,
            allowedPattern: "^[0-9]+$"
        )
        XCTAssertFalse(result)
    }

    func testIsInputAllowed_MaxLengthPasses_PatternFails() {
        let result = TextInputValidation.isInputAllowed(
            "abc",
            in: NSRange(location: 0, length: 0),
            currentText: "",
            maxLength: 10,
            allowedPattern: "^[0-9]+$"
        )
        XCTAssertFalse(result)
    }

    func testIsInputAllowed_NoConstraints() {
        let result = TextInputValidation.isInputAllowed(
            "anything goes! 123 @#$",
            in: NSRange(location: 0, length: 0),
            currentText: "",
            maxLength: nil,
            allowedPattern: nil
        )
        XCTAssertTrue(result)
    }
}
