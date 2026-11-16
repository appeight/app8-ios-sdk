//
//  GridScrollStabilityTests.swift
//  App8EngineTests
//
//  A long self-sizing grid (2-column cards whose titles wrap to
//  1-3 lines) must scroll like a plain list:
//  - the content tracks the finger 1:1: UIKit never moves the offset on its
//    own while the user scrolls (a row above the viewport changing height
//    shifts everything under the finger, "faster than the finger");
//  - heights are final after an item's first measure: scrolling back over
//    items already seen, or resting at the bottom, changes no row height and
//    no content size (no jump after deceleration);
//  - no layout invalidation per frame: a scroll step that brings in no new
//    item, the bottom overscroll included, invalidates nothing.
//

import XCTest
@testable import App8Engine

@MainActor
final class GridScrollStabilityTests: XCTestCase {

    private static let count = 60
    private static let width: CGFloat = 390
    private static let height: CGFloat = 760

    /// Titles of 1, 2 or 3 lines at the card's width, in an irregular order so
    /// rows mix lengths, and reuse hands a cell an item of another height.
    private static func title(_ i: Int) -> String {
        let words = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Theta", "Kappa"]
        let lines = [1, 3, 2, 1, 2, 3, 3, 1, 2][i % 9]
        let perLine = 2
        return (0..<(lines * perLine)).map { words[($0 + i) % words.count] + "\u{00A0}Plus" }.joined(separator: " ")
    }

    private static var itemsJSON: String {
        (0..<count).map { i in
            let subtitle = i % 4 == 0 ? "Subtitle line" : ""
            return #"{"id":"p\#(i)","title":"\#(title(i))","subtitle":"\#(subtitle)"}"#
        }.joined(separator: ",")
    }

    private static let card = """
    { "id": "card", "type": "view",
      "content": { "children": [
        { "id": "photo", "type": "view",
          "content": { "layout": { "constraints": [
            { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
            { "type": "trailing", "target": "superview" },
            { "type": "height", "target": "superview", "attribute": "width", "multiplier": 1.25 } ] } } },
        { "id": "info", "type": "stackView",
          "content": { "properties": { "axis": "vertical", "spacing": 6, "alignment": "fill" },
            "layout": { "constraints": [
              { "type": "top", "target": "photo", "attribute": "bottom", "constant": 12 },
              { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" } ] },
            "children": [
              { "id": "title", "type": "label", "content": { "properties": { "text": "{{item.title}}", "numberOfLines": 0 } } },
              { "id": "subtitle", "type": "label", "content": { "properties": { "text": "{{item.subtitle}}", "isHidden": "{{!item.subtitle}}" } } }
            ] } },
        { "id": "footer", "type": "view",
          "content": { "layout": { "height": 40, "constraints": [
            { "type": "top", "target": "info", "attribute": "bottom", "constant": 14, "op": ">=" },
            { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" },
            { "type": "bottom", "target": "superview" } ] } } }
      ] } }
    """

    private static var screenJSON: String {
        """
        { "type": "view", "id": "root",
          "content": {
            "variables": { "items": { "type": "array", "initialValue": [\(itemsJSON)] },
                           "intro": { "type": "array", "initialValue": [{"id":"intro"}] } },
            "layout": { "width": \(Int(width)), "height": \(Int(height)) },
            "children": [
              { "type": "collection", "id": "grid",
                "content": {
                  "properties": {
                    "sectionDefinitions": [
                      { "key": "intro", "data": "{{intro}}", "templateName": "intro" },
                      { "key": "items", "data": "{{items}}", "templateName": "card" } ],
                    "layout": { "type": "vertical", "contentInsets": { "top": 0, "bottom": 40 } },
                    "sectionLayouts": {
                      "intro": { "type": "vertical", "estimatedItemHeight": 120 },
                      "items": { "type": "grid", "columns": 2, "estimatedItemHeight": 470,
                                    "itemSpacing": 10, "lineSpacing": 28,
                                    "contentInsets": { "left": 10, "right": 10 } } } },
                  "layout": { "top": 0, "leading": 0, "width": \(Int(width)), "height": \(Int(height)) },
                  "templates": {
                    "intro": { "id": "intro", "type": "view", "content": { "layout": { "height": 90 } } },
                    "card": \(card) } } }
            ] } }
        """
    }

    private static func firstCollectionView(in view: UIView?) -> UICollectionView? {
        guard let view else { return nil }
        for sub in view.subviews {
            if let cv = sub as? UICollectionView { return cv }
            if let cv = firstCollectionView(in: sub) { return cv }
        }
        return nil
    }

    /// One display frame: layout, then let main-queue hops (bindings, the
    /// deferred remeasure) run, then layout again.
    private func frame(_ grid: UICollectionView, _ harness: RenderHarness) {
        grid.layoutIfNeeded()
        harness.drain(0.001)
        grid.layoutIfNeeded()
    }

    private func makeGrid(_ json: String = screenJSON) throws -> (RenderHarness, UICollectionView, CCollectionView) {
        let harness = RenderHarness(size: CGSize(width: Self.width, height: Self.height))
        try harness.render(json)
        harness.drain()
        let grid = try XCTUnwrap(Self.firstCollectionView(in: harness.superview))
        let host = try XCTUnwrap(harness.find(CCollectionView.self))
        for _ in 0..<3 { frame(grid, harness) }
        return (harness, grid, host)
    }

    private func maxOffset(_ grid: UICollectionView) -> CGFloat {
        grid.contentSize.height + grid.adjustedContentInset.bottom - grid.bounds.height
    }

    /// Frames of every item the layout knows of, by item.
    private func itemFrames(_ grid: UICollectionView) -> [Int: CGRect] {
        let section = grid.numberOfSections - 1
        var frames: [Int: CGRect] = [:]
        for i in 0..<grid.numberOfItems(inSection: section) {
            if let a = grid.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: i, section: section)) {
                frames[i] = a.frame
            }
        }
        return frames
    }

    func testScrollingTracksTheFingerAndHeightsSettleOnFirstMeasure() throws {
        try assertScrollTracksTheFinger(Self.screenJSON)
    }

    /// A plain vertical list (a feed: `layout.type: vertical`, no section
    /// layouts) of cards of different heights, `estimatedItemHeight` far off.
    func testPlainVerticalListTracksTheFinger() throws {
        try assertScrollTracksTheFinger(Self.listJSON)
    }

    private static var listJSON: String {
        """
        { "type": "view", "id": "root",
          "content": {
            "variables": { "items": { "type": "array", "initialValue": [\(itemsJSON)] } },
            "layout": { "width": \(Int(width)), "height": \(Int(height)) },
            "children": [
              { "type": "collection", "id": "list",
                "content": {
                  "properties": { "data": "{{items}}",
                    "layout": { "type": "vertical", "itemSpacing": 0, "estimatedItemHeight": 480,
                                "contentInsets": { "top": 12, "bottom": 40 } } },
                  "layout": { "top": 0, "leading": 0, "width": \(Int(width)), "height": \(Int(height)) },
                  "template": \(card) } }
            ] } }
        """
    }

    private func assertScrollTracksTheFinger(_ json: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let (harness, grid, host) = try makeGrid(json)
        let step: CGFloat = 37

        // Down to the bottom, a finger-sized step per frame.
        var y = grid.contentOffset.y
        var adjustmentsDown = 0
        while y < maxOffset(grid) {
            y = min(y + step, maxOffset(grid))
            grid.contentOffset.y = y
            frame(grid, harness)
            if abs(grid.contentOffset.y - y) > 0.5 { adjustmentsDown += 1; y = grid.contentOffset.y }
        }
        // Rest at the bottom: the content must not move after the scroll ends.
        let restingSize = grid.contentSize
        let restingOffset = grid.contentOffset
        for _ in 0..<5 { frame(grid, harness) }
        XCTAssertEqual(grid.contentSize.height, restingSize.height, accuracy: 0.5, "content size changed after the scroll ended")
        XCTAssertEqual(grid.contentOffset.y, restingOffset.y, accuracy: 0.5, "offset jumped after the scroll ended")

        // Every item has been measured now: frames are final.
        let settled = itemFrames(grid)
        let settledSize = grid.contentSize

        // Bottom overscroll (a pull up past the end, then the bounce back):
        // no new item comes in, so nothing may be invalidated.
        let invalidationsBefore = host.layoutInvalidationCount
        let bottom = maxOffset(grid)
        for pull in stride(from: CGFloat(10), through: 120, by: 10) {
            grid.contentOffset.y = bottom + pull
            frame(grid, harness)
        }
        for pull in stride(from: CGFloat(120), through: 0, by: -10) {
            grid.contentOffset.y = bottom + pull
            frame(grid, harness)
        }
        XCTAssertEqual(host.layoutInvalidationCount, invalidationsBefore, "bottom overscroll invalidated the layout")

        // Back up to the top: reused cells meet items measured before.
        var adjustmentsUp = 0
        y = grid.contentOffset.y
        let top = -grid.adjustedContentInset.top
        while y > top {
            y = max(y - step, top)
            grid.contentOffset.y = y
            frame(grid, harness)
            if abs(grid.contentOffset.y - y) > 0.5 { adjustmentsUp += 1; y = grid.contentOffset.y }
        }
        XCTAssertEqual(host.layoutInvalidationCount, invalidationsBefore, "scrolling back over measured items invalidated the layout")
        XCTAssertEqual(adjustmentsDown, 0, "UIKit moved the offset under the finger while scrolling down")
        XCTAssertEqual(adjustmentsUp, 0, "UIKit moved the offset under the finger while scrolling up")
        XCTAssertEqual(grid.contentSize.height, settledSize.height, accuracy: 0.5, "content size changed on the way back up")
        let after = itemFrames(grid)
        for (i, f) in settled {
            guard let g = after[i] else { continue }
            XCTAssertEqual(g.height, f.height, accuracy: 0.5, "item \(i) changed height after its first measure")
            XCTAssertEqual(g.minY, f.minY, accuracy: 0.5, "item \(i) moved after its first measure")
        }
    }

    /// Rows still take their tallest item, and every item is as tall as its row.
    func testRowsAreEqualHeightAfterAFullScroll() throws {
        let (harness, grid, _) = try makeGrid()
        var y = grid.contentOffset.y
        while y < maxOffset(grid) {
            y = min(y + 200, maxOffset(grid))
            grid.contentOffset.y = y
            frame(grid, harness)
        }
        grid.contentOffset.y = -grid.adjustedContentInset.top
        frame(grid, harness)
        let frames = itemFrames(grid)
        for row in stride(from: 0, to: Self.count, by: 2) {
            guard let a = frames[row], let b = frames[row + 1] else { continue }
            XCTAssertEqual(a.height, b.height, accuracy: 0.5, "row \(row / 2) items differ in height")
            XCTAssertEqual(a.minY, b.minY, accuracy: 0.5, "row \(row / 2) items differ in top")
            XCTAssertLessThan(a.height, 470, "row \(row / 2) kept the estimated height")
        }
    }
}
