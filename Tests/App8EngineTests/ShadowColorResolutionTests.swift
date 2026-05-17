//
//  ShadowColorResolutionTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

final class ShadowColorResolutionTests: XCTestCase {

    func testShadowResolvesColorReference() throws {
        // A primitive color and a shadow that references it.
        let stylesJSON = """
        [
            { "id": "shadowGray", "type": "color", "content": "#444444" },
            {
                "id": "testShadow",
                "type": "shadow",
                "content": {
                    "layers": [{
                        "isHollow": true,
                        "color": { "light": { "id": "shadowGray" }, "dark": { "id": "shadowGray" } },
                        "radius": 12,
                        "offset": { "x": 0, "y": 6 },
                        "opacity": 0.2
                    }]
                }
            }
        ]
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        var styles = try decoder.decode([DSL.Model.Style.`Any`].self, from: stylesJSON)

        var styleDict: [String: DSL.Model.Style.`Any`] = [:]
        for style in styles {
            styleDict[style.id] = style
        }

        // Resolve style pointers (multi-pass like App8.swift does).
        var madeProgress = true
        while madeProgress {
            madeProgress = false
            for i in 0..<styles.count {
                let wasResolved = styles[i].isResolved()
                var styleCopy = styles[i]
                styleCopy.resolveStylePointers { id in
                    styleDict[id]?.asEntity()
                }
                styles[i] = styleCopy
                styleDict[styleCopy.id] = styleCopy
                if !wasResolved && styleCopy.isResolved() {
                    madeProgress = true
                }
            }
        }

        guard let shadowStyle = styles.first(where: { $0.id == "testShadow" }) else {
            XCTFail("Shadow style not found")
            return
        }

        guard let shadowEntity = shadowStyle.asEntity() as? DSL.Model.Style.Shadow.Entity else {
            XCTFail("Could not cast to Shadow.Entity")
            return
        }

        let shadow = shadowEntity.content
        XCTAssertEqual(shadow.layers.count, 1, "Expected 1 shadow layer")

        let layer = shadow.layers[0]
        XCTAssertTrue(layer.color.isResolved(), "Shadow color should be resolved")

        // Value is stored without the # prefix.
        let lightHex = layer.color.light?.value
        XCTAssertEqual(lightHex, "444444", "Expected 444444, got \(lightHex ?? "nil")")
    }

    func testShadowWorksWithDirectHexColor() throws {
        // A shadow with a direct hex color (no reference).
        let stylesJSON = """
        [
            {
                "id": "directShadow",
                "type": "shadow",
                "content": {
                    "layers": [{
                        "isHollow": true,
                        "color": "#000000",
                        "radius": 10,
                        "offset": { "x": 0, "y": 4 },
                        "opacity": 0.1
                    }]
                }
            }
        ]
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let styles = try decoder.decode([DSL.Model.Style.`Any`].self, from: stylesJSON)

        guard let shadowStyle = styles.first(where: { $0.id == "directShadow" }) else {
            XCTFail("Shadow style not found")
            return
        }

        guard let shadowEntity = shadowStyle.asEntity() as? DSL.Model.Style.Shadow.Entity else {
            XCTFail("Could not cast to Shadow.Entity")
            return
        }

        let shadow = shadowEntity.content
        XCTAssertEqual(shadow.layers.count, 1, "Expected 1 shadow layer")

        let layer = shadow.layers[0]
        XCTAssertTrue(layer.color.isResolved(), "Direct hex color should be resolved")

        // value is stored without # prefix
        let lightHex = layer.color.light?.value
        XCTAssertEqual(lightHex, "000000", "Expected 000000, got \(lightHex ?? "nil")")
    }
}
