//
//  DatasourceDefinitionTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

final class DatasourceDefinitionTests: XCTestCase {

    // MARK: - Wrapped Format Tests

    func testDecodeWrappedFormatWithArray() throws {
        let json = """
        {
            "schema": {
                "type": "array",
                "items": {"type": "object"}
            },
            "data": [
                {"id": "1", "name": "First"},
                {"id": "2", "name": "Second"}
            ]
        }
        """.data(using: .utf8)!

        let definition = try JSONDecoder().decode(DatasourceDefinition.self, from: json)

        XCTAssertNotNil(definition.schema)
        let data = definition.rawData as? [[String: Any]]
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 2)
        XCTAssertEqual(data?[0]["id"] as? String, "1")
    }

    func testDecodeWrappedFormatWithObject() throws {
        let json = """
        {
            "schema": {"type": "object"},
            "data": {"key": "value", "count": 42}
        }
        """.data(using: .utf8)!

        let definition = try JSONDecoder().decode(DatasourceDefinition.self, from: json)

        XCTAssertNotNil(definition.schema)
        let data = definition.rawData as? [String: Any]
        XCTAssertNotNil(data)
        XCTAssertEqual(data?["key"] as? String, "value")
        XCTAssertEqual(data?["count"] as? Int, 42)
    }

    func testDecodeWrappedFormatWithoutSchema() throws {
        let json = """
        {
            "data": [1, 2, 3]
        }
        """.data(using: .utf8)!

        let definition = try JSONDecoder().decode(DatasourceDefinition.self, from: json)

        XCTAssertNil(definition.schema)
        let data = definition.rawData as? [Int]
        XCTAssertNotNil(data)
        XCTAssertEqual(data, [1, 2, 3])
    }

    // MARK: - Raw Format Tests

    func testDecodeRawArrayFormat() throws {
        let json = """
        [
            {"id": "1", "title": "First"},
            {"id": "2", "title": "Second"}
        ]
        """.data(using: .utf8)!

        let definition = try JSONDecoder().decode(DatasourceDefinition.self, from: json)

        XCTAssertNil(definition.schema, "Raw format should have no schema")
        let data = definition.rawData as? [[String: Any]]
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 2)
    }

    func testDecodeRawObjectFormat() throws {
        let json = """
        {"name": "Test", "value": 123}
        """.data(using: .utf8)!

        let definition = try JSONDecoder().decode(DatasourceDefinition.self, from: json)

        XCTAssertNil(definition.schema, "Raw format should have no schema")
        let data = definition.rawData as? [String: Any]
        XCTAssertNotNil(data)
        XCTAssertEqual(data?["name"] as? String, "Test")
        XCTAssertEqual(data?["value"] as? Int, 123)
    }

    func testDecodeRawPrimitiveArray() throws {
        let json = "[1, 2, 3, 4, 5]".data(using: .utf8)!

        let definition = try JSONDecoder().decode(DatasourceDefinition.self, from: json)

        XCTAssertNil(definition.schema)
        let data = definition.rawData as? [Int]
        XCTAssertNotNil(data)
        XCTAssertEqual(data, [1, 2, 3, 4, 5])
    }

    func testDecodeRawStringArray() throws {
        let json = """
        ["apple", "banana", "cherry"]
        """.data(using: .utf8)!

        let definition = try JSONDecoder().decode(DatasourceDefinition.self, from: json)

        XCTAssertNil(definition.schema)
        let data = definition.rawData as? [String]
        XCTAssertNotNil(data)
        XCTAssertEqual(data, ["apple", "banana", "cherry"])
    }

    // MARK: - Schema Preservation Tests

    func testSchemaIsPreserved() throws {
        let json = """
        {
            "schema": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "id": {"type": "string"},
                        "name": {"type": "string"}
                    },
                    "required": ["id", "name"]
                }
            },
            "data": []
        }
        """.data(using: .utf8)!

        let definition = try JSONDecoder().decode(DatasourceDefinition.self, from: json)

        XCTAssertNotNil(definition.schema)
        if case .object(let schemaObj) = definition.schema {
            XCTAssertNotNil(schemaObj["type"])
            XCTAssertNotNil(schemaObj["items"])
        } else {
            XCTFail("Schema should be an object")
        }
    }

    // MARK: - Encoding Tests

    func testEncode() throws {
        let json = """
        {
            "data": [{"id": "1"}]
        }
        """.data(using: .utf8)!

        let definition = try JSONDecoder().decode(DatasourceDefinition.self, from: json)
        let encoded = try JSONEncoder().encode(definition)
        let decoded = try JSONDecoder().decode(DatasourceDefinition.self, from: encoded)

        let originalData = definition.rawData as? [[String: Any]]
        let decodedData = decoded.rawData as? [[String: Any]]
        XCTAssertEqual(originalData?.count, decodedData?.count)
    }

    // MARK: - Edge Cases

    func testEmptyArray() throws {
        let json = "[]".data(using: .utf8)!

        let definition = try JSONDecoder().decode(DatasourceDefinition.self, from: json)

        let data = definition.rawData as? [Any]
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 0)
    }

    func testEmptyObject() throws {
        let json = "{}".data(using: .utf8)!

        let definition = try JSONDecoder().decode(DatasourceDefinition.self, from: json)

        let data = definition.rawData as? [String: Any]
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 0)
    }

    func testNestedData() throws {
        let json = """
        {
            "data": {
                "users": [
                    {"id": "1", "profile": {"name": "Alice", "age": 30}}
                ]
            }
        }
        """.data(using: .utf8)!

        let definition = try JSONDecoder().decode(DatasourceDefinition.self, from: json)

        let data = definition.rawData as? [String: Any]
        XCTAssertNotNil(data)
        let users = data?["users"] as? [[String: Any]]
        XCTAssertNotNil(users)
        XCTAssertEqual(users?.count, 1)
        let profile = users?[0]["profile"] as? [String: Any]
        XCTAssertEqual(profile?["name"] as? String, "Alice")
    }
}
