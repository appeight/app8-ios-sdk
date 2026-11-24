//
//  StretchyCoverTests.swift
//  App8EngineTests
//
//  Stretchy top (scroll-view.md): on a pull of d the hero's frame grows by d
//  with its top on the scroll view's top edge; only its background (its own
//  material and the children covering it) scales; every other child keeps
//  its constraints in the taller frame, at its own size.
//

import XCTest
import UIKit
@testable import App8Engine

@MainActor
final class StretchyCoverTests: XCTestCase {

    private static let edges = #"[ { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" }, { "type": "bottom", "target": "superview" } ]"#

    /// `scrollView > stack > hero (fill, height >= width) + below`. The hero has
    /// a covering photo, a badge pinned to its top, a centred mark, and a
    /// block pinned to its top and its bottom (its height from its content).
    private static let screen = #"""
    { "type": "scrollView", "id": "s", "content": {
        "properties": { "stretchesTopChild": true, "contentInsetAdjustment": "never" },
        "layout": { "constraints": \#(edges) },
        "children": [ { "type": "stackView", "id": "stack", "content": {
          "properties": { "axis": "vertical", "spacing": 0, "alignment": "fill" },
          "layout": { "constraints": \#(edges) },
          "children": [
            { "type": "view", "id": "hero", "content": {
                "style": { "material": [ { "id": "f", "type": "fill", "content": { "solid": "#AA2233" } } ] },
                "layout": { "constraints": [ { "type": "height", "target": "superview", "attribute": "width", "op": ">=", "multiplier": 1 } ] },
                "children": [
                  { "type": "view", "id": "photo", "content": { "layout": { "constraints": \#(edges) } } },
                  { "type": "view", "id": "badge", "content": { "layout": { "width": 40, "height": 24, "constraints": [
                      { "type": "top", "target": "superview", "constant": 12 }, { "type": "leading", "target": "superview", "constant": 12 } ] } } },
                  { "type": "view", "id": "mark", "content": { "layout": { "width": 30, "height": 30, "constraints": [
                      { "type": "centerX", "target": "superview" }, { "type": "centerY", "target": "superview" } ] } } },
                  { "type": "stackView", "id": "block", "content": {
                      "properties": { "axis": "vertical", "spacing": 0, "alignment": "fill" },
                      "layout": { "constraints": [ { "type": "top", "target": "superview", "constant": 120 },
                        { "type": "leading", "target": "superview", "constant": 16 }, { "type": "trailing", "target": "superview", "constant": -16 },
                        { "type": "bottom", "target": "superview", "constant": -24 } ] },
                      "children": [ { "type": "view", "id": "line1", "content": { "layout": { "height": 300 } } },
                                    { "type": "view", "id": "line2", "content": { "layout": { "height": 44 } } } ] } } ] } },
            { "type": "view", "id": "below", "content": { "layout": { "height": 1200 } } } ] } } ] } }
    """#

    private func render() throws -> (RenderHarness, App8ZoomingScrollView, CView) {
        let harness = RenderHarness(size: CGSize(width: 390, height: 844))
        try harness.render(Self.screen)
        harness.drain()
        harness.superview.layoutIfNeeded()
        let scroll = try XCTUnwrap(harness.find(App8ZoomingScrollView.self))
        let hero = try XCTUnwrap(Self.view("hero", in: scroll) as? CView)
        return (harness, scroll, hero)
    }

    private static func view(_ id: String, in root: UIView) -> UIView? {
        if root.accessibilityIdentifier == id { return root }
        for sub in root.subviews { if let found = view(id, in: sub) { return found } }
        return nil
    }

    /// The frame `view` is drawn at (transform included), in the hero's space.
    private func drawn(_ view: UIView, in hero: UIView) -> CGRect {
        view.superview!.convert(view.frame, to: hero)
    }

    func testPullGrowsTheHeroAndScalesOnlyItsBackground() throws {
        let (_, scroll, hero) = try render()
        let h = hero.bounds.height
        let badge = try XCTUnwrap(Self.view("badge", in: hero))
        let mark = try XCTUnwrap(Self.view("mark", in: hero))
        let block = try XCTUnwrap(Self.view("block", in: hero))
        let photo = try XCTUnwrap(Self.view("photo", in: hero))
        let material = try XCTUnwrap(hero.materialView)
        let restBlock = drawn(block, in: hero)
        let restMark = drawn(mark, in: hero)
        XCTAssertEqual(h, 488, accuracy: 0.5, "height from the block: 120 + 344 + 24")

        let d: CGFloat = 100
        scroll.setContentOffset(CGPoint(x: 0, y: -d), animated: false)

        // The hero's own frame keeps its rest height; its content view grows up by d.
        XCTAssertEqual(hero.bounds.height, h, accuracy: 0.5)
        XCTAssertEqual(drawn(hero.contentView, in: hero).minY, -d, accuracy: 0.5)
        XCTAssertEqual(drawn(hero.contentView, in: hero).height, h + d, accuracy: 0.5)

        // Background: the material and the covering photo fill the taller frame, scaled.
        for background in [material, photo] {
            let frame = drawn(background, in: hero)
            XCTAssertEqual(frame.minY, -d, accuracy: 0.5, "\(background)")
            XCTAssertEqual(frame.maxY, h, accuracy: 0.5, "\(background)")
            XCTAssertEqual(background.transform.a, (h + d) / h, accuracy: 0.001)
        }

        // UI: never scaled, laid out again in the taller frame.
        for ui in [badge, mark, block] { XCTAssertEqual(ui.transform, .identity, "\(ui.accessibilityIdentifier ?? "")") }
        XCTAssertEqual(drawn(badge, in: hero).minY, -d + 12, accuracy: 0.5, "pinned to the top: stays at the top")
        XCTAssertEqual(drawn(badge, in: hero).size, CGSize(width: 40, height: 24))
        XCTAssertEqual(drawn(mark, in: hero).midY, restMark.midY - d / 2, accuracy: 0.5, "centred: re-centres")
        XCTAssertEqual(drawn(block, in: hero).height, restBlock.height, accuracy: 0.5, "top and bottom: keeps its size")
        XCTAssertEqual(drawn(block, in: hero).maxY, restBlock.maxY, accuracy: 0.5, "and stays on the bottom")

        // Back at rest: everything as before.
        scroll.setContentOffset(.zero, animated: false)
        hero.superview?.layoutIfNeeded()
        for v in [material, photo, badge, mark, block] { XCTAssertEqual(v.transform, .identity) }
        XCTAssertEqual(drawn(hero.contentView, in: hero), hero.bounds)
        XCTAssertEqual(drawn(block, in: hero), restBlock)
        XCTAssertEqual(drawn(badge, in: hero).minY, 12, accuracy: 0.5)
    }

    /// The content below moves down with the pull by exactly d.
    func testContentBelowMovesWithThePull() throws {
        let (_, scroll, hero) = try render()
        let below = try XCTUnwrap(Self.view("below", in: scroll))
        let rest = below.convert(below.bounds, to: scroll.superview).minY
        scroll.setContentOffset(CGPoint(x: 0, y: -80), animated: false)
        XCTAssertEqual(below.convert(below.bounds, to: scroll.superview).minY, rest + 80, accuracy: 0.5)
        XCTAssertEqual(hero.convert(hero.bounds, to: scroll.superview).maxY, rest + 80, accuracy: 0.5)
        scroll.setContentOffset(.zero, animated: false)
    }

    /// A child set down from its container's top (`top: superview + 40`) is
    /// content of that container, not its hero.
    func testAChildSetDownFromTheTopIsNotTheHero() throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 844))
        try harness.render(#"""
        { "type": "scrollView", "id": "s", "content": {
            "properties": { "stretchesTopChild": true, "contentInsetAdjustment": "never" },
            "layout": { "constraints": \#(Self.edges) },
            "children": [ { "type": "view", "id": "cover", "content": {
                "layout": { "constraints": [ { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
                  { "type": "trailing", "target": "superview" }, { "type": "bottom", "target": "superview" },
                  { "type": "height", "target": "superview", "attribute": "width", "op": ">=", "multiplier": 1 } ] },
                "children": [ { "type": "view", "id": "mark", "content": { "layout": { "height": 100, "constraints": [
                    { "type": "top", "target": "superview", "constant": 40 }, { "type": "leading", "target": "superview" },
                    { "type": "trailing", "target": "superview" } ] } } } ] } } ] } }
        """#)
        harness.drain()
        harness.superview.layoutIfNeeded()
        let scroll = try XCTUnwrap(harness.find(App8ZoomingScrollView.self))
        let cover = try XCTUnwrap(Self.view("cover", in: scroll))
        XCTAssertEqual(CScrollViewView.stretchHero(from: cover).accessibilityIdentifier, "cover")
    }

    // MARK: - Top pins stay at the top (safe area and superview)

    /// A cover under a 47 pt top safe area (a notch), its height fixed, with
    /// a mark pinned to the safe area's top and a badge pinned to the cover's
    /// top. The cover's top stays on the screen's top during a pull, so both
    /// keep their place on screen, as on the web renderer.
    func testTopPinnedChildrenKeepTheirPlaceOnScreen() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let vc = UIViewController()
        vc.additionalSafeAreaInsets = UIEdgeInsets(top: 47, left: 0, bottom: 0, right: 0)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        let harness = RenderHarness(size: CGSize(width: 390, height: 844), inWindow: false)
        harness.superview.frame = vc.view.bounds
        vc.view.addSubview(harness.superview)
        try harness.render(#"""
        { "type": "scrollView", "id": "s", "content": {
            "properties": { "stretchesTopChild": true, "contentInsetAdjustment": "never" },
            "layout": { "constraints": \#(Self.edges) },
            "children": [ { "type": "stackView", "id": "stack", "content": {
              "properties": { "axis": "vertical", "spacing": 0, "alignment": "fill" },
              "layout": { "constraints": \#(Self.edges) },
              "children": [
                { "type": "view", "id": "hero", "content": {
                    "style": { "material": [ { "id": "f", "type": "fill", "content": { "solid": "#AA2233" } } ] },
                    "layout": { "constraints": [ { "type": "height", "target": "superview", "attribute": "width", "multiplier": 1.18 } ] },
                    "children": [
                      { "type": "view", "id": "mark", "content": { "layout": { "width": 60, "height": 40, "constraints": [
                          { "type": "top", "target": "safeArea", "constant": 40 }, { "type": "trailing", "target": "superview", "constant": -16 } ] } } },
                      { "type": "view", "id": "badge", "content": { "layout": { "width": 40, "height": 24, "constraints": [
                          { "type": "top", "target": "superview", "constant": 12 }, { "type": "leading", "target": "superview", "constant": 12 } ] } } },
                      { "type": "stackView", "id": "text", "content": {
                          "properties": { "axis": "vertical" },
                          "layout": { "constraints": [ { "type": "top", "target": "safeArea", "constant": 120 },
                            { "type": "leading", "target": "superview", "constant": 16 }, { "type": "trailing", "target": "superview", "constant": -16 },
                            { "type": "bottom", "target": "superview", "constant": -50 } ] },
                          "children": [ { "type": "view", "id": "line", "content": { "layout": { "height": 44 } } } ] } },
                      { "type": "view", "id": "foot", "content": { "layout": { "height": 30, "constraints": [
                          { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" },
                          { "type": "bottom", "target": "superview", "constant": -10 } ] } } } ] } },
                { "type": "view", "id": "below", "content": { "layout": { "height": 1200 } } } ] } } ] } }
        """#)
        harness.drain()
        window.layoutIfNeeded()
        let scroll = try XCTUnwrap(harness.find(App8ZoomingScrollView.self))
        let hero = try XCTUnwrap(Self.view("hero", in: scroll))
        let onScreen = { (id: String) -> CGRect in
            let v = Self.view(id, in: hero)!
            return v.superview!.convert(v.frame, to: window)
        }
        let rest = (mark: onScreen("mark"), badge: onScreen("badge"), foot: onScreen("foot"), text: onScreen("text"))
        XCTAssertGreaterThan(rest.mark.minY, 47 + 40 - 0.5, "the safe area reaches the cover")

        for d: CGFloat in [20, 40, 100] {
            scroll.setContentOffset(CGPoint(x: 0, y: -d), animated: false)
            // A layout pass, as a frame does: UIKit updates the safe areas
            // (the cover's shrinks with the pull) and lays the cover out.
            window.layoutIfNeeded()
            XCTAssertEqual(scroll.contentOffset.y, -d, accuracy: 0.5)
            XCTAssertEqual(onScreen("mark").minY, rest.mark.minY, accuracy: 0.5, "safe-area pin @\(d)")
            XCTAssertEqual(onScreen("mark").height, 40, accuracy: 0.5)
            XCTAssertEqual(onScreen("badge").minY, rest.badge.minY, accuracy: 0.5, "superview pin @\(d)")
            XCTAssertEqual(onScreen("foot").minY, rest.foot.minY + d, accuracy: 0.5, "bottom pin @\(d)")
            XCTAssertEqual(onScreen("text").height, rest.text.height, accuracy: 0.5, "safe-area top + bottom: its size @\(d)")
            XCTAssertEqual(onScreen("text").maxY, rest.text.maxY + d, accuracy: 0.5, "and on the bottom @\(d)")
        }
        scroll.setContentOffset(.zero, animated: false)
        window.layoutIfNeeded()
        XCTAssertEqual(onScreen("mark"), rest.mark)
        XCTAssertEqual(onScreen("badge"), rest.badge)
        XCTAssertEqual(onScreen("text"), rest.text)
        func all(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(all) }
        let leftovers = all(hero).flatMap(\.constraints).filter { $0.identifier?.hasPrefix("app8.stretchyTop") == true && $0.isActive }
        XCTAssertEqual(leftovers, [], "no stand-in survives the pull")
        window.isHidden = true
    }
}
