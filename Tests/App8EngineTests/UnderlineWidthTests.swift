//
//  UnderlineWidthTests.swift
//  App8EngineTests
//
//  `underline: true` draws a line exactly as wide as the text: from the
//  first glyph to the last one, without the letter spacing that follows the
//  last glyph. That holds for every line: wrapped lines, lines before a
//  newline and the line that ends in an ellipsis, and for negative letter
//  spacing. The label is as wide as its widest line measured the same way.
//  Measured on rendered pixels: the ink of the glyph rows against the ink of
//  the underline row.
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
                  "properties": { "text": "VIEW ALL ITEMS", "numberOfLines": 1 },
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

    // MARK: - Every line

    private struct Line { let text: ClosedRange<CGFloat>; let line: ClosedRange<CGFloat> }
    private struct Block { let lines: [Line]; let label: UILabel; let frame: CGRect }

    /// Renders `text` underlined in a box `boxWidth` wide and returns, per
    /// drawn line, the ink columns of its glyphs and of its underline.
    /// `fill`: the label spans the box (leading and trailing), else it is
    /// centred and hugs its text.
    private func block(_ text: String, letterSpacing: Double, boxWidth: Int, numberOfLines: Int = 0, alignment: String = "left", fill: Bool = false) throws -> Block {
        let horizontal = fill
            ? #"{ "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" }"#
            : #"{ "type": "centerX", "target": "superview" }"#
        let json = ##"""
        {
          "type": "view", "id": "box",
          "content": {
            "layout": { "width": \##(boxWidth), "height": 160 },
            "children": [
              { "type": "label", "id": "link",
                "content": {
                  "properties": { "text": "\##(text)", "numberOfLines": \##(numberOfLines) },
                  "style": { "text": { "fontSize": 16, "color": "#000000", "underline": true, "alignment": "\##(alignment)", "letterSpacing": \##(letterSpacing) } },
                  "layout": { "constraints": [ \##(horizontal), { "type": "centerY", "target": "superview" } ] }
                } }
            ]
          }
        }
        """##
        let harness = RenderHarness(size: CGSize(width: CGFloat(boxWidth), height: 160), inWindow: false)
        try harness.render(json)
        for _ in 0..<4 {
            harness.drain(0.1)
            harness.superview.setNeedsLayout()
            harness.superview.layoutIfNeeded()
        }
        let rows = InkRows(of: harness.superview, scale: 3)
        XCTAssertEqual(rows.bands.count % 2, 0, "glyphs and underline are two ink bands per line")
        var lines: [Line] = []
        for index in stride(from: 0, to: rows.bands.count - 1, by: 2) {
            lines.append(Line(text: try XCTUnwrap(InkRows.columns(of: rows.bands[index], in: harness.superview, scale: 3)),
                              line: try XCTUnwrap(InkRows.columns(of: rows.bands[index + 1], in: harness.superview, scale: 3))))
        }
        let label = try XCTUnwrap(harness.find(UILabel.self))
        return Block(lines: lines, label: label, frame: label.convert(label.bounds, to: harness.superview))
    }

    /// How far the underline runs past the last glyph's ink without letter
    /// spacing (the glyph's side bearing): what every line must match.
    private func naturalOverhang() throws -> CGFloat {
        let m = try measure(letterSpacing: 0)
        return m.line.upperBound - m.text.upperBound
    }

    /// The same for an ellipsis: UIKit's own cut of text without letter spacing.
    private func naturalEllipsisOverhang() throws -> CGFloat {
        let cut = try block("VIEW ALL ITEMS VIEW ALL ITEMS", letterSpacing: 0, boxWidth: 150, numberOfLines: 1, fill: true)
        let line = try XCTUnwrap(cut.lines.first)
        return line.line.upperBound - line.text.upperBound
    }

    private func assertLinesEndAtTheirLastGlyph(_ name: String, _ block: Block, lines count: Int, ellipsis: Bool = false, file: StaticString = #filePath, line: UInt = #line) throws {
        let natural = try ellipsis ? naturalEllipsisOverhang() : naturalOverhang()
        let overhangs = block.lines.map { $0.line.upperBound - $0.text.upperBound }
        print("[underline] \(name): " + overhangs.enumerated().map { String(format: "line %d right %+.2f", $0.offset + 1, $0.element) }.joined(separator: ", ")
              + String(format: " (natural %+.2f); label %.2f, widest ink %.2f", natural, block.frame.width, block.lines.map { width($0.text) }.max() ?? 0))
        XCTAssertEqual(block.lines.count, count, "\(name): lines", file: file, line: line)
        for (index, overhang) in overhangs.enumerated() {
            // The last glyphs differ per line (S, L, an ellipsis): their side bearings differ by under 1 pt.
            XCTAssertEqual(overhang, natural, accuracy: 1.0, "\(name): line \(index + 1) underline end", file: file, line: line)
            XCTAssertEqual(block.lines[index].line.lowerBound, block.lines[index].text.lowerBound, accuracy: 1.5, "\(name): line \(index + 1) underline start", file: file, line: line)
        }
    }

    func testWrappedLinesEndAtTheirLastGlyph() throws {
        let block = try block("VIEW ALL ITEMS VIEW ALL ITEMS VIEW ALL ITEMS", letterSpacing: 4, boxWidth: 200, fill: true)
        try assertLinesEndAtTheirLastGlyph("wrapped", block, lines: 3)
    }

    func testAHuggingWrappedLabelIsAsWideAsItsWidestLine() throws {
        let block = try block("VIEW ALL ITEMS VIEW ALL ITEMS VIEW ALL ITEMS", letterSpacing: 4, boxWidth: 200)
        try assertLinesEndAtTheirLastGlyph("wrapped, hugging", block, lines: 3)
        let ink = block.lines.map { $0.text.upperBound }.max()! - block.lines.map { $0.text.lowerBound }.min()!
        // Side bearings and rounding up to a whole point, not the 4 pt spacing.
        XCTAssertEqual(block.frame.width, ink, accuracy: 3.0)
    }

    func testLinesBeforeANewlineEndAtTheirLastGlyph() throws {
        let block = try block(#"VIEW ALL\nITEMS\nVIEW"#, letterSpacing: 4, boxWidth: 240)
        try assertLinesEndAtTheirLastGlyph("newlines", block, lines: 3)
        let ink = block.lines.map { $0.text.upperBound }.max()! - block.lines.map { $0.text.lowerBound }.min()!
        XCTAssertEqual(block.frame.width, ink, accuracy: 3.0)
    }

    /// Centred lines are centred on their glyphs: no line sits half the
    /// letter spacing to the left.
    func testCentredLinesAreCentredOnTheirGlyphs() throws {
        for (name, text) in [("wrapped", "VIEW ALL ITEMS VIEW ALL ITEMS VIEW ALL ITEMS"), ("newlines", #"VIEW ALL\nITEMS\nVIEW"#)] {
            let block = try block(text, letterSpacing: 4, boxWidth: 200, alignment: "center", fill: true)
            try assertLinesEndAtTheirLastGlyph("centred \(name)", block, lines: 3)
            let centres = block.lines.map { ($0.text.lowerBound + $0.text.upperBound) / 2 - 100 }
            print("[underline] centred \(name): ink centre off the box centre by " + centres.map { String(format: "%+.2f", $0) }.joined(separator: ", "))
            for (index, centre) in centres.enumerated() {
                XCTAssertEqual(centre, 0, accuracy: 1.0, "centred \(name): line \(index + 1)")
            }
        }
    }

    /// One line cut with an ellipsis: the underline ends at the ellipsis.
    func testATruncatedLineEndsAtItsEllipsis() throws {
        let block = try block("VIEW ALL ITEMS VIEW ALL ITEMS", letterSpacing: 4, boxWidth: 150, numberOfLines: 1, fill: true)
        try assertLinesEndAtTheirLastGlyph("truncated", block, lines: 1, ellipsis: true)
        XCTAssertLessThanOrEqual(block.lines[0].line.upperBound, 150.5, "the line stays inside the label")
        XCTAssertGreaterThan(block.lines[0].text.upperBound, 150 - 16, "the text is cut at the label's end, not earlier")
    }

    func testNegativeLetterSpacing() throws {
        let one = try block("VIEW ALL ITEMS", letterSpacing: -1.5, boxWidth: 240, numberOfLines: 1)
        try assertLinesEndAtTheirLastGlyph("negative, one line", one, lines: 1)
        XCTAssertGreaterThanOrEqual(one.frame.maxX + 0.5, one.lines[0].text.upperBound, "the last glyph is inside the label")
        let wrapped = try block("VIEW ALL ITEMS VIEW ALL ITEMS VIEW ALL ITEMS", letterSpacing: -1.5, boxWidth: 130, fill: true)
        try assertLinesEndAtTheirLastGlyph("negative, wrapped", wrapped, lines: 3)
        let truncated = try block("VIEW ALL ITEMS VIEW ALL ITEMS", letterSpacing: -1.5, boxWidth: 120, numberOfLines: 1, fill: true)
        try assertLinesEndAtTheirLastGlyph("negative, truncated", truncated, lines: 1, ellipsis: true)
        XCTAssertLessThanOrEqual(truncated.lines[0].line.upperBound, 120.5, "the line stays inside the label")
    }

    /// Two of three lines: the second one ends in an ellipsis, both end at
    /// their last glyph, and the label still asks for its whole text's width.
    func testATruncatedLastLineOfSeveral() throws {
        let block = try block("VIEW ALL ITEMS VIEW ALL ITEMS VIEW ALL ITEMS", letterSpacing: 4, boxWidth: 200, numberOfLines: 2, fill: true)
        XCTAssertEqual(block.lines.count, 2)
        let natural = try naturalOverhang(), ellipsis = try naturalEllipsisOverhang()
        let overhangs = block.lines.map { $0.line.upperBound - $0.text.upperBound }
        print(String(format: "[underline] 2 of 3 lines: line 1 right %+.2f, line 2 (ellipsis) right %+.2f", overhangs[0], overhangs[1]))
        XCTAssertEqual(overhangs[0], natural, accuracy: 1.0)
        XCTAssertEqual(overhangs[1], ellipsis, accuracy: 1.0)
        XCTAssertLessThanOrEqual(block.lines[1].line.upperBound, 200.5)
        XCTAssertEqual(block.label.accessibilityLabel, "VIEW ALL ITEMS VIEW ALL ITEMS VIEW ALL ITEMS", "the whole text is read out")
    }
}
