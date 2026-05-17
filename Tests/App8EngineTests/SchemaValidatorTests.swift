//
//  SchemaValidatorTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

final class SchemaValidatorTests: XCTestCase {

    private func schema(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: json.data(using: .utf8)!)
    }

    // MARK: - Type Validation Tests

    func testValidateStringType() throws {
        let schemaJSON = try schema("""
        {"type": "string"}
        """)

        XCTAssertNoThrow(try SchemaValidator.validate(data: "hello", against: schemaJSON))

        XCTAssertThrowsError(try SchemaValidator.validate(data: 123, against: schemaJSON)) { error in
            XCTAssertTrue(error is SchemaValidationError)
        }
    }

    func testValidateNumberType() throws {
        let schemaJSON = try schema("""
        {"type": "number"}
        """)

        // Both int and double should pass.
        XCTAssertNoThrow(try SchemaValidator.validate(data: 42, against: schemaJSON))
        XCTAssertNoThrow(try SchemaValidator.validate(data: 3.14, against: schemaJSON))

        XCTAssertThrowsError(try SchemaValidator.validate(data: "123", against: schemaJSON))
    }

    func testValidateBooleanType() throws {
        let schemaJSON = try schema("""
        {"type": "boolean"}
        """)

        XCTAssertNoThrow(try SchemaValidator.validate(data: true, against: schemaJSON))
        XCTAssertNoThrow(try SchemaValidator.validate(data: false, against: schemaJSON))

        XCTAssertThrowsError(try SchemaValidator.validate(data: "true", against: schemaJSON))
        XCTAssertThrowsError(try SchemaValidator.validate(data: 1, against: schemaJSON))
    }

    func testValidateArrayType() throws {
        let schemaJSON = try schema("""
        {"type": "array"}
        """)

        XCTAssertNoThrow(try SchemaValidator.validate(data: [1, 2, 3], against: schemaJSON))
        XCTAssertNoThrow(try SchemaValidator.validate(data: [] as [Any], against: schemaJSON))

        XCTAssertThrowsError(try SchemaValidator.validate(data: "not an array", against: schemaJSON))
    }

    func testValidateObjectType() throws {
        let schemaJSON = try schema("""
        {"type": "object"}
        """)

        XCTAssertNoThrow(try SchemaValidator.validate(data: ["key": "value"] as [String: Any], against: schemaJSON))
        XCTAssertNoThrow(try SchemaValidator.validate(data: [:] as [String: Any], against: schemaJSON))

        XCTAssertThrowsError(try SchemaValidator.validate(data: [1, 2, 3], against: schemaJSON))
    }

    // MARK: - String Constraints

    func testValidateStringMinLength() throws {
        let schemaJSON = try schema("""
        {"type": "string", "minLength": 3}
        """)

        XCTAssertNoThrow(try SchemaValidator.validate(data: "hello", against: schemaJSON))
        XCTAssertNoThrow(try SchemaValidator.validate(data: "abc", against: schemaJSON))

        XCTAssertThrowsError(try SchemaValidator.validate(data: "ab", against: schemaJSON))
    }

    func testValidateStringMaxLength() throws {
        let schemaJSON = try schema("""
        {"type": "string", "maxLength": 5}
        """)

        XCTAssertNoThrow(try SchemaValidator.validate(data: "hello", against: schemaJSON))
        XCTAssertNoThrow(try SchemaValidator.validate(data: "hi", against: schemaJSON))

        XCTAssertThrowsError(try SchemaValidator.validate(data: "hello world", against: schemaJSON))
    }

    // MARK: - Number Constraints

    func testValidateNumberMinimum() throws {
        let schemaJSON = try schema("""
        {"type": "number", "minimum": 0}
        """)

        XCTAssertNoThrow(try SchemaValidator.validate(data: 0, against: schemaJSON))
        XCTAssertNoThrow(try SchemaValidator.validate(data: 100, against: schemaJSON))

        XCTAssertThrowsError(try SchemaValidator.validate(data: -1, against: schemaJSON))
    }

    func testValidateNumberMaximum() throws {
        let schemaJSON = try schema("""
        {"type": "number", "maximum": 100}
        """)

        XCTAssertNoThrow(try SchemaValidator.validate(data: 100, against: schemaJSON))
        XCTAssertNoThrow(try SchemaValidator.validate(data: 50, against: schemaJSON))

        XCTAssertThrowsError(try SchemaValidator.validate(data: 101, against: schemaJSON))
    }

    // MARK: - Array Constraints

    func testValidateArrayMinItems() throws {
        let schemaJSON = try schema("""
        {"type": "array", "minItems": 2}
        """)

        XCTAssertNoThrow(try SchemaValidator.validate(data: [1, 2] as [Any], against: schemaJSON))
        XCTAssertNoThrow(try SchemaValidator.validate(data: [1, 2, 3] as [Any], against: schemaJSON))

        XCTAssertThrowsError(try SchemaValidator.validate(data: [1] as [Any], against: schemaJSON))
        XCTAssertThrowsError(try SchemaValidator.validate(data: [] as [Any], against: schemaJSON))
    }

    func testValidateArrayMaxItems() throws {
        let schemaJSON = try schema("""
        {"type": "array", "maxItems": 3}
        """)

        XCTAssertNoThrow(try SchemaValidator.validate(data: [1, 2, 3] as [Any], against: schemaJSON))
        XCTAssertNoThrow(try SchemaValidator.validate(data: [1] as [Any], against: schemaJSON))

        XCTAssertThrowsError(try SchemaValidator.validate(data: [1, 2, 3, 4] as [Any], against: schemaJSON))
    }

    func testValidateArrayItems() throws {
        let schemaJSON = try schema("""
        {
            "type": "array",
            "items": {"type": "string"}
        }
        """)

        XCTAssertNoThrow(try SchemaValidator.validate(data: ["a", "b", "c"] as [Any], against: schemaJSON))

        // Array containing a non-string.
        XCTAssertThrowsError(try SchemaValidator.validate(data: ["a", 1, "c"] as [Any], against: schemaJSON))
    }

    // MARK: - Object Constraints

    func testValidateObjectProperties() throws {
        let schemaJSON = try schema("""
        {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "age": {"type": "number"}
            }
        }
        """)

        let validData: [String: Any] = ["name": "Alice", "age": 30]
        XCTAssertNoThrow(try SchemaValidator.validate(data: validData, against: schemaJSON))

        // Wrong type for age.
        let invalidData: [String: Any] = ["name": "Alice", "age": "thirty"]
        XCTAssertThrowsError(try SchemaValidator.validate(data: invalidData, against: schemaJSON))
    }

    func testValidateObjectRequired() throws {
        let schemaJSON = try schema("""
        {
            "type": "object",
            "properties": {
                "id": {"type": "string"},
                "name": {"type": "string"}
            },
            "required": ["id"]
        }
        """)

        let validData: [String: Any] = ["id": "123", "name": "Alice"]
        XCTAssertNoThrow(try SchemaValidator.validate(data: validData, against: schemaJSON))

        // Missing optional property is fine.
        let validDataOptional: [String: Any] = ["id": "123"]
        XCTAssertNoThrow(try SchemaValidator.validate(data: validDataOptional, against: schemaJSON))

        // Missing required property.
        let invalidData: [String: Any] = ["name": "Alice"]
        XCTAssertThrowsError(try SchemaValidator.validate(data: invalidData, against: schemaJSON)) { error in
            guard let schemaError = error as? SchemaValidationError else {
                XCTFail("Expected SchemaValidationError")
                return
            }
            if case .missingRequired(_, let property) = schemaError {
                XCTAssertEqual(property, "id")
            } else {
                XCTFail("Expected missingRequired error")
            }
        }
    }

    // MARK: - Enum Validation

    func testValidateEnum() throws {
        let schemaJSON = try schema("""
        {
            "type": "string",
            "enum": ["red", "green", "blue"]
        }
        """)

        XCTAssertNoThrow(try SchemaValidator.validate(data: "red", against: schemaJSON))
        XCTAssertNoThrow(try SchemaValidator.validate(data: "green", against: schemaJSON))
        XCTAssertNoThrow(try SchemaValidator.validate(data: "blue", against: schemaJSON))

        XCTAssertThrowsError(try SchemaValidator.validate(data: "yellow", against: schemaJSON))
    }

    func testValidateEnumNumbers() throws {
        let schemaJSON = try schema("""
        {
            "type": "number",
            "enum": [1, 2, 3]
        }
        """)

        XCTAssertNoThrow(try SchemaValidator.validate(data: 1, against: schemaJSON))
        XCTAssertNoThrow(try SchemaValidator.validate(data: 2, against: schemaJSON))

        XCTAssertThrowsError(try SchemaValidator.validate(data: 4, against: schemaJSON))
    }

    // MARK: - Nested Validation

    func testValidateNestedObjects() throws {
        let schemaJSON = try schema("""
        {
            "type": "object",
            "properties": {
                "user": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string"},
                        "email": {"type": "string"}
                    },
                    "required": ["name"]
                }
            }
        }
        """)

        let validData: [String: Any] = [
            "user": [
                "name": "Alice",
                "email": "alice@example.com"
            ] as [String: Any]
        ]
        XCTAssertNoThrow(try SchemaValidator.validate(data: validData, against: schemaJSON))

        // Nested required property missing.
        let invalidData: [String: Any] = [
            "user": ["email": "alice@example.com"] as [String: Any]
        ]
        XCTAssertThrowsError(try SchemaValidator.validate(data: invalidData, against: schemaJSON))
    }

    func testValidateNestedArrayOfObjects() throws {
        let schemaJSON = try schema("""
        {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "id": {"type": "string"},
                    "title": {"type": "string"}
                },
                "required": ["id"]
            }
        }
        """)

        let validData: [Any] = [
            ["id": "1", "title": "First"] as [String: Any],
            ["id": "2", "title": "Second"] as [String: Any]
        ]
        XCTAssertNoThrow(try SchemaValidator.validate(data: validData, against: schemaJSON))

        // Second item is missing the required id.
        let invalidData: [Any] = [
            ["id": "1", "title": "First"] as [String: Any],
            ["title": "Second"] as [String: Any]
        ]
        XCTAssertThrowsError(try SchemaValidator.validate(data: invalidData, against: schemaJSON)) { error in
            guard let schemaError = error as? SchemaValidationError else {
                XCTFail("Expected SchemaValidationError")
                return
            }
            if case .missingRequired(let path, let property) = schemaError {
                XCTAssertEqual(path, "$[1]")
                XCTAssertEqual(property, "id")
            } else {
                XCTFail("Expected missingRequired error at path $[1]")
            }
        }
    }

    // MARK: - Error Paths

    func testErrorPathsAreCorrect() throws {
        let schemaJSON = try schema("""
        {
            "type": "object",
            "properties": {
                "items": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string"}
                        }
                    }
                }
            }
        }
        """)

        // Nested type mismatch: second item's name is a number.
        let invalidData: [String: Any] = [
            "items": [
                ["name": "Valid"] as [String: Any],
                ["name": 123] as [String: Any]
            ] as [Any]
        ]

        XCTAssertThrowsError(try SchemaValidator.validate(data: invalidData, against: schemaJSON)) { error in
            guard let schemaError = error as? SchemaValidationError else {
                XCTFail("Expected SchemaValidationError")
                return
            }
            if case .typeMismatch(let path, _, _) = schemaError {
                XCTAssertEqual(path, "$.items[1].name")
            } else {
                XCTFail("Expected typeMismatch error with correct path")
            }
        }
    }

    // MARK: - Edge Cases

    func testValidateWithNoTypeSpecified() throws {
        // A schema with no `type` accepts any value.
        let schemaJSON = try schema("""
        {}
        """)

        XCTAssertNoThrow(try SchemaValidator.validate(data: "string", against: schemaJSON))
        XCTAssertNoThrow(try SchemaValidator.validate(data: 123, against: schemaJSON))
        XCTAssertNoThrow(try SchemaValidator.validate(data: [1, 2, 3] as [Any], against: schemaJSON))
    }

    func testValidateEmptyData() throws {
        let schemaJSON = try schema("""
        {"type": "array"}
        """)

        XCTAssertNoThrow(try SchemaValidator.validate(data: [] as [Any], against: schemaJSON))
    }
}
