//
//  AdaptiveGlassTests.swift
//  App8EngineTests
//
//  styles.md, glassAppearance: glass follows the content behind it (auto) or
//  is pinned light / dark.
//

import XCTest
import UIKit
@testable import App8Engine

@MainActor
final class AdaptiveGlassTests: XCTestCase {

    func testDecoding() throws {
        func decode(_ json: String) throws -> DSL.Model.Style.GlassAppearance {
            try JSONDecoder().decode([DSL.Model.Style.GlassAppearance].self, from: Data("[\(json)]".utf8))[0]
        }
        XCTAssertEqual(try decode("\"light\""), .light)
        XCTAssertEqual(try decode("\"dark\""), .dark)
        XCTAssertEqual(try decode("\"auto\""), .auto)
        XCTAssertEqual(try decode("\"purple\""), .auto)
        XCTAssertEqual(DSL.Model.Style.GlassAppearance.dark.interfaceStyle, .dark)
        XCTAssertEqual(DSL.Model.Style.GlassAppearance.auto.interfaceStyle, .unspecified)
    }

    func testHysteresis() {
        let mid = (BackdropLuminance.darkBelow + BackdropLuminance.lightAbove) / 2
        XCTAssertTrue(BackdropLuminance.nextDark(current: nil, luminance: 0.02))
        XCTAssertFalse(BackdropLuminance.nextDark(current: nil, luminance: 0.8))
        XCTAssertTrue(BackdropLuminance.nextDark(current: true, luminance: mid))
        XCTAssertFalse(BackdropLuminance.nextDark(current: false, luminance: mid))
    }

    func testSamplesWhatIsBehindTheView() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.makeKeyAndVisible()
        let backdrop = UIView(frame: window.bounds)
        window.addSubview(backdrop)
        let glass = UIView(frame: CGRect(x: 50, y: 50, width: 200, height: 60))
        glass.backgroundColor = .white // left out of the sample
        window.addSubview(glass)
        backdrop.backgroundColor = .black
        XCTAssertEqual(BackdropLuminance.sample(behind: glass) ?? -1, 0, accuracy: 0.02)
        backdrop.backgroundColor = .white
        XCTAssertEqual(BackdropLuminance.sample(behind: glass) ?? -1, 1, accuracy: 0.02)
        XCTAssertFalse(glass.isHidden)
    }

    func testPinnedGlassOnIOS26() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("system glass is iOS 26") }
        let harness = RenderHarness(size: CGSize(width: 390, height: 200))
        try harness.render(#"""
        { "type": "view", "id": "root", "content": { "layout": { "width": 390, "height": 200 }, "children": [
          { "type": "view", "id": "pinned", "content": {
              "style": { "glassAppearance": "dark", "material": [ { "id": "g", "type": "visualEffect", "content": { "glass": "normal" } } ] },
              "layout": { "top": 0, "leading": 0, "width": 120, "height": 44 } } },
          { "type": "view", "id": "adaptive", "content": {
              "style": { "material": [ { "id": "g2", "type": "visualEffect", "content": { "glass": "normal" } } ] },
              "layout": { "top": 60, "leading": 0, "width": 120, "height": 44 } } }
        ] } }
        """#)
        harness.drain()
        func effects(_ v: UIView) -> [UIVisualEffectView] { v.subviews.flatMap { ($0 as? UIVisualEffectView).map { [$0] } ?? effects($0) } }
        let all = effects(harness.superview).sorted { $0.convert($0.bounds, to: nil).minY < $1.convert($1.bounds, to: nil).minY }
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].overrideUserInterfaceStyle, .dark)
        XCTAssertEqual(all[1].overrideUserInterfaceStyle, .unspecified)
        // Pinned dark: a dark tint on the system glass; adaptive: none.
        XCTAssertNotNil((all[0].effect as? UIGlassEffect)?.tintColor)
        XCTAssertNil((all[1].effect as? UIGlassEffect)?.tintColor)
    }
}
