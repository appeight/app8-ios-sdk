//
//  PropertyResolverTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

@MainActor
class PropertyResolverTests: XCTestCase {
    var resolver: PropertyResolver!
    var testContext: VariableContext!
    var variableStore: VariableStore!

    override func setUp() {
        super.setUp()
        resolver = PropertyResolver()
        variableStore = VariableStore()

        try! variableStore.defineVariable(name: "name", definition: VariableDefinition(type: .string, initialValue: "John"))
        try! variableStore.defineVariable(name: "age", definition: VariableDefinition(type: .number, initialValue: 25))
        try! variableStore.defineVariable(name: "isActive", definition: VariableDefinition(type: .boolean, initialValue: true))
        try! variableStore.defineVariable(name: "items", definition: VariableDefinition(type: .array, initialValue: ["apple", "banana", "cherry"]))
        try! variableStore.defineVariable(name: "user", definition: VariableDefinition(type: .object, initialValue: [
            "firstName": "Jane",
            "lastName": "Doe",
            "email": "jane@example.com"
        ]))
        try! variableStore.defineVariable(name: "count", definition: VariableDefinition(type: .number, initialValue: 3))

        testContext = VariableContext(store: variableStore)
    }

    // MARK: - containsExpression Tests

    func testContainsExpressionTrue() {
        XCTAssertTrue(resolver.containsExpression("Hello {{name}}"))
        XCTAssertTrue(resolver.containsExpression("{{name}}"))
        XCTAssertTrue(resolver.containsExpression("{{a}} and {{b}}"))
    }

    func testContainsExpressionFalse() {
        XCTAssertFalse(resolver.containsExpression("Hello World"))
        XCTAssertFalse(resolver.containsExpression("Just text"))
        XCTAssertFalse(resolver.containsExpression("{{ incomplete"))
        XCTAssertFalse(resolver.containsExpression("incomplete }}"))
    }

    // MARK: - Single Expression Resolution Tests

    func testResolveSingleExpressionReturnsRawValue() throws {
        // When entire value is a single expression, return raw type (not string)
        let result = try resolver.resolve("{{name}}", context: testContext)
        XCTAssertEqual(result as? String, "John")
    }

    func testResolveSingleExpressionNumber() throws {
        let result = try resolver.resolve("{{age}}", context: testContext)
        XCTAssertEqual(result as? Int, 25)
    }

    func testResolveSingleExpressionBoolean() throws {
        let result = try resolver.resolve("{{isActive}}", context: testContext)
        XCTAssertEqual(result as? Bool, true)
    }

    func testResolveSingleExpressionArray() throws {
        let result = try resolver.resolve("{{items}}", context: testContext)
        XCTAssertEqual(result as? [String], ["apple", "banana", "cherry"])
    }

    func testResolveSingleExpressionWithSpaces() throws {
        // Whitespace around expression should still return raw value
        let result = try resolver.resolve("  {{age}}  ", context: testContext)
        XCTAssertEqual(result as? Int, 25)
    }

    // MARK: - String Interpolation Tests

    func testResolveStringInterpolation() throws {
        let result = try resolver.resolve("Hello {{name}}!", context: testContext)
        XCTAssertEqual(result as? String, "Hello John!")
    }

    func testResolveMultipleExpressions() throws {
        let result = try resolver.resolve("{{name}} is {{age}} years old", context: testContext)
        XCTAssertEqual(result as? String, "John is 25 years old")
    }

    func testResolveExpressionAtStart() throws {
        let result = try resolver.resolve("{{name}} says hello", context: testContext)
        XCTAssertEqual(result as? String, "John says hello")
    }

    func testResolveExpressionAtEnd() throws {
        let result = try resolver.resolve("Hello {{name}}", context: testContext)
        XCTAssertEqual(result as? String, "Hello John")
    }

    func testResolveExpressionInMiddle() throws {
        let result = try resolver.resolve("Say {{name}} please", context: testContext)
        XCTAssertEqual(result as? String, "Say John please")
    }

    // MARK: - Complex Expression Tests

    func testResolveNestedObjectAccess() throws {
        let result = try resolver.resolve("{{user.firstName}}", context: testContext)
        XCTAssertEqual(result as? String, "Jane")
    }

    func testResolveArrayAccess() throws {
        let result = try resolver.resolve("{{items[0]}}", context: testContext)
        XCTAssertEqual(result as? String, "apple")
    }

    func testResolveTernaryExpression() throws {
        let result = try resolver.resolve("{{isActive ? 'Yes' : 'No'}}", context: testContext)
        XCTAssertEqual(result as? String, "Yes")
    }

    func testResolveArithmeticExpression() throws {
        let result = try resolver.resolve("{{age + 5}}", context: testContext)
        XCTAssertEqual(result as? Int, 30)
    }

    func testResolveFunctionCall() throws {
        let result = try resolver.resolve("{{length(items)}}", context: testContext)
        XCTAssertEqual(result as? Int, 3)
    }

    // MARK: - resolveToString Tests

    func testResolveToStringAlwaysReturnsString() throws {
        XCTAssertEqual(try resolver.resolveToString("{{name}}", context: testContext), "John")
        XCTAssertEqual(try resolver.resolveToString("{{age}}", context: testContext), "25")
        XCTAssertEqual(try resolver.resolveToString("{{isActive}}", context: testContext), "true")
    }

    func testResolveToStringWithInterpolation() throws {
        let result = try resolver.resolveToString("Count: {{count}}", context: testContext)
        XCTAssertEqual(result, "Count: 3")
    }

    func testResolveToStringPlainText() throws {
        let result = try resolver.resolveToString("Plain text", context: testContext)
        XCTAssertEqual(result, "Plain text")
    }

    // MARK: - resolveAny Tests

    func testResolveAnyWithString() throws {
        let result = try resolver.resolveAny("Hello {{name}}", context: testContext)
        XCTAssertEqual(result as? String, "Hello John")
    }

    func testResolveAnyWithNonString() throws {
        let result = try resolver.resolveAny(42, context: testContext)
        XCTAssertEqual(result as? Int, 42)
    }

    func testResolveAnyWithArray() throws {
        let result = try resolver.resolveAny(["{{name}}", "{{age}}"], context: testContext)
        let arrayResult = result as? [Any]
        XCTAssertEqual(arrayResult?[0] as? String, "John")
        XCTAssertEqual(arrayResult?[1] as? Int, 25)
    }

    func testResolveAnyWithDictionary() throws {
        let result = try resolver.resolveAny(["greeting": "Hello {{name}}"], context: testContext)
        let dictResult = result as? [String: Any]
        XCTAssertEqual(dictResult?["greeting"] as? String, "Hello John")
    }

    func testResolveAnyWithPlainString() throws {
        let result = try resolver.resolveAny("No expressions here", context: testContext)
        XCTAssertEqual(result as? String, "No expressions here")
    }

    // MARK: - Error Handling Tests

    func testResolveInvalidExpressionKeepsOriginal() throws {
        // Unevaluable expressions are left verbatim rather than throwing.
        let result = try resolver.resolve("Hello {{undefinedVar}}", context: testContext)
        XCTAssertEqual(result as? String, "Hello {{undefinedVar}}")
    }

    func testResolveUnclosedBracket() throws {
        // Unclosed expression should be treated as literal
        let result = try resolver.resolve("Hello {{name", context: testContext)
        XCTAssertEqual(result as? String, "Hello {{name")
    }

    // MARK: - Edge Cases

    func testResolveEmptyString() throws {
        let result = try resolver.resolve("", context: testContext)
        XCTAssertEqual(result as? String, "")
    }

    func testResolveOnlyText() throws {
        let result = try resolver.resolve("Just plain text", context: testContext)
        XCTAssertEqual(result as? String, "Just plain text")
    }

    func testResolveMultipleExpressionsWithArithmetic() throws {
        let result = try resolver.resolve("{{count}} items: {{items[0]}}, {{items[1]}}", context: testContext)
        XCTAssertEqual(result as? String, "3 items: apple, banana")
    }

    func testResolveComplexInterpolation() throws {
        let result = try resolver.resolve("{{user.firstName}} {{user.lastName}} ({{user.email}})", context: testContext)
        XCTAssertEqual(result as? String, "Jane Doe (jane@example.com)")
    }

}
