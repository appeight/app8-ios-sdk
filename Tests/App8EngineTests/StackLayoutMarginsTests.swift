//
//  StackLayoutMarginsTests.swift
//  App8EngineTests
//
//  stackView `style.layoutMargins`: arranged subviews inside the margins,
//  the stack's frame (and background) the full width.
//

import XCTest
@testable import App8Engine

@MainActor
final class StackLayoutMarginsTests: XCTestCase {

    private func view(_ id: String, in root: UIView) -> UIView? {
        if let c = root as? CView, c.layoutModeId == id { return c }
        for sub in root.subviews { if let v = view(id, in: sub) { return v } }
        return nil
    }

    private func frame(_ id: String, _ harness: RenderHarness) throws -> CGRect {
        let v = try XCTUnwrap(view(id, in: harness.superview), id)
        return v.convert(v.bounds, to: harness.superview)
    }

    func testMarginsInsetTheArrangedSubviews() throws {
        let harness = RenderHarness()
        try harness.render("""
        {
          "id": "root", "type": "view",
          "content": {
            "layout": { "width": 390, "height": 844 },
            "children": [
              { "id": "stack", "type": "stackView", "content": {
                  "properties": { "axis": "vertical", "spacing": 10, "backgroundColor": "#112233" },
                  "style": { "layoutMargins": { "top": 12, "leading": 16, "bottom": 8, "trailing": 16 } },
                  "layout": { "constraints": [
                    { "type": "top", "target": "superview", "constant": 100 },
                    { "type": "leading", "target": "superview", "constant": 0 },
                    { "type": "trailing", "target": "superview", "constant": 0 } ] },
                  "children": [
                    { "id": "a", "type": "view", "content": { "layout": { "height": 20 } } },
                    { "id": "hidden", "type": "view", "content": { "properties": { "isHidden": true }, "layout": { "height": 300 } } },
                    { "id": "b", "type": "view", "content": { "layout": { "height": 44 } } }
                  ] } },
              { "id": "sibling", "type": "view", "content": { "layout": { "constraints": [
                    { "type": "top", "target": "superview", "constant": 400 },
                    { "type": "leading", "target": "superview", "constant": 16 },
                    { "type": "trailing", "target": "superview", "constant": -16 },
                    { "type": "height", "constant": 20 } ] } } }
            ]
          }
        }
        """)
        harness.superview.layoutIfNeeded()
        let stack = try XCTUnwrap(harness.find(UIStackView.self))
        XCTAssertEqual(stack.convert(stack.bounds, to: harness.superview), CGRect(x: 0, y: 100, width: 390, height: 12 + 20 + 10 + 44 + 8))
        XCTAssertEqual(try frame("a", harness), CGRect(x: 16, y: 112, width: 358, height: 20))
        XCTAssertEqual(try frame("b", harness), CGRect(x: 16, y: 142, width: 358, height: 44))
        XCTAssertEqual(try frame("a", harness).minX, try frame("sibling", harness).minX, "lines up with a 16 pt inset sibling")
    }

    func testNoMarginsKeepsTheOldLayout() throws {
        let harness = RenderHarness()
        try harness.render("""
        {
          "id": "root", "type": "view",
          "content": {
            "layout": { "width": 390, "height": 844 },
            "children": [
              { "id": "stack", "type": "stackView", "content": {
                  "properties": { "axis": "vertical" },
                  "layout": { "constraints": [
                    { "type": "top", "target": "superview", "constant": 100 },
                    { "type": "leading", "target": "superview", "constant": 0 },
                    { "type": "trailing", "target": "superview", "constant": 0 } ] },
                  "children": [ { "id": "a", "type": "view", "content": { "layout": { "height": 20 } } } ] } }
            ]
          }
        }
        """)
        harness.superview.layoutIfNeeded()
        XCTAssertEqual(try frame("a", harness), CGRect(x: 0, y: 100, width: 390, height: 20))
    }
}
