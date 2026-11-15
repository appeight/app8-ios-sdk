//
//  ControlFlowActionTests.swift
//  App8EngineTests
//
//  `forEach`, `with` and the array actions (`insertArrayItem`,
//  `upsertArrayItem`, `removeArrayItem`, `incrementArrayItem` null keys).
//

import XCTest
@testable import App8Engine

@MainActor
final class ControlFlowActionTests: XCTestCase {

    private var harness: RenderHarness!
    private var root: CViewModel!

    override func setUp() async throws {
        harness = RenderHarness()
        try harness.render("""
        {
            "id": "root", "type": "view",
            "content": {
                "variables": {
                    "lines": { "type": "array", "initialValue": [ { "key": "a" }, { "key": "b" }, { "key": "a" } ] },
                    "cart": { "type": "array", "initialValue": [ { "key": "a", "quantity": 1 } ] },
                    "log": { "type": "array", "initialValue": [] },
                    "list": { "type": "array", "initialValue": ["x", "y"] },
                    "people": { "type": "array", "initialValue": [ { "id": 1, "name": "Ann", "age": 30 }, { "id": 2, "name": "Bo" } ] },
                    "empty": { "type": "array" },
                    "item": { "type": "string", "initialValue": "outer" }
                },
                "layout": { "width": 390, "height": 844 }
            }
        }
        """)
        root = try XCTUnwrap(harness.viewModel("root", as: CViewModel.self))
    }

    private func run(_ json: String) throws {
        let action = try JSONDecoder().decode(DSL.Model.Action.self, from: Data(json.utf8))
        root.executeAction(action)
    }

    private func value(_ name: String) -> Any? { root.variableStore.getValue(name: name) }

    // MARK: increment amount

    func testIncrementByAcceptsAnExpression() throws {
        try root.variableStore.setValue(name: "cart", value: [["key": "a", "quantity": 1]])
        try run(#"{ "type": "incrementArrayItem", "variableName": "cart", "matchBy": "key", "value": { "key": "a" }, "by": "{{people.length}}" }"#)
        let cart = try XCTUnwrap(value("cart") as? [[String: Any]])
        XCTAssertEqual(cart.first?["quantity"] as? Int, 3)
    }

    func testBadActionInAListReportsItsOwnPath() throws {
        let json = #"{ "type": "forEach", "items": "{{lines}}", "actions": [ { "type": "appendToArray", "variableName": 5 } ] }"#
        XCTAssertThrowsError(try JSONDecoder().decode(DSL.Model.Action.self, from: Data(json.utf8))) { error in
            let path = (error as? DecodingError).flatMap { error -> [CodingKey]? in
                switch error {
                case .typeMismatch(_, let c), .valueNotFound(_, let c), .keyNotFound(_, let c), .dataCorrupted(let c): return c.codingPath
                @unknown default: return nil
                }
            }?.map(\.stringValue) ?? []
            XCTAssertEqual(path, ["actions", "Index 0", "variableName"], "the failing field, not the list")
        }
    }

    // MARK: variable alias

    func testVariableKeyIsAnAliasOfVariableName() throws {
        try run(#"{ "type": "appendToArray", "variable": "log", "value": "alias" }"#)
        try run(#"{ "type": "appendToArray", "variableName": "log", "variable": "list", "value": "documented" }"#)
        XCTAssertEqual(value("log") as? [String], ["alias", "documented"], "variableName wins over the alias")
        XCTAssertEqual(value("list") as? [String], ["x", "y"])
    }

    // MARK: forEach

    func testForEachRunsNestedActionsPerElementInOrder() throws {
        try run("""
        { "type": "forEach", "items": "{{lines}}", "as": "line", "index": "i",
          "actions": [
            { "type": "incrementArrayItem", "variableName": "cart", "matchBy": "key", "value": { "key": "{{line.key}}" }, "by": 1 },
            { "type": "appendToArray", "variableName": "log", "value": "{{i}}:{{line.key}}" }
          ] }
        """)
        let cart = try XCTUnwrap(value("cart") as? [[String: Any]])
        XCTAssertEqual(cart.count, 2)
        XCTAssertEqual(cart[0]["key"] as? String, "a")
        XCTAssertEqual(cart[0]["quantity"] as? Int, 3)
        XCTAssertEqual(cart[1]["key"] as? String, "b")
        XCTAssertEqual(cart[1]["quantity"] as? Int, 1)
        XCTAssertEqual(value("log") as? [String], ["0:a", "1:b", "2:a"])
    }

    func testForEachDefaultsToItemAndShadowsOnlyInside() throws {
        try run("""
        { "type": "forEach", "items": ["p", "q"], "actions": { "type": "appendToArray", "variableName": "log", "value": "{{item}}" } }
        """)
        XCTAssertEqual(value("log") as? [String], ["p", "q"])
        XCTAssertEqual(value("item") as? String, "outer")
    }

    func testForEachEvaluatesItemsOnce() throws {
        // Appending to the walked array must not add iterations.
        try run("""
        { "type": "forEach", "items": "{{list}}", "as": "x",
          "actions": [ { "type": "appendToArray", "variableName": "list", "value": "{{x}}!" } ] }
        """)
        XCTAssertEqual(value("list") as? [String], ["x", "y", "x!", "y!"])
    }

    func testForEachNullOrNonArrayRunsNothing() throws {
        try run(#"{ "type": "forEach", "items": "{{empty}}", "actions": [ { "type": "appendToArray", "variableName": "log", "value": 1 } ] }"#)
        try run(#"{ "type": "forEach", "items": "{{item}}", "actions": [ { "type": "appendToArray", "variableName": "log", "value": 1 } ] }"#)
        XCTAssertEqual((value("log") as? [Any])?.count, 0)
    }

    func testNestedForEach() throws {
        try run("""
        { "type": "forEach", "items": [1, 2], "as": "a",
          "actions": { "type": "forEach", "items": ["x", "y"], "as": "b",
                       "actions": { "type": "appendToArray", "variableName": "log", "value": "{{a}}{{b}}" } } }
        """)
        XCTAssertEqual(value("log") as? [String], ["1x", "1y", "2x", "2y"])
    }

    // MARK: with

    func testWithBindsValuesOnceForNestedActions() throws {
        try run("""
        { "type": "with", "values": { "product": "{{people[1]}}", "qty": 2, "label": "n={{people.length}}" },
          "actions": [
            { "type": "appendToArray", "variableName": "log", "value": { "name": "{{product.name}}", "qty": "{{qty}}" } },
            { "type": "appendToArray", "variableName": "people", "value": { "id": 3 } },
            { "type": "appendToArray", "variableName": "log", "value": "{{label}}" }
          ] }
        """)
        let log = try XCTUnwrap(value("log") as? [Any])
        let first = try XCTUnwrap(log.first as? [String: Any])
        XCTAssertEqual(first["name"] as? String, "Bo")
        XCTAssertEqual(first["qty"] as? Int, 2)
        // `label` was evaluated before the append.
        XCTAssertEqual(log.last as? String, "n=2")
    }

    // MARK: Array actions

    func testInsertArrayItem() throws {
        try run(#"{ "type": "insertArrayItem", "variableName": "list", "value": "first" }"#)
        try run(#"{ "type": "insertArrayItem", "variableName": "list", "value": "last", "index": -1 }"#)
        try run(#"{ "type": "insertArrayItem", "variableName": "list", "value": "beforeLast", "index": -2 }"#)
        try run(#"{ "type": "insertArrayItem", "variableName": "list", "value": "far", "index": 99 }"#)
        XCTAssertEqual(value("list") as? [String], ["first", "x", "y", "beforeLast", "last", "far"])
        try run(#"{ "type": "insertArrayItem", "variableName": "empty", "value": 1, "index": 5 }"#)
        XCTAssertEqual(value("empty") as? [Int], [1])
    }

    func testUpsertReplacesExactlyOrInserts() throws {
        try run(#"{ "type": "upsertArrayItem", "variableName": "people", "matchBy": "id", "value": { "id": 1, "name": "Ann B" } }"#)
        var people = try XCTUnwrap(value("people") as? [[String: Any]])
        XCTAssertEqual(people.count, 2)
        XCTAssertEqual(people[0]["name"] as? String, "Ann B")
        XCTAssertNil(people[0]["age"], "replaced exactly, old fields dropped")

        try run(#"{ "type": "upsertArrayItem", "variableName": "people", "matchBy": "id", "value": { "id": 9 }, "position": "start" }"#)
        try run(#"{ "type": "upsertArrayItem", "variableName": "people", "matchBy": "id", "value": { "id": 10 } }"#)
        people = try XCTUnwrap(value("people") as? [[String: Any]])
        XCTAssertEqual(people.map { $0["id"] as? Int }, [9, 1, 2, 10])

        // Missing key: no-op.
        try run(#"{ "type": "upsertArrayItem", "variableName": "people", "matchBy": "id", "value": { "name": "nobody" } }"#)
        XCTAssertEqual((value("people") as? [Any])?.count, 4)
    }

    func testRemoveArrayItem() throws {
        try run(#"{ "type": "removeArrayItem", "variableName": "lines", "matchBy": "key", "value": "a" }"#)
        XCTAssertEqual((value("lines") as? [[String: Any]])?.map { $0["key"] as? String }, ["b"])

        try run(#"{ "type": "removeArrayItem", "variableName": "list", "index": -1 }"#)
        XCTAssertEqual(value("list") as? [String], ["x"])
        try run(#"{ "type": "removeArrayItem", "variableName": "list", "index": 7 }"#)
        XCTAssertEqual(value("list") as? [String], ["x"])

        // An object value uses its own matchBy key; a null key is a no-op.
        try run(#"{ "type": "removeArrayItem", "variableName": "people", "matchBy": "id", "value": { "id": 2 } }"#)
        try run(#"{ "type": "removeArrayItem", "variableName": "people", "matchBy": "id", "value": "{{people[0].nokey}}" }"#)
        XCTAssertEqual((value("people") as? [[String: Any]])?.map { $0["id"] as? Int }, [1])
    }

    func testIncrementArrayItemNullKeyIsNoOp() throws {
        try run(#"{ "type": "incrementArrayItem", "variableName": "cart", "matchBy": "key", "value": { "key": "{{cart[0].nokey}}" } }"#)
        try run(#"{ "type": "incrementArrayItem", "variableName": "cart", "matchBy": "key", "value": { "title": "no key" } }"#)
        let cart = try XCTUnwrap(value("cart") as? [[String: Any]])
        XCTAssertEqual(cart.count, 1)
        XCTAssertEqual(cart[0]["quantity"] as? Int, 1)
    }
}
