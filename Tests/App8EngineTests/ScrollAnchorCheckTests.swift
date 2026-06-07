//
//  ScrollAnchorCheckTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

final class ScrollAnchorCheckTests: XCTestCase {

    private func findings(_ json: String) -> [App8.ValidationWarning] {
        ScrollAnchorCheck.findings(
            screenData: json.data(using: .utf8)!,
            screenId: "test-screen"
        ).warnings
    }

    /// A scrollView with one child whose `bottom`/`trailing` may or may not pin superview.
    private func scrollViewJSON(direction: String?, childConstraintType: String?, childTarget: String = "superview", autoScroll: Bool = false) -> String {
        let dirProp = direction.map { "\"direction\": \"\($0)\"," } ?? ""
        let autoProp = autoScroll ? "\"autoScroll\": true," : ""
        let constraints = childConstraintType.map {
            "\"constraints\": [{ \"type\": \"\($0)\", \"target\": \"\(childTarget)\" }]"
        } ?? "\"constraints\": []"
        return """
        {
            "type": "screen", "id": "s",
            "content": {
                "children": [{
                    "type": "scrollView", "id": "sv",
                    "content": {
                        "properties": { \(autoProp)\(dirProp) "x": 0 },
                        "children": [{
                            "type": "view", "id": "inner",
                            "content": { "layout": { \(constraints) } }
                        }]
                    }
                }]
            }
        }
        """
    }

    // MARK: - SCL001 fires

    func testSCL001_firesWhenVerticalContentNotPinned() {
        let w = findings(scrollViewJSON(direction: "vertical", childConstraintType: "top"))
        XCTAssertEqual(w.map(\.code), ["SCL001"], "Vertical content not pinning bottom should warn")
        XCTAssertEqual(w.first?.context?["scrollViewId"], "sv")
        XCTAssertEqual(w.first?.context?["direction"], "vertical")
    }

    func testSCL001_firesForHorizontalWhenTrailingNotPinned() {
        let w = findings(scrollViewJSON(direction: "horizontal", childConstraintType: "leading"))
        XCTAssertEqual(w.map(\.code), ["SCL001"])
        XCTAssertEqual(w.first?.context?["direction"], "horizontal")
    }

    func testSCL001_defaultsToVerticalWhenDirectionOmitted() {
        let w = findings(scrollViewJSON(direction: nil, childConstraintType: "top"))
        XCTAssertEqual(w.map(\.code), ["SCL001"])
        XCTAssertEqual(w.first?.context?["direction"], "vertical")
    }

    // MARK: - No fire

    func testNoFire_whenVerticalContentPinsBottom() {
        let w = findings(scrollViewJSON(direction: "vertical", childConstraintType: "bottom"))
        XCTAssertTrue(w.isEmpty, "bottom-pinned content is correct: \(w.map(\.code))")
    }

    func testNoFire_whenHorizontalContentPinsTrailing() {
        let w = findings(scrollViewJSON(direction: "horizontal", childConstraintType: "trailing"))
        XCTAssertTrue(w.isEmpty, "trailing-pinned content is correct: \(w.map(\.code))")
    }

    func testNoFire_whenBottomConstraintTargetsNonSuperview() {
        // Pinning bottom to a sibling, not superview, does not anchor the content.
        let w = findings(scrollViewJSON(direction: "vertical", childConstraintType: "bottom", childTarget: "sibling"))
        XCTAssertEqual(w.map(\.code), ["SCL001"], "bottom→non-superview shouldn't count as anchored")
    }

    func testNoFire_whenAutoScroll() {
        let w = findings(scrollViewJSON(direction: "horizontal", childConstraintType: "leading", autoScroll: true))
        XCTAssertTrue(w.isEmpty, "autoScroll views are engine-sized — skipped: \(w.map(\.code))")
    }

    func testNoFire_whenNoChildren() {
        let w = findings("""
        {
            "type": "screen", "id": "s",
            "content": {
                "children": [{
                    "type": "scrollView", "id": "sv",
                    "content": { "properties": {}, "children": [] }
                }]
            }
        }
        """)
        XCTAssertTrue(w.isEmpty, "Empty scrollView has nothing to anchor")
    }

    func testNoFire_whenNotAScrollView() {
        let w = findings("""
        {
            "type": "screen", "id": "s",
            "content": {
                "children": [{
                    "type": "view", "id": "v",
                    "content": { "children": [{ "type": "label", "id": "l", "content": {} }] }
                }]
            }
        }
        """)
        XCTAssertTrue(w.isEmpty)
    }

    // MARK: - Traversal

    func testNestedScrollViewIsChecked() {
        let w = findings("""
        {
            "type": "screen", "id": "s",
            "content": {
                "children": [{
                    "type": "view", "id": "outer",
                    "content": {
                        "children": [{
                            "type": "scrollView", "id": "nested",
                            "content": {
                                "properties": { "direction": "vertical" },
                                "children": [{
                                    "type": "view", "id": "inner",
                                    "content": { "layout": { "constraints": [{ "type": "top", "target": "superview" }] } }
                                }]
                            }
                        }]
                    }
                }]
            }
        }
        """)
        XCTAssertEqual(w.map(\.code), ["SCL001"])
        XCTAssertEqual(w.first?.context?["scrollViewId"], "nested")
    }

    func testAnchoredAmongMultipleChildren() {
        // Last child pins bottom even though earlier ones don't — that's the valid pattern.
        let w = findings("""
        {
            "type": "screen", "id": "s",
            "content": {
                "children": [{
                    "type": "scrollView", "id": "sv",
                    "content": {
                        "properties": { "direction": "vertical" },
                        "children": [
                            { "type": "view", "id": "a", "content": { "layout": { "constraints": [{ "type": "top", "target": "superview" }] } } },
                            { "type": "view", "id": "b", "content": { "layout": { "constraints": [{ "type": "bottom", "target": "superview" }] } } }
                        ]
                    }
                }]
            }
        }
        """)
        XCTAssertTrue(w.isEmpty, "One child pinning bottom anchors the content: \(w.map(\.code))")
    }

    func testMalformedJSON_returnsEmpty() {
        let w = ScrollAnchorCheck.findings(screenData: Data("nope".utf8), screenId: nil).warnings
        XCTAssertTrue(w.isEmpty)
    }
}
