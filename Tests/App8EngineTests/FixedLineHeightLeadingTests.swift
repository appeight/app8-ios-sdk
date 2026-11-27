//
//  FixedLineHeightLeadingTests.swift
//  App8EngineTests
//
//  A `fixed` line height splits its leading (line height − the font's ascent
//  + descent, without its line gap) evenly above and below the glyphs, like
//  CSS half-leading. A
//  one-line label centred in a box therefore draws its glyphs where the same
//  label without a line height draws them. UIKit by itself puts all of the
//  extra height above the glyphs, so the text sat (lineHeight − natural) / 2
//  low: 14 pt text on a 22 pt line was 2.65 pt low ((22 − 16.71) / 2; drawn on
//  the 3x pixel grid that measures as 2.67 pt).
//
//  The tests measure drawn ink (rendered pixels), not frames.
//

import XCTest
@testable import App8Engine

@MainActor
final class FixedLineHeightLeadingTests: XCTestCase {

    private static let scale: CGFloat = 3

    /// Renders a 200 × 120 box with one label and returns the label and the
    /// drawn ink rows of the whole box, in points from the box's top.
    private func render(text: String, style: String, constraints: String, width: CGFloat = 200, height: CGFloat = 120, numberOfLines: Int? = nil) throws -> (label: UILabel, ink: InkRows) {
        let lines = numberOfLines.map { #", "numberOfLines": \#($0)"# } ?? ""
        let json = """
        {
          "type": "view", "id": "box",
          "content": {
            "layout": { "width": \(Int(width)), "height": \(Int(height)) },
            "children": [
              { "type": "label", "id": "text",
                "content": {
                  "properties": { "text": "\(text)"\(lines) },
                  "style": { "text": \(style) },
                  "layout": { "constraints": [ \(constraints) ] }
                } }
            ]
          }
        }
        """
        let harness = RenderHarness(size: CGSize(width: width, height: height), inWindow: false)
        try harness.render(json)
        for _ in 0..<3 {
            harness.drain(0.1)
            harness.superview.setNeedsLayout()
            harness.superview.layoutIfNeeded()
        }
        let label = try XCTUnwrap(harness.find(UILabel.self))
        return (label, InkRows(of: harness.superview, scale: Self.scale))
    }

    private static let centred = #"{ "type": "centerX", "target": "superview" }, { "type": "centerY", "target": "superview" }"#
    private static let topLeading = #"{ "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" }"#

    private func style(size: Int, lineHeight: Int?, extra: String = "") -> String {
        let lh = lineHeight.map { #", "lineHeight": { "type": "fixed", "value": \#($0) }"# } ?? ""
        return ##"{ "fontSize": \##(size), "color": "#000000"\##(lh)\##(extra) }"##
    }

    /// The headline case: 14 pt on a 22 pt line, centred in a box.
    func testCentredOneLineLabelDrawsWhereTheNaturalOneDoes() throws {
        for (size, lineHeight) in [(14, 22), (12, 20), (17, 28), (11, 24)] {
            let natural = try render(text: "Hxgp", style: style(size: size, lineHeight: nil), constraints: Self.centred)
            let fixed = try render(text: "Hxgp", style: style(size: size, lineHeight: lineHeight), constraints: Self.centred)
            let offset = fixed.ink.centre - natural.ink.centre
            let leading = CGFloat(lineHeight) - UIFont.systemFont(ofSize: CGFloat(size)).lineHeight
            print(String(format: "[leading] centred %d/%d: ink offset %.2f pt (top-loaded leading would give %.2f)", size, lineHeight, offset, leading / 2))
            XCTAssertEqual(offset, 0, accuracy: 0.5, "\(size) pt on a \(lineHeight) pt line: the glyphs are \(offset) pt off the box's centre")
            XCTAssertEqual(fixed.label.alignmentRect(forFrame: fixed.label.frame).height, CGFloat(lineHeight), accuracy: 0.01, "the label is one line high")
        }
    }

    /// The first line starts half the leading below the label's top.
    func testTopPinnedLabelStartsHalfTheLeadingDown() throws {
        let natural = try render(text: "Hxgp", style: style(size: 14, lineHeight: nil), constraints: Self.topLeading)
        let fixed = try render(text: "Hxgp", style: style(size: 14, lineHeight: 22), constraints: Self.topLeading)
        let half = (22 - UIFont.systemFont(ofSize: 14).lineHeight) / 2
        XCTAssertEqual(fixed.ink.top - natural.ink.top, half, accuracy: 0.5)
    }

    /// Several lines keep their pitch and the block its height: only the
    /// position inside each line moves.
    func testMultiLineBlockKeepsItsPitchAndHeight() throws {
        let text = "Hxgp Hxgp Hxgp Hxgp Hxgp Hxgp Hxgp Hxgp Hxgp Hxgp Hxgp Hxgp"
        let fixed = try render(text: text, style: style(size: 14, lineHeight: 22), constraints: Self.topLeading, width: 120, height: 200)
        let lines = fixed.ink.bands
        XCTAssertGreaterThanOrEqual(lines.count, 3)
        XCTAssertEqual(fixed.label.alignmentRect(forFrame: fixed.label.frame).height, CGFloat(lines.count) * 22, accuracy: 0.01, "block height = lines × line height")
        for (a, b) in zip(lines, lines.dropFirst()) {
            XCTAssertEqual(b.lowerBound - a.lowerBound, 22, accuracy: 0.5, "line pitch")
        }
        // Each line's ink is centred in its 22 pt slot like the first one.
        let natural = try render(text: "Hxgp", style: style(size: 14, lineHeight: nil), constraints: Self.topLeading)
        let half = (22 - UIFont.systemFont(ofSize: 14).lineHeight) / 2
        for (index, band) in lines.enumerated() {
            XCTAssertEqual(band.lowerBound - CGFloat(index) * 22, natural.ink.top + half, accuracy: 0.5, "line \(index + 1)")
        }
    }

    /// A line height below the natural one (tight display type) centres too,
    /// and nothing is cut off: the glyphs overflow the line evenly.
    func testTightLineHeightCentresWithoutClipping() throws {
        let natural = try render(text: "Hxgp", style: style(size: 40, lineHeight: nil), constraints: Self.centred)
        let fixed = try render(text: "Hxgp", style: style(size: 40, lineHeight: 36), constraints: Self.centred)
        XCTAssertEqual(fixed.ink.centre - natural.ink.centre, 0, accuracy: 0.5)
        XCTAssertEqual(fixed.ink.bottom - fixed.ink.top, natural.ink.bottom - natural.ink.top, accuracy: 0.5, "no ink is clipped")
        XCTAssertEqual(fixed.label.alignmentRect(forFrame: fixed.label.frame).height, 36, accuracy: 0.01)
    }

    /// Tight lines keep their pitch too.
    func testTightMultiLineBlockKeepsItsPitchAndHeight() throws {
        let fixed = try render(text: "HHH HHH HHH HHH", style: style(size: 40, lineHeight: 36), constraints: Self.topLeading, width: 110, height: 200)
        let lines = fixed.ink.bands
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(fixed.label.alignmentRect(forFrame: fixed.label.frame).height, CGFloat(lines.count) * 36, accuracy: 0.01)
        for (a, b) in zip(lines, lines.dropFirst()) {
            XCTAssertEqual(b.lowerBound - a.lowerBound, 36, accuracy: 0.5, "line pitch")
        }
    }

    /// Underline and strikethrough move with the glyphs.
    func testDecorationsMoveWithTheGlyphs() throws {
        let natural = try render(text: "Hxgp", style: style(size: 14, lineHeight: nil, extra: #", "underline": true"#), constraints: Self.centred)
        let fixed = try render(text: "Hxgp", style: style(size: 14, lineHeight: 22, extra: #", "underline": true"#), constraints: Self.centred)
        XCTAssertEqual(fixed.ink.top - natural.ink.top, 0, accuracy: 0.5)
        // The line itself is placed on whole pixels: up to 2 px at 3x.
        XCTAssertEqual(fixed.ink.bottom - natural.ink.bottom, 0, accuracy: 0.7)
    }

    /// A state style switches between a roomy and a tight line height at run
    /// time: the room for the overflowing glyphs (the label's alignment
    /// insets) follows, in both directions.
    func testOverflowRoomFollowsAStateStyleChange() throws {
        func text(_ lineHeight: Int) -> String { ##"{ "text": { "fontSize": 40, "color": "#000000", "lineHeight": { "type": "fixed", "value": \##(lineHeight) } } }"## }
        let json = """
        {
          "type": "view", "id": "box",
          "content": {
            "variables": { "tight": { "type": "boolean", "initialValue": false } },
            "layout": { "width": 200, "height": 120 },
            "children": [
              { "type": "label", "id": "text",
                "content": {
                  "properties": { "text": "Hxgp" },
                  "style": \(text(60)),
                  "states": { "roomy": { "style": \(text(60)) }, "tight": { "style": \(text(30)) } },
                  "defaultStateName": "{{tight ? 'tight' : 'roomy'}}",
                  "layout": { "constraints": [ \(Self.centred) ] }
                } }
            ]
          }
        }
        """
        let harness = RenderHarness(size: CGSize(width: 200, height: 120), inWindow: false)
        try harness.render(json)
        func settle() {
            for _ in 0..<3 {
                harness.drain(0.1)
                harness.superview.setNeedsLayout()
                harness.superview.layoutIfNeeded()
            }
        }
        settle()
        let label = try XCTUnwrap(harness.find(LineBoxLabel.self))
        let component = try XCTUnwrap(harness.service.componentRegistry.viewRegistry.view(forId: "box.text"))
        let root = try XCTUnwrap(harness.viewModel("box", as: CViewModel.self))
        let font = UIFont.systemFont(ofSize: 40)
        let overflow = ((font.ascender - font.descender) - 30) / 2
        let natural = try render(text: "Hxgp", style: style(size: 40, lineHeight: nil), constraints: Self.centred)
        let naturalInk = natural.ink.bottom - natural.ink.top

        func check(_ name: String, lineHeight: CGFloat, overflow: CGFloat) {
            let ink = InkRows(of: harness.superview, scale: Self.scale)
            print(String(format: "[leading] state %@: overflow %.2f, insets top %.2f, component height %.2f, label frame y %.2f height %.2f, ink %.2f…%.2f",
                         name, label.verticalOverflow, label.alignmentRectInsets.top, component.frame.height, label.frame.minY, label.frame.height, ink.top, ink.bottom))
            XCTAssertEqual(label.verticalOverflow, overflow, accuracy: 0.05, "\(name): overflow")
            XCTAssertEqual(component.frame.height, lineHeight, accuracy: 0.5, "\(name): the component is one line high")
            XCTAssertEqual(label.frame.minY, -overflow, accuracy: 0.5, "\(name): the label starts its overflow above the line")
            XCTAssertEqual(label.frame.height, lineHeight + 2 * overflow, accuracy: 0.5, "\(name): the label's frame holds the glyphs")
            XCTAssertEqual(ink.centre, natural.ink.centre, accuracy: 0.5, "\(name): the glyphs are centred")
            XCTAssertEqual(ink.bottom - ink.top, naturalInk, accuracy: 0.5, "\(name): no ink is clipped")
        }

        check("roomy", lineHeight: 60, overflow: 0)
        try root.variableStore.setValue(name: "tight", value: true)
        settle()
        check("tight", lineHeight: 30, overflow: overflow)
        try root.variableStore.setValue(name: "tight", value: false)
        settle()
        check("roomy again", lineHeight: 60, overflow: 0)
    }

    /// Fonts with a line gap: the leading is split around ascent + descent,
    /// the gap is not part of it. The baseline of the first line is
    /// (line height − (ascent + descent)) / 2 + ascent below the label's top.
    func testHalfLeadingIgnoresTheFontsLineGap() throws {
        var checked = 0
        for name in ["HiraginoSans-W3", "Thonburi", "TimesNewRomanPSMT", "HelveticaNeue"] {
            guard let font = UIFont(name: name, size: 40) else { continue }
            XCTAssertGreaterThan(font.leading, 0.5, "\(name) has a line gap")
            checked += 1
            let fixed = try render(text: "HHH", style: style(size: 40, lineHeight: 64, extra: #", "fontFamily": "\#(name)""#), constraints: Self.topLeading)
            let content = font.ascender - font.descender
            let expected = (64 - content) / 2 + font.ascender
            let withGap = (64 - content - font.leading) / 2 + font.ascender
            print(String(format: "[leading] %@ 40/64: line gap %.2f, UIFont.lineHeight %.2f, ascent + descent %.2f; baseline at %.2f, expected %.2f (%.2f if the gap counted)",
                         name, font.leading, font.lineHeight, content, fixed.ink.bottom, expected, withGap))
            XCTAssertEqual(fixed.ink.bottom, expected, accuracy: 0.5, "\(name): baseline of a 40 pt H on a 64 pt line")
            XCTAssertEqual(font.halfLeading(forLineHeight: 64), (64 - content) / 2, accuracy: 0.001)
        }
        XCTAssertGreaterThanOrEqual(checked, 1, "the test host has a font with a line gap")
    }

    /// Tight lines with a line limit: the last visible line's descenders are
    /// not cut off. Two of four lines draw as low as a two-line text does.
    func testTightLinesWithALineLimitKeepTheLastLinesDescenders() throws {
        let whole = try render(text: "Hgp Hgp", style: style(size: 40, lineHeight: 36), constraints: Self.topLeading, width: 110, height: 200)
        let limited = try render(text: "Hgp Hgp Hgp Hgp", style: style(size: 40, lineHeight: 36), constraints: Self.topLeading, width: 110, height: 200, numberOfLines: 2)
        let font = UIFont.systemFont(ofSize: 40)
        // Baseline of line 2 plus the descender of "g" / "p".
        let overflow = ((font.ascender - font.descender) - 36) / 2
        print(String(format: "[leading] tight 40/36, 2 of 4 lines: ink %.2f…%.2f; two-line text %.2f…%.2f; line box ends at %.2f, glyph box at %.2f",
                     limited.ink.top, limited.ink.bottom, whole.ink.top, whole.ink.bottom, 72.0, 72 + overflow))
        XCTAssertEqual(whole.label.alignmentRect(forFrame: whole.label.frame).height, 72, accuracy: 0.01)
        XCTAssertEqual(limited.label.alignmentRect(forFrame: limited.label.frame).height, 72, accuracy: 0.01, "two lines high")
        XCTAssertEqual(limited.ink.bottom, whole.ink.bottom, accuracy: 0.5, "the last visible line's descenders are whole")
        XCTAssertEqual(limited.ink.top, whole.ink.top, accuracy: 0.5)
        XCTAssertGreaterThan(limited.ink.bottom, 72, "the descenders reach below the line box")
    }
}
