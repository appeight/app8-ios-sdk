//
//  LabelLineBreakStrategyTests.swift
//  App8EngineTests
//
//  Labels avoid a lone word on the last line (orphan) with .pushOut, as
//  system text does. An explicit paragraph style (any lineHeight) resets the
//  strategy to none, so the engine sets it on every paragraph style it builds.
//

import XCTest
@testable import App8Engine

@MainActor
final class LabelLineBreakStrategyTests: XCTestCase {

    private func labelJSON(textStyle: String) -> String {
        """
        {
          "type": "view", "id": "root",
          "content": {
            "layout": { "width": 240, "height": 200 },
            "children": [
              { "type": "label", "id": "title",
                "content": {
                  "properties": { "text": "You're on the Nice List" },
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
    }

    private static func firstLabel(in view: UIView) -> UILabel? {
        if let l = view as? UILabel { return l }
        for sub in view.subviews { if let l = firstLabel(in: sub) { return l } }
        return nil
    }

    private func assertPushOut(_ textStyle: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let harness = RenderHarness(size: CGSize(width: 240, height: 200), inWindow: false)
        try harness.render(labelJSON(textStyle: textStyle))
        harness.drain()
        let label = try XCTUnwrap(Self.firstLabel(in: harness.superview), file: file, line: line)
        XCTAssertTrue(label.lineBreakStrategy.contains(.pushOut), "label strategy", file: file, line: line)
        let text = try XCTUnwrap(label.attributedText, file: file, line: line)
        if let style = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            XCTAssertTrue(style.lineBreakStrategy.contains(.pushOut), "paragraph style strategy", file: file, line: line)
        }
    }

    func testPlainLabelUsesPushOut() throws {
        try assertPushOut(#"{ "fontSize": 30, "numberOfLines": 0 }"#)
    }

    func testLabelWithLineHeightKeepsPushOut() throws {
        try assertPushOut(#"{ "fontSize": 30, "numberOfLines": 0, "lineHeight": { "type": "multiplier", "value": 1.05 } }"#)
        try assertPushOut(#"{ "fontSize": 30, "numberOfLines": 0, "lineHeight": { "type": "fixed", "value": 34 } }"#)
    }
}
