//
//  SortByMergeTests.swift
//  App8EngineTests
//
//  sortBy and merge (app8-dsl docs/variables.md): the shared input/output
//  table from app8-conformance (fixtures/functions/sortBy-merge.json), kept
//  here as Fixtures/sortBy-merge.table (not .json: the parsing tests load
//  every .json fixture as an app).
//

import XCTest
@testable import App8Engine

final class SortByMergeTests: XCTestCase {

    private struct Table: Decodable {
        struct Case: Decodable { let expression: String }
        let cases: [Case]
    }

    private func tableData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sortBy-merge", withExtension: "table"))
        return try Data(contentsOf: url)
    }

    /// JSON-normalized, so 1 == 1.0 and NSNull == null.
    private func normalized(_ value: Any?) throws -> NSObject {
        let data = try JSONSerialization.data(withJSONObject: value ?? NSNull(), options: [.fragmentsAllowed, .sortedKeys])
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as! NSObject
    }

    @MainActor
    func testSharedTable() throws {
        let data = try tableData()
        let table = try JSONDecoder().decode(Table.self, from: data)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let expected = try XCTUnwrap(raw["cases"] as? [[String: Any]]).map { $0["expected"] }
        // Plain JSON values (as datasources deliver them), not AnyCodableValue wrappers.
        let variables = try XCTUnwrap(raw["variables"] as? [String: Any])
        let store = VariableStore()
        for (name, value) in variables {
            let type: VariableType = value is [Any] ? .array : (value is String ? .string : .object)
            try store.defineVariable(name: name, definition: VariableDefinition(type: type, initialValue: nil))
            try store.setValue(name: name, value: value is NSNull ? nil : value)
        }
        for (i, c) in table.cases.enumerated() {
            let result = try ExpressionEvaluator().evaluate(ExpressionParser().parse(c.expression), context: VariableContext(store: store))
            XCTAssertEqual(try normalized(result), try normalized(expected[i]), c.expression)
        }
    }

    /// The vendored copy equals app8-conformance's when that checkout is next to this repo.
    func testVendoredTableMatchesConformance() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for dir in ["app8-conformance", "app8-conformance-wt-dsl-gaps"] {
            let url = root.appendingPathComponent(dir).appendingPathComponent("fixtures/functions/sortBy-merge.json")
            guard let other = try? Data(contentsOf: url) else { continue }
            XCTAssertEqual(try normalized(JSONSerialization.jsonObject(with: other)), try normalized(JSONSerialization.jsonObject(with: tableData())), "\(url.path) differs: copy it to Fixtures/sortBy-merge.table")
            return
        }
    }
}
