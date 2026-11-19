//
//  CardTextOverImageTests.swift
//  App8EngineTests
//
//  A card in a vertical scroll view's stack: height = 0.8 × its width, an
//  image filling it, a text stack pinned to its bottom and sides (a caption
//  and a multi-line paragraph). The text stack must sit inside the card, at
//  its bottom, as tall as its two labels.
//

import XCTest
@testable import App8Engine

@MainActor
final class CardTextOverImageTests: XCTestCase {

    private static let json = #"""
{"type": "view", "id": "root", "content": {"layout": {"width": 402, "height": 874}, "children": [{"id": "scr532", "type": "scrollView", "content": {"properties": {"direction": "vertical", "showsIndicator": false, "contentInsetAdjustment": "automatic"}, "layout": {"constraints": [{"type": "top", "target": "superview"}, {"type": "leading", "target": "superview"}, {"type": "trailing", "target": "superview"}, {"type": "bottom", "target": "superview"}]}, "children": [{"id": "sta531", "type": "stackView", "content": {"properties": {"axis": "vertical", "spacing": 0, "alignment": "fill"}, "layout": {"constraints": [{"type": "top", "target": "superview"}, {"type": "leading", "target": "superview"}, {"type": "trailing", "target": "superview"}, {"type": "bottom", "target": "superview"}]}, "children": [{"id": "vie459", "type": "view", "content": {"children": [{"id": "lab458", "type": "label", "content": {"properties": {"text": "Sign in to continue"}, "style": {"text": {"fontSize": 16, "color": "#000000", "fontWeight": "medium", "lineHeight": {"type": "multiplier", "value": 1.25}}}, "layout": {"constraints": [{"type": "top", "target": "superview", "constant": 8}, {"type": "leading", "target": "superview", "constant": 16}, {"type": "trailing", "target": "superview", "constant": -16}, {"type": "bottom", "target": "superview"}]}}}]}}, {"id": "vie460", "type": "view", "content": {"layout": {"height": 8}}}, {"id": "vie462", "type": "view", "content": {"children": [{"id": "lab461", "type": "label", "content": {"properties": {"text": "Keep your orders, your saved items and your rewards in one place.", "numberOfLines": 0}, "style": {"text": {"fontSize": 13, "color": "#5D5D5D", "fontWeight": "regular", "lineHeight": {"type": "multiplier", "value": 1.2}}}, "layout": {"constraints": [{"type": "top", "target": "superview"}, {"type": "leading", "target": "superview", "constant": 16}, {"type": "trailing", "target": "superview", "constant": -16}, {"type": "bottom", "target": "superview"}]}}}]}}, {"id": "vie463", "type": "view", "content": {"layout": {"height": 16}}}, {"id": "vie466", "type": "view", "content": {"properties": {"isHidden": "{{signedIn}}"}, "children": [{"id": "but465", "type": "button", "content": {"properties": {"text": "LOG IN"}, "style": {"text": {"id": "buttonW"}, "material": [{"id": "f464", "type": "fill", "content": {"solid": "#000000"}}]}, "layout": {"height": 50, "constraints": [{"type": "top", "target": "superview"}, {"type": "leading", "target": "superview", "constant": 16}, {"type": "trailing", "target": "superview", "constant": -16}, {"type": "bottom", "target": "superview"}]}, "actions": {}}}]}}, {"id": "vie467", "type": "view", "content": {"layout": {"height": 32}}}, {"id": "vie475", "type": "view", "content": {"children": [{"id": "clubTile", "type": "view", "content": {"layout": {"constraints": [{"type": "top", "target": "superview"}, {"type": "leading", "target": "superview", "constant": 16}, {"type": "trailing", "target": "superview", "constant": -16}, {"type": "bottom", "target": "superview"}, {"type": "height", "target": "superview", "attribute": "width", "multiplier": 0.8}]}, "children": [{"id": "clubHero", "type": "image", "content": {"properties": {"type": "remoteAsset", "url": "https://invalid.example/x.jpg"}, "style": {"contentMode": "scaleAspectFill"}, "layout": {"constraints": [{"type": "top", "target": "superview"}, {"type": "leading", "target": "superview"}, {"type": "trailing", "target": "superview"}, {"type": "bottom", "target": "superview"}]}, "interaction": {"clipsToBounds": "true"}}}, {"id": "vie469", "type": "view", "content": {"style": {"material": [{"id": "g468", "type": "fill", "content": {"gradient": {"start": {"x": 0.5, "y": 0, "color": "#00000000"}, "end": {"x": 0.5, "y": 1, "color": "#000000A6"}}}}]}, "layout": {"height": 140, "constraints": [{"type": "leading", "target": "superview"}, {"type": "trailing", "target": "superview"}, {"type": "bottom", "target": "superview"}]}}}, {"id": "ima470", "type": "view", "content": {"style": {"material": [{"id": "stripeF", "type": "fill", "content": {"solid": "#F59E0B"}}]}, "layout": {"height": 4, "constraints": [{"type": "top", "target": "superview"}, {"type": "leading", "target": "superview"}, {"type": "trailing", "target": "superview"}]}}}, {"id": "sta473", "type": "stackView", "content": {"properties": {"axis": "vertical", "spacing": 6, "alignment": "fill"}, "layout": {"constraints": [{"type": "leading", "target": "superview", "constant": 16}, {"type": "trailing", "target": "superview", "constant": -16}, {"type": "bottom", "target": "superview", "constant": -16}]}, "children": [{"id": "lab471", "type": "label", "content": {"properties": {"text": "MEMBERS CLUB"}, "style": {"text": {"fontSize": 12, "color": "#FFFFFF", "fontWeight": "medium", "lineHeight": {"type": "multiplier", "value": 1.2}}}}}, {"id": "lab472", "type": "label", "content": {"properties": {"text": "Expected: these two lines of white text sit inside the photo card, at its bottom, above the gradient; nothing draws over the black button or outside the card.", "numberOfLines": 0}, "style": {"text": {"fontSize": 15, "color": "#FFFFFF", "fontWeight": "regular", "lineHeight": {"type": "multiplier", "value": 1.2}}}}}]}}, {"id": "but474", "type": "button", "content": {"properties": {"text": ""}, "style": {"system": {"variant": "plain"}}, "layout": {"constraints": [{"type": "top", "target": "superview"}, {"type": "leading", "target": "superview"}, {"type": "trailing", "target": "superview"}, {"type": "bottom", "target": "superview"}]}, "actions": {}}}]}}]}}, {"id": "vie476", "type": "view", "content": {"layout": {"height": 24}}}]}}]}}]}}
"""#

    private func labels(in view: UIView) -> [UILabel] {
        view.subviews.flatMap { sub -> [UILabel] in ((sub as? UILabel).map { [$0] } ?? []) + labels(in: sub) }
    }

    func testTextStackSitsInsideTheCard() throws {
        let harness = RenderHarness(size: CGSize(width: 402, height: 874))
        try harness.render(Self.json)
        harness.drain()
        harness.superview.layoutIfNeeded()
        harness.drain(0.05)
        harness.superview.layoutIfNeeded()
        let all = labels(in: harness.superview)
        let caption = try XCTUnwrap(all.first { $0.text == "MEMBERS CLUB" })
        let body = try XCTUnwrap(all.first { $0.text?.hasPrefix("Expected: these two lines") == true })
        // The card: the first ancestor of the text that is as tall as 0.8 × its width.
        var node: UIView? = caption
        while let v = node, abs(v.bounds.height - v.bounds.width * 0.8) > 1 || v.bounds.width < 300 { node = v.superview }
        let card = try XCTUnwrap(node, "the text stack's card")
        let cardFrame = card.convert(card.bounds, to: nil)
        let captionFrame = caption.convert(caption.bounds, to: nil)
        let bodyFrame = body.convert(body.bounds, to: nil)
        XCTAssertGreaterThan(cardFrame.height, 250)
        XCTAssertTrue(cardFrame.insetBy(dx: -0.5, dy: -0.5).contains(captionFrame), "caption inside the card")
        XCTAssertTrue(cardFrame.insetBy(dx: -0.5, dy: -0.5).contains(bodyFrame), "paragraph inside the card")
        XCTAssertEqual(bodyFrame.maxY, cardFrame.maxY - 16, accuracy: 1, "text at the card's bottom")
        // Four lines at 15 pt × 1.2 at most: not a word per line.
        XCTAssertLessThan(bodyFrame.height, 18 * 5)
        XCTAssertGreaterThan(bodyFrame.width, 300)
        // The paragraph above the button wraps to two lines and is not clipped.
        let intro = try XCTUnwrap(all.first { $0.text?.hasPrefix("Keep your orders") == true })
        XCTAssertGreaterThan(intro.bounds.height, 30, "two lines")
        XCTAssertGreaterThanOrEqual(intro.bounds.height + 0.5, intro.sizeThatFits(CGSize(width: intro.bounds.width, height: .greatestFiniteMagnitude)).height, "not clipped")
        XCTAssertGreaterThanOrEqual(body.bounds.height + 0.5, body.sizeThatFits(CGSize(width: body.bounds.width, height: .greatestFiniteMagnitude)).height, "not clipped")
    }
}
