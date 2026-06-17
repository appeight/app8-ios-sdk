//
//  SystemButtonStyleTests.swift
//  App8EngineTests
//

import UIKit
import XCTest
@testable import App8Engine

/// Tests for `DSL.Model.Style.SystemButton` — the native `UIButton.Configuration`
/// styling block exposed via `button` → `style.system`.
@MainActor
final class SystemButtonStyleTests: XCTestCase {

    private func decode(_ json: String) throws -> DSL.Model.Style.SystemButton {
        try JSONDecoder().decode(DSL.Model.Style.SystemButton.self, from: Data(json.utf8))
    }

    // MARK: - Decoding

    func testFullConfigurationDecodes() throws {
        let system = try decode("""
        {
            "variant": "glass",
            "cornerStyle": "capsule",
            "size": "large",
            "role": "primary",
            "tint": "#007AFF",
            "foreground": "#FFFFFF",
            "image": { "type": "symbol", "name": "star.fill" },
            "imagePlacement": "trailing",
            "imagePadding": 8,
            "subtitle": "Tap to continue",
            "showsActivityIndicator": "{{loading}}"
        }
        """)

        XCTAssertEqual(system.variant, .glass)
        XCTAssertEqual(system.cornerStyle, .capsule)
        XCTAssertEqual(system.size, .large)
        XCTAssertEqual(system.role, .primary)
        XCTAssertEqual(system.tint?.light?.value, "007AFF")
        XCTAssertEqual(system.foreground?.light?.value, "FFFFFF")
        XCTAssertEqual(system.image?.type, .symbol)
        XCTAssertEqual(system.image?.name, "star.fill")
        XCTAssertEqual(system.imagePlacement, .trailing)
        XCTAssertEqual(system.imagePadding, 8)
        XCTAssertEqual(system.subtitle, "Tap to continue")
        XCTAssertEqual(system.showsActivityIndicator, "{{loading}}")
    }

    func testEmptyDecodesAndIsResolved() throws {
        let system = try decode("{}")
        XCTAssertNil(system.variant)
        XCTAssertNil(system.tint)
        XCTAssertTrue(system.isResolved())
    }

    func testUnknownEnumDegradesToDefault() throws {
        // SafeEnumCodable: unknown raw values fall back rather than failing the decode.
        let system = try decode(#"{ "variant": "neonHologram", "cornerStyle": "warp" }"#)
        XCTAssertEqual(system.variant, .filled)   // Variant.unknownCase
        XCTAssertEqual(system.cornerStyle, .dynamic) // CornerStyle.unknownCase
    }

    // MARK: - makeConfiguration

    func testMakeConfigurationMapsCornerSizeAndColors() throws {
        let system = try decode("""
        { "variant": "filled", "cornerStyle": "capsule", "size": "large", "tint": "#FF0000", "foreground": "#00FF00", "imagePadding": 12 }
        """)
        let config = system.makeConfiguration()

        XCTAssertEqual(config.cornerStyle, .capsule)
        XCTAssertEqual(config.buttonSize, .large)
        XCTAssertEqual(config.baseBackgroundColor, system.tint?.ui)
        XCTAssertEqual(config.baseForegroundColor, system.foreground?.ui)
        XCTAssertEqual(config.imagePadding, 12)
    }

    func testGlassVariantBuildsAConfiguration() throws {
        // On iOS 26 this is `.glass()`; below 26 it degrades to `.filled()`. Either
        // way `makeConfiguration` must produce a usable configuration without crashing.
        let system = try decode(#"{ "variant": "glass", "cornerStyle": "capsule" }"#)
        let config = system.makeConfiguration()
        XCTAssertEqual(config.cornerStyle, .capsule)
    }

    // MARK: - Pointer resolution (reusable named configs)

    func testSystemButtonResolvesTintColorPointer() throws {
        let resolver: (String) -> (any DSL.Model.Style.Entity)? = {
            let data = Data("""
            [ { "id": "brand", "type": "color", "content": "#123456" } ]
            """.utf8)
            let styles = try! JSONDecoder().decode([DSL.Model.Style.`Any`].self, from: data)
            var dict: [String: DSL.Model.Style.`Any`] = [:]
            for s in styles { dict[s.id] = s }
            return { dict[$0]?.asEntity() }
        }()

        var system = try decode(#"{ "variant": "filled", "tint": { "id": "brand", "type": "color" } }"#)
        XCTAssertNil(system.tint, "pointer is unresolved before resolution")
        XCTAssertFalse(system.isResolved())

        system.resolveStylePointers(resolver: resolver)

        XCTAssertEqual(system.tint?.light?.value, "123456")
        XCTAssertTrue(system.isResolved())
    }
}
