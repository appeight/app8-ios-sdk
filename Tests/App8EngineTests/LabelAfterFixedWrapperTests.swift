//
//  LabelAfterFixedWrapperTests.swift
//  App8EngineTests
//
//  In a vertical fill stack, a multi-line label (numberOfLines 0) that follows
//  a wrapper view with a fixed height (an image pinned inside it) wraps to as
//  many lines as it needs, like the labels before it: not one truncated line.
//

import XCTest
@testable import App8Engine

@MainActor
final class LabelAfterFixedWrapperTests: XCTestCase {

    private static let json = #"""
{"type": "view", "id": "root", "content": {"layout": {"width": 390, "height": 844}, "children": [{"type": "stackView", "id": "page", "content": {"properties": {"axis": "vertical", "spacing": 10, "alignment": "fill"}, "layout": {"constraints": [{"type": "top", "target": "safeArea", "constant": 16}, {"type": "leading", "target": "superview", "constant": 16}, {"type": "trailing", "target": "superview", "constant": -16}]}, "children": [{"type": "label", "id": "t", "content": {"properties": {"text": "Asset map: localAsset names", "numberOfLines": 0}, "style": {"text": {"fontSize": 20, "fontWeight": "bold", "color": "#0F172A"}}}}, {"type": "label", "id": "aL", "content": {"properties": {"text": "A. localAsset \"brand-mark\" (asset map -> mark-art.png): a yellow disc on blue", "numberOfLines": 0}, "style": {"text": {"fontSize": 13, "color": "#334155"}}}}, {"type": "view", "id": "aW", "content": {"layout": {"height": 96}, "children": [{"type": "image", "id": "a", "content": {"properties": {"type": "localAsset", "name": "brand-mark"}, "style": {"contentMode": "scaleToFill", "material": [{"id": "abg", "type": "fill", "content": {"solid": "#E2E8F0"}}]}, "layout": {"width": 96, "height": 96, "constraints": [{"type": "top", "target": "superview"}, {"type": "leading", "target": "superview"}]}}}]}}, {"type": "label", "id": "bL", "content": {"properties": {"text": "B. asset \"stripe-art\" (no type; map -> bands.jpg): six colour bands", "numberOfLines": 0}, "style": {"text": {"fontSize": 13, "color": "#334155"}}}}, {"type": "view", "id": "bW", "content": {"layout": {"height": 12}, "children": [{"type": "image", "id": "b", "content": {"properties": {"asset": "stripe-art"}, "style": {"contentMode": "scaleToFill", "material": [{"id": "bbg", "type": "fill", "content": {"solid": "#E2E8F0"}}]}, "layout": {"width": 300, "height": 12, "constraints": [{"type": "top", "target": "superview"}, {"type": "leading", "target": "superview"}]}}}]}}, {"type": "label", "id": "cL", "content": {"properties": {"text": "C. remoteAsset name \"brand-mark\": the same disc, smaller", "numberOfLines": 0}, "style": {"text": {"fontSize": 13, "color": "#334155"}}}}, {"type": "view", "id": "cW", "content": {"layout": {"height": 64}, "children": [{"type": "image", "id": "c", "content": {"properties": {"type": "remoteAsset", "name": "brand-mark"}, "style": {"contentMode": "scaleToFill", "material": [{"id": "cbg", "type": "fill", "content": {"solid": "#E2E8F0"}}]}, "layout": {"width": 64, "height": 64, "constraints": [{"type": "top", "target": "superview"}, {"type": "leading", "target": "superview"}]}}}]}}, {"type": "label", "id": "dL", "content": {"properties": {"text": "D. localAsset \"not-in-map\": nothing (only the grey background)", "numberOfLines": 0}, "style": {"text": {"fontSize": 13, "color": "#334155"}}}}, {"type": "view", "id": "dW", "content": {"layout": {"height": 64}, "children": [{"type": "image", "id": "d", "content": {"properties": {"type": "localAsset", "name": "not-in-map"}, "style": {"contentMode": "scaleToFill", "material": [{"id": "dbg", "type": "fill", "content": {"solid": "#E2E8F0"}}]}, "layout": {"width": 64, "height": 64, "constraints": [{"type": "top", "target": "superview"}, {"type": "leading", "target": "superview"}]}}}]}}]}}]}}
"""#

    private func labels(in view: UIView) -> [UILabel] {
        view.subviews.flatMap { sub -> [UILabel] in ((sub as? UILabel).map { [$0] } ?? []) + labels(in: sub) }
    }

    func testEveryCaptionWrapsInsteadOfTruncating() throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 844))
        try harness.render(Self.json)
        harness.drain()
        harness.superview.layoutIfNeeded()
        harness.drain(0.05)
        harness.superview.layoutIfNeeded()
        let captions = labels(in: harness.superview).filter { ($0.text ?? "").hasPrefix("A.") || ($0.text ?? "").hasPrefix("B.") || ($0.text ?? "").hasPrefix("C.") || ($0.text ?? "").hasPrefix("D.") }
        XCTAssertEqual(captions.count, 4)
        for label in captions {
            let fits = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height
            XCTAssertGreaterThanOrEqual(label.bounds.height + 0.5, fits, "\(label.text!.prefix(2)) is cut: \(label.bounds) needs \(fits)")
            XCTAssertGreaterThan(label.bounds.height, 25, "\(label.text!.prefix(2)) wraps to two lines")
        }
    }
}
