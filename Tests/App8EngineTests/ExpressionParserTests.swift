//
//  ExpressionParserTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

final class ExpressionParserTests: XCTestCase {
    var parser: ExpressionParser!

    override func setUp() {
        super.setUp()
        parser = ExpressionParser()
    }

    // MARK: - Literal Tests
    func testParseLiterals() throws {
        XCTAssertEqual(try parseAndDescribe("true"), ".literal(true)")
        XCTAssertEqual(try parseAndDescribe("false"), ".literal(false)")

        XCTAssertEqual(try parseAndDescribe("42"), ".literal(42)")
        XCTAssertEqual(try parseAndDescribe("3.14"), ".literal(3.14)")

        XCTAssertEqual(try parseAndDescribe("'hello'"), ".literal(hello)")
        XCTAssertEqual(try parseAndDescribe("\"world\""), ".literal(world)")

        XCTAssertEqual(try parseAndDescribe("null"), ".literal(null)")

        let arrayNode = try parser.parse("[1, 2, 3]")
        if case .literal(let value) = arrayNode {
            let arr = value.anyValue as? [Any]
            XCTAssertEqual(arr?.count, 3)
        } else {
            XCTFail("Expected array literal")
        }
    }

    // MARK: - Variable Tests
    func testParseVariables() throws {
        XCTAssertEqual(try parseAndDescribe("myVariable"), ".variable(myVariable)")
        XCTAssertEqual(try parseAndDescribe("_private"), ".variable(_private)")
        XCTAssertEqual(try parseAndDescribe("var123"), ".variable(var123)")
    }

    // MARK: - Binary Operation Tests
    func testParseArithmetic() throws {
        XCTAssertEqual(try parseAndDescribe("1 + 2"), ".binaryOperation(+)")
        XCTAssertEqual(try parseAndDescribe("a - b"), ".binaryOperation(-)")
        XCTAssertEqual(try parseAndDescribe("x * y"), ".binaryOperation(*)")
        XCTAssertEqual(try parseAndDescribe("10 / 2"), ".binaryOperation(/)")
    }

    func testParseComparison() throws {
        XCTAssertEqual(try parseAndDescribe("a > b"), ".binaryOperation(>)")
        XCTAssertEqual(try parseAndDescribe("x >= y"), ".binaryOperation(>=)")
        XCTAssertEqual(try parseAndDescribe("m < n"), ".binaryOperation(<)")
        XCTAssertEqual(try parseAndDescribe("p <= q"), ".binaryOperation(<=)")
    }

    func testParseEquality() throws {
        XCTAssertEqual(try parseAndDescribe("a === b"), ".binaryOperation(===)")
        XCTAssertEqual(try parseAndDescribe("x !== y"), ".binaryOperation(!==)")
        XCTAssertEqual(try parseAndDescribe("m == n"), ".binaryOperation(==)")
        XCTAssertEqual(try parseAndDescribe("p != q"), ".binaryOperation(!=)")
    }

    func testParseLogical() throws {
        XCTAssertEqual(try parseAndDescribe("a && b"), ".binaryOperation(&&)")
        XCTAssertEqual(try parseAndDescribe("x || y"), ".binaryOperation(||)")
    }

    // MARK: - Unary Operation Tests
    func testParseUnary() throws {
        XCTAssertEqual(try parseAndDescribe("!isValid"), ".unaryOperation(!)")
        XCTAssertEqual(try parseAndDescribe("-count"), ".unaryOperation(-)")
        XCTAssertEqual(try parseAndDescribe("!!value"), ".unaryOperation(!)")
    }

    // MARK: - Member Access Tests
    func testParseMemberAccess() throws {
        XCTAssertEqual(try parseAndDescribe("user.name"), ".memberAccess(name)")
        XCTAssertEqual(try parseAndDescribe("data.items.length"), ".memberAccess(length)")
    }

    // MARK: - Array Access Tests
    func testParseArrayAccess() throws {
        XCTAssertEqual(try parseAndDescribe("items[0]"), ".arrayAccess")
        XCTAssertEqual(try parseAndDescribe("matrix[i][j]"), ".arrayAccess")
    }

    // MARK: - Function Call Tests
    func testParseFunctionCall() throws {
        XCTAssertEqual(try parseAndDescribe("length()"), ".functionCall(length)")
        XCTAssertEqual(try parseAndDescribe("items.includes('test')"), ".functionCall(includes)")
        XCTAssertEqual(try parseAndDescribe("parseInt('123')"), ".functionCall(parseInt)")
    }

    // MARK: - Ternary Tests
    func testParseTernary() throws {
        XCTAssertEqual(try parseAndDescribe("a ? b : c"), ".ternary")
        XCTAssertEqual(try parseAndDescribe("x > 0 ? 'positive' : 'negative'"), ".ternary")
    }

    // MARK: - Complex Expression Tests
    func testParseComplexExpressions() throws {
        // Operator precedence
        let expr1 = try parser.parse("a + b * c")
        if case .binaryOperation(let op, _, _) = expr1 {
            XCTAssertEqual(op, "+")
        }

        // Parentheses
        let expr2 = try parser.parse("(a + b) * c")
        if case .binaryOperation(let op, _, _) = expr2 {
            XCTAssertEqual(op, "*")
        }

        // Nested ternary
        _ = try parser.parse("a ? b ? c : d : e")

        // Complex boolean expression
        _ = try parser.parse("isValid && (count > 0 || hasDefault)")
    }

    // MARK: - Expression Wrapper Tests
    func testParseWithBrackets() throws {
        XCTAssertEqual(try parseAndDescribe("{{myVar}}"), ".variable(myVar)")
        XCTAssertEqual(try parseAndDescribe("{{ a + b }}"), ".binaryOperation(+)")
    }

    // MARK: - Error Tests
    func testParseErrors() {
        XCTAssertThrowsError(try parser.parse(""))
        XCTAssertThrowsError(try parser.parse("{{}}"))
        XCTAssertThrowsError(try parser.parse("a +"))
        XCTAssertThrowsError(try parser.parse("(a + b"))
        XCTAssertThrowsError(try parser.parse("a ? b"))
        XCTAssertThrowsError(try parser.parse("'unterminated string"))
        XCTAssertThrowsError(try parser.parse("@invalid"))
    }

    // MARK: - Helper Methods
    private func parseAndDescribe(_ expression: String) throws -> String {
        let node = try parser.parse(expression)
        return describeNode(node)
    }

    private func describeNode(_ node: ExpressionNode) -> String {
        switch node {
        case .literal(let value):
            switch value {
            case .null:
                return ".literal(null)"
            case .bool(let b):
                return ".literal(\(b))"
            case .int(let i):
                return ".literal(\(i))"
            case .double(let d):
                return ".literal(\(d))"
            case .string(let s):
                return ".literal(\(s))"
            case .array:
                return ".literal(array)"
            }

        case .variable(let name):
            return ".variable(\(name))"

        case .binaryOperation(let op, _, _):
            return ".binaryOperation(\(op))"

        case .unaryOperation(let op, _):
            return ".unaryOperation(\(op))"

        case .functionCall(let name, _):
            return ".functionCall(\(name))"

        case .memberAccess(_, let member):
            return ".memberAccess(\(member))"

        case .arrayAccess:
            return ".arrayAccess"

        case .ternary:
            return ".ternary"
        }
    }
}
