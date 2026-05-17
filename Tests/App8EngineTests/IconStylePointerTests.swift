//
//  IconStylePointerTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

/// Tests for the `"icon"` self-pointer pattern in `DSL.Model.Style.Icon`:
///   `"style": { "icon": { "id": "namedIconStyle", "type": "icon" } }`
@MainActor
final class IconStylePointerTests: XCTestCase {

    /// Builds a resolver from a styles JSON array, running the multi-pass resolution
    /// that App8.swift uses so that chains like color → icon → component work.
    private func buildResolver(from stylesJSON: String) throws -> (String) -> (any DSL.Model.Style.Entity)? {
        let data = stylesJSON.data(using: .utf8)!
        var styles = try JSONDecoder().decode([DSL.Model.Style.`Any`].self, from: data)

        var styleDict: [String: DSL.Model.Style.`Any`] = [:]
        for style in styles { styleDict[style.id] = style }

        var madeProgress = true
        while madeProgress {
            madeProgress = false
            for i in 0..<styles.count {
                let wasResolved = styles[i].isResolved()
                var copy = styles[i]
                copy.resolveStylePointers { styleDict[$0]?.asEntity() }
                styles[i] = copy
                styleDict[copy.id] = copy
                if !wasResolved && copy.isResolved() { madeProgress = true }
            }
        }

        return { styleDict[$0]?.asEntity() }
    }

    // MARK: - Self-pointer resolution

    func testIconSelfPointerResolvesTint() throws {
        // Styles: white color + onAccentIcon icon that uses it as tint
        let resolver = try buildResolver(from: """
        [
            { "id": "white", "type": "color", "content": "#FFFFFF" },
            {
                "id": "onAccentIcon",
                "type": "icon",
                "content": { "tint": { "id": "white", "type": "color" } }
            }
        ]
        """)

        let json = #"{ "icon": { "id": "onAccentIcon", "type": "icon" } }"#.data(using: .utf8)!
        var icon = try JSONDecoder().decode(DSL.Model.Style.Icon.self, from: json)

        XCTAssertNil(icon.tint, "tint should be nil before resolution")

        icon.resolveStylePointers(resolver: resolver)

        XCTAssertNotNil(icon.tint, "tint should be resolved")
        XCTAssertEqual(icon.tint?.light?.value, "FFFFFF")
    }

    func testIconSelfPointerResolvesColor() throws {
        // Variant using `color` field instead of `tint`
        let resolver = try buildResolver(from: """
        [
            { "id": "accent", "type": "color", "content": "#FF6600" },
            {
                "id": "accentIcon",
                "type": "icon",
                "content": { "color": { "id": "accent", "type": "color" } }
            }
        ]
        """)

        let json = #"{ "icon": { "id": "accentIcon", "type": "icon" } }"#.data(using: .utf8)!
        var icon = try JSONDecoder().decode(DSL.Model.Style.Icon.self, from: json)
        icon.resolveStylePointers(resolver: resolver)

        XCTAssertNotNil(icon.color)
        XCTAssertEqual(icon.color?.light?.value, "FF6600")
    }

    func testIconSelfPointerResolvesChainedColorRef() throws {
        // Chain: component → onAccentIcon → textOnAccent → white → #FFFFFF
        let resolver = try buildResolver(from: """
        [
            { "id": "white", "type": "color", "content": "#FFFFFF" },
            {
                "id": "textOnAccent",
                "type": "color",
                "content": {
                    "light": { "id": "white" },
                    "dark":  { "id": "white" }
                }
            },
            {
                "id": "onAccentIcon",
                "type": "icon",
                "content": { "tint": { "id": "textOnAccent", "type": "color" } }
            }
        ]
        """)

        let json = #"{ "icon": { "id": "onAccentIcon", "type": "icon" } }"#.data(using: .utf8)!
        var icon = try JSONDecoder().decode(DSL.Model.Style.Icon.self, from: json)
        icon.resolveStylePointers(resolver: resolver)

        XCTAssertEqual(icon.tint?.light?.value, "FFFFFF", "chained color ref should resolve to white")
    }

    func testIconSelfPointerUnknownIdLeavesFieldsNil() throws {
        // Pointer to a non-existent style → fields stay nil, no crash
        let resolver = try buildResolver(from: "[]")

        let json = #"{ "icon": { "id": "doesNotExist", "type": "icon" } }"#.data(using: .utf8)!
        var icon = try JSONDecoder().decode(DSL.Model.Style.Icon.self, from: json)
        icon.resolveStylePointers(resolver: resolver)

        XCTAssertNil(icon.tint)
        XCTAssertNil(icon.color)
    }

    func testIconSelfPointerUnresolved_isResolved_returnsFalse() throws {
        let json = #"{ "icon": { "id": "notResolved", "type": "icon" } }"#.data(using: .utf8)!
        let icon = try JSONDecoder().decode(DSL.Model.Style.Icon.self, from: json)
        XCTAssertFalse(icon.isResolved())
    }

    // MARK: - Backward compatibility

    func testIconStyleWithNoPointerDecodesNormally() throws {
        // Existing pattern — inline tint field — still works
        let resolver = try buildResolver(from: """
        [
            { "id": "white", "type": "color", "content": "#FFFFFF" }
        ]
        """)

        let json = #"{ "tint": { "id": "white", "type": "color" } }"#.data(using: .utf8)!
        var icon = try JSONDecoder().decode(DSL.Model.Style.Icon.self, from: json)
        icon.resolveStylePointers(resolver: resolver)

        XCTAssertEqual(icon.tint?.light?.value, "FFFFFF")
    }

    func testIconStyleEmptyDecodes() throws {
        let json = "{}".data(using: .utf8)!
        let icon = try JSONDecoder().decode(DSL.Model.Style.Icon.self, from: json)
        XCTAssertNil(icon.tint)
        XCTAssertNil(icon.color)
        XCTAssertTrue(icon.isResolved())
    }
}
