//
//  FixedLineHeightLeadingTests.swift
//  App8EngineTests
//
//  A `fixed` line height splits its leading (line height − the font's natural
//  line height) evenly above and below the glyphs, like CSS half-leading. A
//  one-line label centred in a box therefore draws its glyphs where the same
//  label without a line height draws them. UIKit by itself puts all of the
//  extra height above the glyphs, so the text sat (lineHeight − natural) / 2
//  low: 14 pt text on a 22 pt line was 2.65 pt low.
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
    private func render(text: String, style: String, constraints: String, width: CGFloat = 200, height: CGFloat = 120) throws -> (label: UILabel, ink: InkRows) {
        let json = """
        {
          "type": "view", "id": "box",
          "content": {
            "layout": { "width": \(Int(width)), "height": \(Int(height)) },
            "children": [
              { "type": "label", "id": "text",
                "content": {
                  "properties": { "text": "\(text)" },
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
}

/// Rows of a rendered view that contain dark ink, in points.
@MainActor
struct InkRows {
    /// Runs of consecutive ink rows (one per text line when lines do not touch).
    let bands: [ClosedRange<CGFloat>]
    /// Leftmost and rightmost ink column, in points.
    let columns: ClosedRange<CGFloat>?

    var top: CGFloat { bands.first?.lowerBound ?? .nan }
    var bottom: CGFloat { bands.last?.upperBound ?? .nan }
    var centre: CGFloat { (top + bottom) / 2 }

    init(of view: UIView, scale: CGFloat, in rect: CGRect? = nil) {
        let size = view.bounds.size
        let width = Int(size.width * scale), height = Int(size.height * scale)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        UIGraphicsPushContext(context)
        view.layer.render(in: context)
        UIGraphicsPopContext()

        let x0 = max(0, Int((rect?.minX ?? 0) * scale)), x1 = min(width, Int((rect?.maxX ?? size.width) * scale))
        let y0 = max(0, Int((rect?.minY ?? 0) * scale)), y1 = min(height, Int((rect?.maxY ?? size.height) * scale))
        var bands: [ClosedRange<CGFloat>] = []
        var start: Int?
        var minX = Int.max, maxX = Int.min
        for y in y0..<y1 {
            var ink = false
            for x in x0..<x1 where pixels[(y * width + x) * 4] < 128 {
                ink = true
                minX = min(minX, x); maxX = max(maxX, x)
            }
            if ink, start == nil { start = y }
            if !ink, let s = start {
                bands.append(CGFloat(s) / scale ... CGFloat(y) / scale)
                start = nil
            }
        }
        if let s = start { bands.append(CGFloat(s) / scale ... CGFloat(y1) / scale) }
        self.bands = bands
        columns = minX <= maxX ? CGFloat(minX) / scale ... CGFloat(maxX + 1) / scale : nil
    }
}
