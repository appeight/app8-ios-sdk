//
//  LabelEllipsisTests.swift
//  App8EngineTests
//
//  A line-limited label ends its last line with an ellipsis, also when it has
//  a lineHeight (which needs an explicit paragraph style, whose own
//  lineBreakMode would otherwise win and wrap without an ellipsis).
//

import XCTest
@testable import App8Engine

@MainActor
final class LabelEllipsisTests: XCTestCase {

    private static let longText = "Discover our top-rated skincare solutions designed to target fine lines, wrinkles, and loss of firmness for smoother skin."

    private func render(_ textStyle: String) throws -> UILabel {
        let json = """
        {
          "type": "view", "id": "root",
          "content": {
            "layout": { "width": 180, "height": 300 },
            "children": [
              { "type": "label", "id": "body",
                "content": {
                  "properties": { "text": "\(Self.longText)" },
                  "style": { "text": \(textStyle) },
                  "layout": { "constraints": [
                    { "type": "top", "target": "superview" },
                    { "type": "leading", "target": "superview" },
                    { "type": "trailing", "target": "superview" } ] }
                } }
            ]
          }
        }
        """
        let harness = RenderHarness(size: CGSize(width: 180, height: 300), inWindow: false)
        try harness.render(json)
        harness.drain()
        return try XCTUnwrap(harness.find(UILabel.self))
    }

    private func paragraphMode(_ label: UILabel) -> NSLineBreakMode? {
        (label.attributedText?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.lineBreakMode
    }

    func testLineLimitedLabelWithLineHeightTruncatesTail() throws {
        let label = try render(#"{ "fontSize": 14, "numberOfLines": 3, "lineHeight": { "type": "multiplier", "value": 1.15 } }"#)
        XCTAssertEqual(label.numberOfLines, 3)
        XCTAssertEqual(paragraphMode(label), .byTruncatingTail)
    }

    func testExplicitLineBreakModeIsKept() throws {
        let label = try render(#"{ "fontSize": 14, "numberOfLines": 3, "lineBreakMode": "truncateHead", "lineHeight": { "type": "multiplier", "value": 1.15 } }"#)
        XCTAssertEqual(paragraphMode(label), .byTruncatingHead)
    }

    func testUnlimitedLabelKeepsWordWrapping() throws {
        let label = try render(#"{ "fontSize": 14, "numberOfLines": 0, "lineHeight": { "type": "multiplier", "value": 1.15 } }"#)
        XCTAssertEqual(paragraphMode(label), .byWordWrapping)
    }

    func testSystemButtonWithOneLineTextTruncates() throws {
        let json = """
        {
          "type": "view", "id": "root",
          "content": {
            "layout": { "width": 100, "height": 40 },
            "children": [
              { "type": "button", "id": "added",
                "content": {
                  "properties": { "text": "12 IN BAG" },
                  "style": {
                    "text": { "fontSize": 14, "numberOfLines": 1 },
                    "system": { "variant": "plain" }
                  },
                  "layout": { "constraints": [
                    { "type": "top", "target": "superview" },
                    { "type": "leading", "target": "superview" },
                    { "type": "trailing", "target": "superview" },
                    { "type": "bottom", "target": "superview" } ] }
                } }
            ]
          }
        }
        """
        let harness = RenderHarness(size: CGSize(width: 100, height: 40), inWindow: false)
        try harness.render(json)
        harness.drain()
        let button = try XCTUnwrap(harness.find(UIButton.self))
        XCTAssertEqual(button.configuration?.titleLineBreakMode, .byTruncatingTail)
    }
}
