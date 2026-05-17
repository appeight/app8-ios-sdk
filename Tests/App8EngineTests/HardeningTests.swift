//
//  HardeningTests.swift
//  App8EngineTests
//
//  Covers the crash/security hardening: recursion & size limits, ImageLoader
//  URL rejection, substring overflow safety, match() ReDoS caps, UIFont fallback.
//

import XCTest
import UIKit
@testable import App8Engine

@MainActor
final class HardeningTests: XCTestCase {

    private var parser: ExpressionParser!
    private var evaluator: ExpressionEvaluator!
    private var context: VariableContext!

    override func setUp() {
        super.setUp()
        parser = ExpressionParser()
        evaluator = ExpressionEvaluator()
        let store = VariableStore()
        context = VariableContext(store: store)
    }

    // MARK: - Expression recursion limits (C2)

    func testDeeplyNestedExpressionParseThrows() {
        let depth = EngineLimits.maxExpressionDepth + 50
        let expr = String(repeating: "(", count: depth) + "1" + String(repeating: ")", count: depth)
        XCTAssertThrowsError(try parser.parse(expr)) { error in
            XCTAssertTrue(error is ExpressionError)
        }
    }

    func testShallowExpressionStillParses() throws {
        let node = try parser.parse("(((1 + 2)))")
        XCTAssertEqual(try evaluator.evaluate(node, context: context) as? Int, 3)
    }

    func testDeeplyNestedExpressionEvaluateThrows() {
        // Parse caps depth too, so build the over-deep AST by hand.
        var node: ExpressionNode = .literal(.string("x"))
        for _ in 0..<(EngineLimits.maxExpressionDepth + 50) {
            node = .unaryOperation(operator: "!", operand: node)
        }
        XCTAssertThrowsError(try evaluator.evaluate(node, context: context))
    }

    // MARK: - JSON decode depth limit (C4)

    func testDeeplyNestedJSONDecodeThrows() {
        let depth = EngineLimits.maxJSONDepth + 200
        let json = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        let data = Data(json.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(JSONValue.self, from: data))
        XCTAssertThrowsError(try JSONDecoder().decode(AnyCodable.self, from: data))
    }

    func testShallowJSONStillDecodes() throws {
        let data = Data(#"{"a":{"b":[1,2,3]}}"#.utf8)
        XCTAssertNoThrow(try JSONDecoder().decode(JSONValue.self, from: data))
    }

    // MARK: - DeepMerge depth limit (C4)

    func testDeepMergeStopsAtDepthLimitWithoutCrashing() {
        func nested(_ depth: Int) -> JSONValue {
            var v: JSONValue = .string("leaf")
            for _ in 0..<depth { v = .object(["child": v]) }
            return v
        }
        let depth = EngineLimits.maxDeepMergeDepth + 100
        guard case .object(let base) = nested(depth) else { return XCTFail("setup") }
        let merged = deepMerge(base: base, override: nested(depth))
        XCTAssertNotNil(merged["child"])  // returns without stack overflow
    }

    // MARK: - substring overflow safety (C8)

    func testSubstringWithNegativeLengthReturnsEmpty() throws {
        XCTAssertEqual(try eval("substring('hello', 10, -5)") as? String, "")
    }

    func testSubstringWithHugeArgumentsDoesNotTrap() throws {
        XCTAssertEqual(try eval("substring('hello', 99999999999, 99999999999)") as? String, "")
        XCTAssertEqual(try eval("substring('hello', 1, 3)") as? String, "ell")
    }

    // MARK: - match() ReDoS caps (S5)

    func testHasNestedQuantifierDetection() {
        XCTAssertTrue(ExpressionEvaluator.hasNestedQuantifier("(a+)+"))
        XCTAssertTrue(ExpressionEvaluator.hasNestedQuantifier("(.*)*"))
        XCTAssertTrue(ExpressionEvaluator.hasNestedQuantifier("(a+){2,}"))
        XCTAssertFalse(ExpressionEvaluator.hasNestedQuantifier("abc"))
        XCTAssertFalse(ExpressionEvaluator.hasNestedQuantifier("a+b+"))
        XCTAssertFalse(ExpressionEvaluator.hasNestedQuantifier("(ab)+"))
    }

    func testMatchRejectsCatastrophicPattern() throws {
        // Classic ReDoS input — must return false, not hang.
        let result = try eval("match('aaaaaaaaaaaaaaaaaaaaaaaaa!', '(a+)+b')")
        XCTAssertEqual(result as? Bool, false)
    }

    func testMatchStillWorksForSafePattern() throws {
        XCTAssertEqual(try eval("match('hello123', '[0-9]+')") as? Bool, true)
        XCTAssertEqual(try eval("match('hello', '[0-9]+')") as? Bool, false)
    }

    // MARK: - ImageLoader URL scheme allow-list (S1)

    func testImageLoaderRejectsFileURL() async {
        let loader = ImageLoader()
        let data = await loader.load(urlString: "file:///etc/passwd")
        XCTAssertNil(data)
    }

    func testImageLoaderRejectsNonHTTPScheme() async {
        let loader = ImageLoader()
        let ftp = await loader.load(urlString: "ftp://example.com/x.png")
        XCTAssertNil(ftp)
        let invalid = await loader.load(urlString: "not a url")
        XCTAssertNil(invalid)
    }

    // MARK: - UIFont trait fallback (C1)

    func testUIFontWithUnsupportedTraitDoesNotCrash() {
        let font = UIFont.systemFont(ofSize: 14).bold()
        XCTAssertGreaterThan(font.pointSize, 0)
    }

    // MARK: - Helper

    private func eval(_ expression: String) throws -> Any? {
        let node = try parser.parse(expression)
        return try evaluator.evaluate(node, context: context)
    }
}
