//
//  UnderlineWidthTests.swift
//  App8EngineTests
//
//  `underline: true` draws a line exactly as wide as the text: from the
//  first glyph to the last one, without the letter spacing that follows the
//  last glyph. Measured on rendered pixels: the ink of the glyph rows against
//  the ink of the underline row.
//

import XCTest
@testable import App8Engine

@MainActor
final class UnderlineWidthTests: XCTestCase {

    private struct Measure { let text: ClosedRange<CGFloat>; let line: ClosedRange<CGFloat>; let label: UILabel }

    /// Capitals only: no descender crosses the underline, so the glyphs and
    /// the line are separate ink bands.
    private func measure(letterSpacing: Double, alignment: String = "left", lineHeight: Int? = nil) throws -> Measure {
        let lh = lineHeight.map { #", "lineHeight": { "type": "fixed", "value": \#($0) }"# } ?? ""
        let json = ##"""
        {
          "type": "view", "id": "box",
          "content": {
            "layout": { "width": 240, "height": 80 },
            "children": [
              { "type": "label", "id": "link",
                "content": {
                  "properties": { "text": "HIDE THE EDIT", "numberOfLines": 1 },
                  "style": { "text": { "fontSize": 16, "color": "#000000", "underline": true, "alignment": "\##(alignment)", "letterSpacing": \##(letterSpacing)\##(lh) } },
                  "layout": { "constraints": [ { "type": "centerX", "target": "superview" }, { "type": "centerY", "target": "superview" } ] }
                } }
            ]
          }
        }
        """##
        let harness = RenderHarness(size: CGSize(width: 240, height: 80), inWindow: false)
        try harness.render(json)
        for _ in 0..<2 {
            harness.drain(0.1)
            harness.superview.setNeedsLayout()
            harness.superview.layoutIfNeeded()
        }
        let rows = InkRows(of: harness.superview, scale: 3)
        XCTAssertEqual(rows.bands.count, 2, "glyphs and underline are two ink bands")
        let glyphs = try XCTUnwrap(rows.bands.first), underline = try XCTUnwrap(rows.bands.last)
        let text = try XCTUnwrap(InkRows(of: harness.superview, scale: 3, in: CGRect(x: 0, y: glyphs.lowerBound, width: 240, height: glyphs.upperBound - glyphs.lowerBound)).columns)
        let line = try XCTUnwrap(InkRows(of: harness.superview, scale: 3, in: CGRect(x: 0, y: underline.lowerBound, width: 240, height: underline.upperBound - underline.lowerBound)).columns)
        return Measure(text: text, line: line, label: try XCTUnwrap(harness.find(UILabel.self)))
    }

    private func width(_ range: ClosedRange<CGFloat>) -> CGFloat { range.upperBound - range.lowerBound }

    func testUnderlineIsAsWideAsTheText() throws {
        for spacing in [0.0, 1.5, 4.0] {
            let m = try measure(letterSpacing: spacing)
            print(String(format: "[underline] letterSpacing %.1f: text ink %.2f pt, underline %.2f pt, left %+.2f, right %+.2f, label %.2f",
                         spacing, width(m.text), width(m.line), m.line.lowerBound - m.text.lowerBound, m.line.upperBound - m.text.upperBound, m.label.bounds.width))
            // The line starts and ends at the glyphs' edges, give or take their side bearings (about 1 pt at 16 pt).
            XCTAssertEqual(m.line.lowerBound, m.text.lowerBound, accuracy: 1.5, "letterSpacing \(spacing): left edge")
            XCTAssertEqual(m.line.upperBound, m.text.upperBound, accuracy: 1.5, "letterSpacing \(spacing): right edge")
        }
    }

    /// The label is as wide as its text, so a centred or trailing label does
    /// not sit off by the last letter's spacing.
    func testTrailingLetterSpacingIsNotPartOfTheLabel() throws {
        let m = try measure(letterSpacing: 4)
        // Centred in a 240 pt box: the ink is centred too.
        XCTAssertEqual((m.text.lowerBound + m.text.upperBound) / 2, 120, accuracy: 1.0)
    }

    func testUnderlineWithAFixedLineHeight() throws {
        let m = try measure(letterSpacing: 1.5, lineHeight: 26)
        XCTAssertEqual(m.line.upperBound, m.text.upperBound, accuracy: 1.5)
        XCTAssertEqual(m.line.lowerBound, m.text.lowerBound, accuracy: 1.5)
    }
}
