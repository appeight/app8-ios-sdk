import XCTest
import UIKit
@testable import App8Engine

/// layout.md, Constraint Structure: `multiplier` on a position (edge or centre)
/// scales the target's position in the superview's bounds. `centerX` × 2 of the
/// superview is its trailing edge, × 0.5 a quarter of its width. Before 0.7.17
/// iOS dropped the multiplier on positions (only width and height used it), so
/// markers placed at fractions of a frame all sat in its middle.
@MainActor
final class PositionMultiplierTests: XCTestCase {

    private func marker(_ id: String, _ constraints: String) -> String {
        """
        { "id": "\(id)", "type": "view", "content": { "layout": { "constraints": [
            { "type": "width", "constant": 10 }, { "type": "height", "constant": 10 }, \(constraints)
        ] } } }
        """
    }

    /// A 300 × 200 frame placed at (40, 100): positions are relative to it, not to the window.
    private func render(_ children: [String]) throws -> RenderHarness {
        let h = RenderHarness(size: CGSize(width: 400, height: 600))
        try h.render("""
        { "id": "frame", "type": "view", "content": {
          "layout": { "constraints": [
            { "type": "leading", "target": "superview", "constant": 40 },
            { "type": "top", "target": "superview", "constant": 100 },
            { "type": "width", "constant": 300 }, { "type": "height", "constant": 200 } ] },
          "children": [ \(children.joined(separator: ",")) ] } }
        """)
        h.superview.layoutIfNeeded()
        return h
    }

    private func view(_ h: RenderHarness, _ id: String) throws -> UIView {
        func all(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(all) }
        return try XCTUnwrap(all(h.superview).first { $0.accessibilityIdentifier == id }, id)
    }

    func testCentreMultipliersPlaceAtFractionsOfTheSuperview() throws {
        let h = try render([
            marker("q", #"{ "type": "centerX", "target": "superview", "multiplier": 0.5 }, { "type": "centerY", "target": "superview", "multiplier": 0.5 }"#),
            marker("t", #"{ "type": "centerX", "target": "superview", "multiplier": 1.6 }, { "type": "centerY", "target": "superview", "multiplier": 1.2 }"#),
            marker("e", #"{ "type": "centerX", "target": "superview", "multiplier": 2 }, { "type": "centerY", "target": "superview", "multiplier": 2 }"#),
            marker("m", #"{ "type": "centerX", "target": "superview" }, { "type": "centerY", "target": "superview" }"#),
        ])
        let frame = try view(h, "frame")
        XCTAssertEqual(frame.frame, CGRect(x: 40, y: 100, width: 300, height: 200))
        // Centre at fx × 2 × (w / 2) = fx × w within the frame.
        XCTAssertEqual(try view(h, "q").center, CGPoint(x: 75, y: 50))
        XCTAssertEqual(try view(h, "t").center, CGPoint(x: 240, y: 120))
        XCTAssertEqual(try view(h, "e").center, CGPoint(x: 300, y: 200), "× 2: the bottom-trailing corner")
        XCTAssertEqual(try view(h, "m").center, CGPoint(x: 150, y: 100), "no multiplier: unchanged")
    }

    func testEdgeMultiplierAndConstant() throws {
        let h = try render([
            marker("l", #"{ "type": "leading", "target": "superview", "attribute": "trailing", "multiplier": 0.25, "constant": 5 }, { "type": "top", "target": "superview", "attribute": "bottom", "multiplier": 0.5 }"#),
        ])
        XCTAssertEqual(try view(h, "l").frame.origin, CGPoint(x: 80, y: 100))
    }

    func testSiblingTargetUsesTheSharedSuperviewsBounds() throws {
        let h = try render([
            marker("a", #"{ "type": "leading", "target": "superview", "constant": 100 }, { "type": "top", "target": "superview", "constant": 20 }"#),
            marker("b", #"{ "type": "centerX", "target": "sibling(a)", "multiplier": 2 }, { "type": "top", "target": "sibling(a)", "attribute": "bottom", "multiplier": 3 }"#),
        ])
        XCTAssertEqual(try view(h, "a").center.x, 105)
        XCTAssertEqual(try view(h, "b").center.x, 210)
        XCTAssertEqual(try view(h, "b").frame.minY, 90)
    }

    func testZeroMultiplierOnAPositionIsIgnoredNotATrap() throws {
        let h = try render([
            marker("z", #"{ "type": "centerX", "target": "superview", "multiplier": 0 }, { "type": "centerY", "target": "superview" }"#),
        ])
        XCTAssertEqual(try view(h, "z").center, CGPoint(x: 150, y: 100))
    }
}
