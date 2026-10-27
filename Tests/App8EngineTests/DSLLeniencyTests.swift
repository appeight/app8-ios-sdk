//
//  DSLLeniencyTests.swift
//  App8EngineTests
//
//  The documented DSL shapes must decode: string text alignment, `sibling(id)`
//  constraint targets, collection layout at `content.layout`, inline templates
//  without an `id`, and `navigationBar.search`.
//

import XCTest
@testable import App8Engine

final class DSLLeniencyTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testTextAlignmentAcceptsNamesAndIntegers() throws {
        let named = try decode(DSL.Model.Style.TextModel.self, #"{"fontSize": 13, "alignment": "center"}"#)
        XCTAssertEqual(named.alignment, .center)
        let raw = try decode(DSL.Model.Style.TextModel.self, #"{"fontSize": 13, "alignment": 2}"#)
        XCTAssertEqual(raw.alignment, .right)
        XCTAssertThrowsError(try decode(DSL.Model.Style.TextModel.self, #"{"fontSize": 13, "alignment": "middle"}"#))
    }

    func testSiblingTargetWrappedAndBare() throws {
        let wrapped = try decode(DSL.Model.Layout.Constraint.Target.self, #""sibling(title)""#)
        guard case .sibling("title") = wrapped else { return XCTFail("got \(wrapped)") }
        let bare = try decode(DSL.Model.Layout.Constraint.Target.self, #""title""#)
        guard case .sibling("title") = bare else { return XCTFail("got \(bare)") }
        let safe = try decode(DSL.Model.Layout.Constraint.Target.self, #""safeArea(header)""#)
        guard case .safeArea("header") = safe else { return XCTFail("got \(safe)") }
    }

    func testCollectionLayoutAtContentLevelAndTemplateWithoutId() throws {
        let json = """
        {
          "type": "collection",
          "id": "list",
          "content": {
            "properties": { "data": "{{items}}" },
            "layout": { "type": "horizontal", "itemWidth": 240, "itemHeight": 430 },
            "template": { "type": "label", "content": { "properties": { "text": "{{item.title}}" } } }
          }
        }
        """
        let component = try decode(DSL.Model.Component.`Any`.self, json)
        let entity: DSL.Model.Component.Collection.Entity = try XCTUnwrap(component.asConcreteEntity())
        XCTAssertEqual(entity.content.properties.layout?.type, .horizontal)
        XCTAssertEqual(entity.content.properties.layout?.itemWidth, 240)
        XCTAssertNotNil(entity.content.template)
    }

    func testPositioningLayoutDoesNotBecomeCollectionLayout() throws {
        let json = """
        {
          "type": "collection",
          "id": "list",
          "content": {
            "properties": { "data": "{{items}}", "layout": { "type": "vertical" } },
            "layout": { "constraints": [ { "type": "top", "target": "superview" } ] },
            "template": { "id": "row", "type": "label", "content": { "properties": { "text": "x" } } }
          }
        }
        """
        let component = try decode(DSL.Model.Component.`Any`.self, json)
        let entity: DSL.Model.Component.Collection.Entity = try XCTUnwrap(component.asConcreteEntity())
        XCTAssertEqual(entity.content.properties.layout?.type, .vertical)
        XCTAssertNotNil(entity.content.layout)
    }

    func testNavigationBarSearch() throws {
        let bar = try decode(DSL.Model.NavigationBar.self, """
        { "search": { "placeholder": "Search", "bindVariable": "q", "placement": "integrated",
                      "onSubmit": { "type": "dismissKeyboard" } } }
        """)
        let search = try XCTUnwrap(bar.search)
        XCTAssertEqual(search.placeholder, "Search")
        XCTAssertEqual(search.bindVariable, "q")
        XCTAssertEqual(search.placement, .integrated)
        XCTAssertEqual(search.onSubmit?.count, 1)

        let unknown = try decode(DSL.Model.NavigationBar.self, #"{ "search": { "placement": "floating" } }"#)
        XCTAssertEqual(unknown.search?.placement, .automatic)
    }
}
