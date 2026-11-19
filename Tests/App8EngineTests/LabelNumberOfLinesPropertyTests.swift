//
//  LabelNumberOfLinesPropertyTests.swift
//  App8EngineTests
//
//  `properties.numberOfLines` caps a label's lines (0 = unlimited) and wins
//  over the text style's `numberOfLines`; the cap also limits the measured
//  height.
//

import XCTest
@testable import App8Engine

@MainActor
final class LabelNumberOfLinesPropertyTests: XCTestCase {

    private static let longText = "A long body text that needs several lines to fit inside a narrow column, so a line cap visibly shortens the label and ends it early."

    private func render(properties: String, textStyle: String?) throws -> UILabel {
        let style = textStyle.map { #", "style": { "text": \#($0) }"# } ?? ""
        let json = """
        {
          "type": "view", "id": "root",
          "content": {
            "layout": { "width": 160, "height": 600 },
            "children": [
              { "type": "label", "id": "body",
                "content": {
                  "properties": { "text": "\(Self.longText)"\(properties) }\(style),
                  "layout": { "constraints": [
                    { "type": "top", "target": "superview" },
                    { "type": "leading", "target": "superview" },
                    { "type": "trailing", "target": "superview" } ] }
                } }
            ]
          }
        }
        """
        let harness = RenderHarness(size: CGSize(width: 160, height: 600), inWindow: false)
        try harness.render(json)
        harness.drain()
        return try XCTUnwrap(harness.find(UILabel.self))
    }

    func testPropertyAppliesWithoutTextStyleLines() throws {
        let label = try render(properties: #", "numberOfLines": 2"#, textStyle: #"{ "fontSize": 14 }"#)
        XCTAssertEqual(label.numberOfLines, 2)
    }

    func testPropertyAppliesWithoutAnyTextStyle() throws {
        let label = try render(properties: #", "numberOfLines": 3"#, textStyle: nil)
        XCTAssertEqual(label.numberOfLines, 3)
    }

    func testPropertyWinsOverTextStyle() throws {
        let capped = try render(properties: #", "numberOfLines": 2"#, textStyle: #"{ "fontSize": 14, "numberOfLines": 0 }"#)
        XCTAssertEqual(capped.numberOfLines, 2)
        let unlimited = try render(properties: #", "numberOfLines": 0"#, textStyle: #"{ "fontSize": 14, "numberOfLines": 1 }"#)
        XCTAssertEqual(unlimited.numberOfLines, 0)
    }

    func testTextStyleUsedWhenPropertyAbsent() throws {
        let label = try render(properties: "", textStyle: #"{ "fontSize": 14, "numberOfLines": 4 }"#)
        XCTAssertEqual(label.numberOfLines, 4)
    }

    func testCapLimitsMeasuredHeight() throws {
        let style = #"{ "fontSize": 14, "numberOfLines": 0 }"#
        let unlimited = try render(properties: "", textStyle: style)
        let capped = try render(properties: #", "numberOfLines": 2"#, textStyle: style)
        let lineHeight = UIFont.systemFont(ofSize: 14).lineHeight
        XCTAssertGreaterThan(unlimited.bounds.height, lineHeight * 3)
        XCTAssertLessThanOrEqual(capped.bounds.height, ceil(lineHeight * 2) + 1)
        XCTAssertGreaterThan(capped.bounds.height, lineHeight * 1.5)
    }

    func testLineHeightTruncatesTailWithPropertyCap() throws {
        let label = try render(
            properties: #", "numberOfLines": 2"#,
            textStyle: #"{ "fontSize": 14, "lineHeight": { "type": "multiplier", "value": 1.2 } }"#
        )
        let mode = (label.attributedText?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.lineBreakMode
        XCTAssertEqual(mode, .byTruncatingTail)
    }

    func testEffectiveNumberOfLinesPrecedence() {
        XCTAssertEqual(CLabelView.effectiveNumberOfLines(property: 2, style: 5), 2)
        XCTAssertEqual(CLabelView.effectiveNumberOfLines(property: nil, style: 5), 5)
        XCTAssertEqual(CLabelView.effectiveNumberOfLines(property: 0, style: 1), 0)
        XCTAssertEqual(CLabelView.effectiveNumberOfLines(property: -1, style: 1), 0)
        XCTAssertNil(CLabelView.effectiveNumberOfLines(property: nil, style: nil))
    }
}
