//
//  LenientDecodingTests.swift
//  App8EngineTests
//
//  Unknown or mistyped values are ignored, never fatal (DSL spec): the bad
//  value is dropped (its default applies), the screen and the component stay,
//  and a warning is logged. Android: DegradingDecodeTest.
//

import XCTest
import UIKit
@testable import App8Engine

@MainActor
final class LenientDecodingTests: XCTestCase {

    private func decodeScreen(_ json: String, warnings: inout [String]) throws -> DSL.Model.Component.`Any` {
        var collected: [String] = []
        defer { warnings = collected }
        return try LenientDocumentDecoding.decode(DSL.Model.Component.`Any`.self, from: Data(json.utf8),
                                                 using: JSONDecoder()) { collected.append($0) }
    }

    private func label(_ c: DSL.Model.Component.`Any`?) -> DSL.Model.Component.Label.C? {
        c?.asConcreteEntity()?.content
    }

    func testMistypedScreenFieldsAreDroppedNotFatal() throws {
        var warnings: [String] = []
        let screen = try decodeScreen(#"""
        { "type": "screen", "id": "s", "content": {
            "navigationBar": { "title": 5, "backLabel": "Back" },
            "hidesTabBar": "no",
            "children": [ { "type": "label", "id": "l", "content": { "properties": { "text": "Hi" } } } ] } }
        """#, warnings: &warnings)
        let content = try XCTUnwrap(screen.asConcreteEntity() as DSL.Model.Component.ConcreteEntity<DSL.Model.Component.View.C>?).content
        XCTAssertNil(content.navigationBar?.title, "the mistyped title is ignored")
        XCTAssertEqual(content.navigationBar?.backLabel, "Back", "its siblings stay")
        XCTAssertNil(content.hidesTabBar)
        XCTAssertEqual(content.children.count, 1)
        XCTAssertEqual(warnings.count, 2)
        XCTAssertTrue(warnings.allSatisfy { $0.hasPrefix("value.ignored:") })
        XCTAssertTrue(warnings.contains { $0.contains("content.navigationBar.title") })
    }

    func testChildWithMistypedPropertyKeepsTheRest() throws {
        var warnings: [String] = []
        let screen = try decodeScreen(#"""
        { "type": "screen", "id": "s", "content": { "children": [
            { "type": "label", "id": "l", "content": { "properties": { "text": "Kept", "numberOfLines": "two" } } },
            { "type": "hologram", "id": "u", "content": { "properties": {} } }
        ] } }
        """#, warnings: &warnings)
        let children = screen.asEntity()?.content.children ?? []
        XCTAssertEqual(children.count, 1, "the unknown component type is skipped, the label stays")
        let props = try XCTUnwrap(label(children.first)).properties
        XCTAssertNil(props.numberOfLines, "the mistyped value is ignored")
        if case .literal(let text) = props.text { XCTAssertEqual(text, "Kept") } else { XCTFail("text lost") }
    }

    func testUnusableRootStillFails() {
        var warnings: [String] = []
        XCTAssertThrowsError(try decodeScreen(#"{ "id": "no-type", "content": {} }"#, warnings: &warnings))
        XCTAssertThrowsError(try decodeScreen(#"[1, 2]"#, warnings: &warnings))
    }

    func testRemovingPaths() {
        struct K: CodingKey {
            var stringValue: String; var intValue: Int?
            init(_ s: String) { stringValue = s; intValue = nil }
            init(_ i: Int) { stringValue = "Index \(i)"; intValue = i }
            init?(stringValue: String) { self.init(stringValue) }
            init?(intValue: Int) { self.init(intValue) }
        }
        let root: [String: Any] = ["a": ["b": [1, ["c": 2, "d": 3]]]]
        let out = LenientDocumentDecoding.removing([K("a"), K("b"), K(1), K("c")], from: root) as? [String: Any]
        let inner = ((out?["a"] as? [String: Any])?["b"] as? [Any])?[1] as? [String: Any]
        XCTAssertNil(inner?["c"])
        XCTAssertEqual(inner?["d"] as? Int, 3)
        XCTAssertNil(LenientDocumentDecoding.removing([K("missing")], from: root))
    }

    /// End to end: the screen renders instead of the engine's error screen.
    func testRenderedChildKeepsItsGoodValues() throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 200))
        try harness.render(#"""
        { "type": "view", "id": "root", "content": { "layout": { "width": 390, "height": 200 }, "children": [
          { "type": "label", "id": "l", "content": {
              "properties": { "text": "Still here", "numberOfLines": { "oops": true } },
              "layout": { "top": 0, "leading": 0, "trailing": 0 } } } ] } }
        """#)
        func labels(_ v: UIView) -> [UILabel] { ((v as? UILabel).map { [$0] } ?? []) + v.subviews.flatMap(labels) }
        XCTAssertTrue(labels(harness.superview).contains { $0.text == "Still here" })
    }
}
