import XCTest
@testable import App8Engine

/// Per-node `ios` / `android` overrides and `platforms` filters
/// (app8-dsl docs/platforms.md). Mirrors the Android engine's PlatformOverridesTest.
@MainActor
final class PlatformOverridesTests: XCTestCase {

    private func json(_ s: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))
    }

    private func object(_ s: String) throws -> [String: JSONValue] {
        guard case .object(let o) = try json(s) else { throw XCTSkip("not an object") }
        return o
    }

    /// Decodes a screen the way the engine loads one (templates, then overrides).
    private func decodeScreen(_ s: String, resolver: TemplateResolver? = nil) throws -> DSL.Model.Component.`Any` {
        let data = try TemplatePreprocessor.prepareScreen(Data(s.utf8), resolver: resolver)
        return try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: data)
    }

    private func childIds(_ c: DSL.Model.Component.`Any`) -> [String] {
        c.asEntity()?.content.children.map(\.id) ?? []
    }

    private func labelText(_ c: DSL.Model.Component.`Any`) -> String? {
        guard let entity = c.asEntity(), let content = entity.content as? DSL.Model.Component.Label.C else { return nil }
        return String(describing: content.properties.text)
    }

    // MARK: - Merge semantics

    func testObjectsMergeRecursivelyArraysAndScalarsReplace() throws {
        let base = try object(#"{ "a": { "b": 1, "c": [1, 2, 3], "d": { "e": "x", "f": "y" } }, "g": true }"#)
        let override = try object(#"{ "a": { "c": [9], "d": { "f": "z" } }, "g": { "now": "object" } }"#)
        XCTAssertEqual(
            JSONValue.object(PlatformOverrides.merge(base, override)),
            try json(#"{ "a": { "b": 1, "c": [9], "d": { "e": "x", "f": "z" } }, "g": { "now": "object" } }"#))
    }

    func testIosOverrideAppliesOnlyOnIos() throws {
        let node = try object("""
        { "id": "t", "type": "label", "content": {
            "properties": { "text": "base", "numberOfLines": 2 },
            "ios": { "properties": { "text": "apple" } },
            "android": { "properties": { "text": "robot" } } } }
        """)
        let ios = try XCTUnwrap(PlatformOverrides.apply(node, platform: .ios))
        let android = try XCTUnwrap(PlatformOverrides.apply(node, platform: .android))
        XCTAssertEqual(ios["content"], try json(#"{ "properties": { "text": "apple", "numberOfLines": 2 } }"#))
        XCTAssertEqual(android["content"], try json(#"{ "properties": { "text": "robot", "numberOfLines": 2 } }"#))
    }

    func testNodeLevelOverrideMergesIntoTheNode() throws {
        let node = try object("""
        { "id": "v", "type": "view",
          "ios": { "content": { "layout": { "height": 56 } } },
          "content": { "layout": { "width": 10, "height": 44 } } }
        """)
        let applied = try XCTUnwrap(PlatformOverrides.apply(node))
        XCTAssertEqual(applied["content"], try json(#"{ "layout": { "width": 10, "height": 56 } }"#))
    }

    func testPlatformKeysAreDroppedAfterMerging() throws {
        let node = try object(#"{ "type": "view", "ios": { "x": 1 }, "android": { "y": 2 }, "content": { "ios": { "z": 3 }, "android": {} } }"#)
        let applied = try XCTUnwrap(PlatformOverrides.apply(node, platform: .ios))
        XCTAssertNil(applied["ios"]); XCTAssertNil(applied["android"]); XCTAssertNil(applied["y"])
        XCTAssertEqual(applied["x"], .number(1))
        XCTAssertEqual(applied["content"], try json(#"{ "z": 3 }"#))
    }

    func testUnknownKeysInAnOverrideAreKeptForTheDecoder() throws {
        // An override may add keys the engine doesn't know; they merge like any other
        // and the decoders ignore them as before.
        let screen = try decodeScreen("""
        { "id": "s", "type": "screen", "content": {
            "ios": { "futureFlag": true, "properties": { "somethingNew": 1 } },
            "children": [ { "id": "a", "type": "view", "content": {} } ] } }
        """)
        XCTAssertEqual(childIds(screen), ["a"])
        let applied = try XCTUnwrap(PlatformOverrides.apply(try object(#"{ "type": "view", "content": { "ios": { "futureFlag": true } } }"#)))
        XCTAssertEqual(applied["content"], try json(#"{ "futureFlag": true }"#))
    }

    func testNonObjectOverrideOnlyStripsTheKeys() throws {
        let applied = try XCTUnwrap(PlatformOverrides.apply(try object(#"{ "type": "view", "ios": 5, "android": "x", "content": { "ios": [1] } }"#)))
        XCTAssertEqual(JSONValue.object(applied), try json(#"{ "type": "view", "content": {} }"#))
    }

    func testMergeStopsAtTheDepthLimit() throws {
        func nested(_ depth: Int, leaf: JSONValue) -> [String: JSONValue] {
            var o: [String: JSONValue] = ["leaf": leaf]
            for _ in 0..<depth { o = ["child": .object(o)] }
            return o
        }
        let depth = EngineLimits.maxDeepMergeDepth + 100
        let merged = PlatformOverrides.merge(nested(depth, leaf: .string("base")), nested(depth, leaf: .string("override")))
        XCTAssertNotNil(merged["child"], "deep merges terminate and keep the base past the limit")
        // Within the limit the override wins.
        let shallow = PlatformOverrides.merge(nested(3, leaf: .string("base")), nested(3, leaf: .string("override")))
        XCTAssertEqual(JSONValue.object(shallow), JSONValue.object(nested(3, leaf: .string("override"))))
    }

    // MARK: - Nested content and decoding

    func testNestedChildrenGetTheirOverridesOnDecode() throws {
        let screen = try decodeScreen("""
        { "id": "s", "type": "screen", "content": { "children": [
            { "id": "wrap", "type": "view", "content": { "children": [
                { "id": "t", "type": "label", "content": {
                    "properties": { "text": "base" },
                    "ios": { "properties": { "text": "apple" } },
                    "android": { "properties": { "text": "robot" } } } } ] } } ] } }
        """)
        let wrap = try XCTUnwrap(screen.asEntity()?.content.children.first)
        let label = try XCTUnwrap(wrap.asEntity()?.content.children.first)
        XCTAssertEqual(label.id, "t")
        XCTAssertTrue(labelText(label)?.contains("apple") == true, labelText(label) ?? "nil")
    }

    func testChildrenOverrideReplacesTheArray() throws {
        let screen = try decodeScreen("""
        { "id": "root", "type": "screen", "content": {
            "children": [ { "id": "a", "type": "view", "content": {} }, { "id": "b", "type": "view", "content": {} } ],
            "ios": { "children": [ { "id": "c", "type": "view", "content": {} } ] } } }
        """)
        XCTAssertEqual(childIds(screen), ["c"])
    }

    // MARK: - platforms

    func testChildrenNotListingIosAreDropped() throws {
        let screen = try decodeScreen("""
        { "id": "root", "type": "screen", "content": { "children": [
            { "id": "both", "type": "view", "content": {} },
            { "id": "iosOnly", "type": "view", "platforms": ["ios"], "content": {} },
            { "id": "androidOnly", "type": "view", "platforms": ["android"], "content": {} },
            { "id": "everywhere", "type": "view", "platforms": ["ios", "android"], "content": {} },
            { "id": "nowhere", "type": "view", "platforms": [], "content": {} } ] } }
        """)
        XCTAssertEqual(childIds(screen), ["both", "iosOnly", "everywhere"])
    }

    func testPlatformsThatIsNotAnArrayIsIgnored() throws {
        XCTAssertTrue(PlatformOverrides.isIncluded(try object(#"{ "type": "view", "platforms": "android" }"#)))
        XCTAssertFalse(PlatformOverrides.isIncluded(try object(#"{ "platforms": [] }"#)))
        XCTAssertFalse(PlatformOverrides.isIncluded(try object(#"{ "platforms": [1, "android"] }"#)))
    }

    func testConstraintToAnExcludedSiblingDoesNotCrash() throws {
        let data = try PlatformOverrides.resolveDocument(Data("""
        { "id": "root", "type": "view", "content": { "children": [
            { "id": "gone", "type": "view", "platforms": ["android"], "content": {} },
            { "id": "kept", "type": "view", "content": { "layout": { "constraints": [
                { "type": "top", "target": "gone", "attribute": "bottom" },
                { "type": "leading", "target": "superview" }, { "type": "width", "constant": 10 },
                { "type": "height", "constant": 10 } ] } } } ] } }
        """.utf8))
        let harness = RenderHarness()
        try harness.render(String(decoding: data, as: UTF8.self))
        XCTAssertNotNil(harness.viewModel("root.kept", as: CViewModel.self))
        XCTAssertNil(harness.viewModel("root.gone", as: CViewModel.self))
    }

    func testExcludedRootThrows() {
        XCTAssertThrowsError(try decodeScreen(#"{ "id": "s", "type": "screen", "platforms": ["android"], "content": {} }"#)) { error in
            XCTAssertTrue(error is PlatformOverrides.Excluded)
        }
        XCTAssertNoThrow(try decodeScreen(#"{ "id": "s", "type": "screen", "platforms": ["ios"], "content": {} }"#))
    }

    func testExcludedSingleSlotsAreRemoved() throws {
        let resolved = try XCTUnwrap(PlatformOverrides.resolveComponent(try json("""
        { "id": "list", "type": "collection", "content": {
            "template": { "type": "label", "platforms": ["android"], "content": {} },
            "emptyState": { "id": "e", "type": "label", "platforms": ["android"], "content": {} },
            "loadingState": { "id": "l", "type": "label", "content": { "ios": { "properties": { "text": "i" } } } },
            "templates": { "ref": "Card", "a": { "id": "ta", "type": "view", "content": {} }, "b": { "id": "tb", "type": "view", "platforms": ["android"], "content": {} } },
            "sectionHeaders": { "a": { "id": "ha", "type": "label", "content": {} }, "b": { "id": "hb", "type": "label", "platforms": ["android"], "content": {} } },
            "navigationBar": { "title": "T", "titleView": { "id": "tv", "type": "view", "platforms": ["android"], "content": {} } },
            "contextMenu": { "preview": { "component": { "id": "p", "type": "view", "platforms": ["android"], "content": {} } }, "items": [] },
            "fallback": { "id": "f", "type": "view", "platforms": ["android"], "content": {} } } }
        """)))
        guard case .object(let root) = resolved, case .object(let content)? = root["content"] else { return XCTFail() }
        XCTAssertNil(content["template"]); XCTAssertNil(content["emptyState"]); XCTAssertNil(content["fallback"])
        XCTAssertEqual(content["loadingState"], try json(#"{ "id": "l", "type": "label", "content": { "properties": { "text": "i" } } }"#))
        XCTAssertEqual(content["templates"], try json(#"{ "ref": "Card", "a": { "id": "ta", "type": "view", "content": {} } }"#))
        XCTAssertEqual(content["sectionHeaders"], try json(#"{ "a": { "id": "ha", "type": "label", "content": {} } }"#))
        XCTAssertEqual(content["navigationBar"], try json(#"{ "title": "T" }"#))
        XCTAssertEqual(content["contextMenu"], try json(#"{ "items": [] }"#))
    }

    func testBottomBarAndTableRows() throws {
        let resolved = try XCTUnwrap(PlatformOverrides.resolveComponent(try json("""
        { "id": "s", "type": "screen", "content": {
            "bottomBar": { "component": { "id": "bar", "type": "view", "platforms": ["android"], "content": {} } },
            "children": [ { "id": "table", "type": "tableView", "content": { "sections": [ { "id": "s1", "rows": [
                { "id": "r1", "children": [ { "id": "x", "type": "view", "platforms": ["android"], "content": {} },
                                            { "id": "y", "type": "view", "content": { "ios": { "layout": { "height": 1 } } } } ] } ] } ] } } ] } }
        """)))
        guard case .object(let root) = resolved, case .object(let content)? = root["content"] else { return XCTFail() }
        XCTAssertNil(content["bottomBar"])
        XCTAssertEqual(content["children"], try json("""
        [ { "id": "table", "type": "tableView", "content": { "sections": [ { "id": "s1", "rows": [
            { "id": "r1", "children": [ { "id": "y", "type": "view", "content": { "layout": { "height": 1 } } } ] } ] } ] } } ]
        """))
    }

    // MARK: - Templates

    func testTemplatesApplyOverridesAtLoad() throws {
        let card = try JSONDecoder().decode(DSL.Model.Component.Template.self, from: Data("""
        { "id": "Card", "type": "view", "content": {
            "properties": { "cornerRadius": 8 }, "ios": { "properties": { "cornerRadius": 12 } },
            "children": [ { "id": "a", "type": "view", "platforms": ["android"], "content": {} } ] } }
        """.utf8))
        XCTAssertEqual(card.rawContent?.value, try json(#"{ "properties": { "cornerRadius": 12 }, "children": [] }"#))
        XCTAssertThrowsError(try JSONDecoder().decode(DSL.Model.Component.Template.self, from: Data(
            #"{ "id": "DroidCard", "type": "view", "platforms": ["android"], "content": {} }"#.utf8))) { error in
            XCTAssertTrue(error is PlatformOverrides.Excluded)
        }
    }

    func testInstanceOverridesApplyAfterTemplateExpansion() throws {
        let template = try JSONDecoder().decode(DSL.Model.Component.Template.self, from: Data("""
        { "id": "Row", "type": "view", "content": { "children": [ { "id": "inner", "type": "view", "content": {} } ] } }
        """.utf8))
        var resolver = TemplateResolver(templates: [template])
        resolver.resolveAllTemplates()
        let screen = try decodeScreen("""
        { "id": "s", "type": "screen", "content": { "children": [
            { "id": "row1", "templateId": "Row", "content": { "ios": { "children": [] } } },
            { "id": "row2", "templateId": "Row", "platforms": ["android"] } ] } }
        """, resolver: resolver)
        XCTAssertEqual(childIds(screen), ["row1"])
        XCTAssertEqual(childIds(try XCTUnwrap(screen.asEntity()?.content.children.first)), [])
    }

    // MARK: - Documents without overrides

    func testDocumentWithoutOverridesIsReturnedAsIs() throws {
        let data = Data(#"{ "id": "s", "type": "screen", "content": { "children": [] } }"#.utf8)
        XCTAssertFalse(PlatformOverrides.mayHaveOverrides(data))
        XCTAssertEqual(try PlatformOverrides.resolveDocument(data), data)
        let notJSON = Data("{ \"ios\": ".utf8)
        XCTAssertEqual(try PlatformOverrides.resolveDocument(notJSON), notJSON)
    }

    func testVariableValuesNamedIosAreNotTouched() throws {
        // Only component nodes and their content carry overrides: data with
        // `ios` / `platforms` keys inside variables stays as written.
        let screen = try json("""
        { "id": "s", "type": "screen", "content": {
            "variables": { "links": { "type": "object", "initialValue": { "ios": "a", "android": "b", "platforms": ["web"] } } },
            "children": [] } }
        """)
        XCTAssertEqual(try PlatformOverrides.resolveDocument(screen), screen)
    }
}
