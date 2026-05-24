//
//  LocalizedStringTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

final class LocalizedStringTests: XCTestCase {

    private let decoder = JSONDecoder()

    // MARK: - Bare-string form (.literal)

    func test_decodesBareStringAsLiteral() throws {
        let data = Data(#""Hello, world""#.utf8)
        let value = try decoder.decode(LocalizedString.self, from: data)
        guard case .literal(let s) = value else {
            return XCTFail("Expected .literal, got \(value)")
        }
        XCTAssertEqual(s, "Hello, world")
    }

    func test_decodesEmptyStringAsLiteral() throws {
        let data = Data(#""""#.utf8)
        let value = try decoder.decode(LocalizedString.self, from: data)
        XCTAssertEqual(value.rawValue, "")
    }

    func test_literalKeepsExpressionPlaceholdersIntact() throws {
        // Literals MUST NOT be treated as keys, even when they look like
        // template strings — they pass through to {{var}} interpolation as-is.
        let data = Data(#""Hello {{user.name}}""#.utf8)
        let value = try decoder.decode(LocalizedString.self, from: data)
        XCTAssertEqual(value.rawValue, "Hello {{user.name}}")
    }

    // MARK: - i18n marker form (.key)

    func test_decodesI18nObjectAsKey() throws {
        let data = Data(#"{"$i18n":"home.greeting"}"#.utf8)
        let value = try decoder.decode(LocalizedString.self, from: data)
        guard case .key(let k) = value else {
            return XCTFail("Expected .key, got \(value)")
        }
        XCTAssertEqual(k, "home.greeting")
    }

    func test_i18nKeyRawValueReturnsKeyForDebugPlaceholder() throws {
        // Missing-translation render path uses rawValue as the visible
        // fallback. Authors expect to see the key, not an empty label.
        let data = Data(#"{"$i18n":"checkout.cta"}"#.utf8)
        let value = try decoder.decode(LocalizedString.self, from: data)
        XCTAssertEqual(value.rawValue, "checkout.cta")
    }

    // MARK: - Invalid shapes

    func test_throwsOnUnknownObjectKey() {
        // Object without $i18n is a malformed text value — should not silently
        // decode to empty string. Catches schema typos at decode time.
        let data = Data(#"{"translate":"home.greeting"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(LocalizedString.self, from: data))
    }

    func test_throwsOnNonStringI18nValue() {
        // {"$i18n": 42} is still wrong even though the key name matches —
        // value must be a string.
        let data = Data(#"{"$i18n":42}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(LocalizedString.self, from: data))
    }
}
