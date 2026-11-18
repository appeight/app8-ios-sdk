//
//  ExpressionLiteralTests.swift
//  App8EngineTests
//
//  Array and object literals in expressions (app8-dsl docs/variables.md,
//  "Array and Object Literals"), including `}}` inside nested braces.
//

import XCTest
@testable import App8Engine

@MainActor
final class ExpressionLiteralTests: XCTestCase {
    private var store: VariableStore!
    private let resolver = PropertyResolver()

    override func setUp() {
        super.setUp()
        store = VariableStore()
        try! store.defineVariable(name: "newCount", definition: VariableDefinition(type: .number, initialValue: 3))
        try! store.defineVariable(name: "items", definition: VariableDefinition(type: .array, initialValue: [1, 2]))
        try! store.defineVariable(name: "name", definition: VariableDefinition(type: .string, initialValue: "Ann"))
    }

    private func r(_ s: String) throws -> NSObject {
        let v = try resolver.resolve(s, context: VariableContext(store: store))
        let data = try JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed, .sortedKeys])
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as! NSObject
    }

    private func json(_ s: String) -> NSObject {
        try! JSONSerialization.jsonObject(with: Data(s.utf8), options: [.fragmentsAllowed]) as! NSObject
    }

    func testObjectAndArrayLiteralsAreValues() throws {
        XCTAssertEqual(try r(#"{{[ {"title": "A"}, {"title": "B"} ]}}"#), json(#"[{"title":"A"},{"title":"B"}]"#))
        XCTAssertEqual(try r("{{[ {'title': 'New', 'count': newCount}, {title: 'All', count: length(items)} ]}}"), json(#"[{"title":"New","count":3},{"title":"All","count":2}]"#))
        XCTAssertEqual(try r("{{ {} }}"), json("{}"))
        XCTAssertEqual(try r("{{ {'a': {'b': [1, {'c': name}]}} }}"), json(#"{"a":{"b":[1,{"c":"Ann"}]}}"#))
        XCTAssertEqual(try r("{{{'a': 1}}}"), json(#"{"a":1}"#), "no spaces around the braces")
        XCTAssertEqual(try r("{{ {'a': {'b': 1}}.a.b }}"), json("1"))
        XCTAssertEqual(try r("{{ {'k': '}}'}.k }}"), json(#""}}""#), "a }} inside quotes does not end the expression")
    }

    func testInterpolationAfterANestedLiteral() throws {
        let s = try resolver.resolveToString("x {{ {'a': {'b': 2}}.a.b }} y {{name}}", context: VariableContext(store: store))
        XCTAssertEqual(s, "x 2 y Ann")
    }

    func testObjectLiteralValuesAreDependencies() throws {
        let deps = try XCTUnwrap(ExpressionDependencies.names(in: ["{{ {'n': newCount, 'm': {k: name}} }}"]))
        XCTAssertTrue(deps.contains("newCount") && deps.contains("name"), "\(deps)")
    }

    func testSyntaxErrors() {
        XCTAssertThrowsError(try ExpressionParser().parse("{{ {'a': 1,} }}"))
        XCTAssertThrowsError(try ExpressionParser().parse("{{ {1: 2} }}"))
    }
}
