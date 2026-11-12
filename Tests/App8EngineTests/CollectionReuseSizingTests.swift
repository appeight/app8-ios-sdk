//
//  CollectionReuseSizingTests.swift
//  App8EngineTests
//
//  A reused collection cell must be measured at its NEW item's size. Item
//  templates with `layout.height: "{{item.height}}"` (the Facetheory shop:
//  a 36pt strip, a 500pt hero, product rows…) used to keep the previous
//  item's height after reuse, because the dimension expression re-resolved
//  on a later main-queue hop, after the collection had measured the cell.
//  The short strip then sat in a tall cell and pushed the next section down.
//

import XCTest
@testable import App8Engine

@MainActor
final class CollectionReuseSizingTests: XCTestCase {

    private static let heights: [Int] = (0..<24).map { [36, 500, 260, 120, 420][$0 % 5] }

    private func listJSON() -> String {
        let items = Self.heights.enumerated()
            .map { #"{"id":"s\#($0.offset)","height":\#($0.element),"kind":"\#($0.element == 36 ? "strip" : "block")"}"# }
            .joined(separator: ",")
        return """
        {
          "type": "view", "id": "root",
          "content": {
            "properties": {},
            "variables": { "sections": { "type": "array", "initialValue": [\(items)] } },
            "layout": { "width": 390, "height": 700 },
            "children": [
              { "type": "collection", "id": "sectionList",
                "content": {
                  "properties": { "data": "{{sections}}", "layout": { "type": "vertical", "itemSpacing": 10, "estimatedItemHeight": 480 } },
                  "layout": { "top": 0, "leading": 0, "width": 390, "height": 700 },
                  "template": { "id": "section", "type": "view",
                    "content": { "layout": { "height": "{{item.height}}" },
                      "children": [
                        { "id": "strip", "type": "view",
                          "content": { "properties": { "isHidden": "{{item.kind != 'strip'}}" },
                            "layout": { "constraints": [
                              { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
                              { "type": "trailing", "target": "superview" }, { "type": "bottom", "target": "superview" } ] } } },
                        { "id": "block", "type": "view",
                          "content": { "properties": { "isHidden": "{{item.kind == 'strip'}}" },
                            "layout": { "constraints": [
                              { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
                              { "type": "trailing", "target": "superview" }, { "type": "bottom", "target": "superview" } ] } } }
                      ] } }
                } }
            ]
          }
        }
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

    private static func firstView(withId id: String, in view: UIView) -> UIView? {
        if let c = view as? CView, c.layoutModeId == id { return c }
        for sub in view.subviews { if let v = firstView(withId: id, in: sub) { return v } }
        return nil
    }

    func testReusedCellsTakeTheNewItemsHeightAndVisibility() throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 700), inWindow: false)
        try harness.render(listJSON())
        harness.drain()

        let list = try XCTUnwrap(Self.firstCollectionView(in: harness.superview))
        list.layoutIfNeeded()
        harness.drain()

        var reusedCells = Set<ObjectIdentifier>()
        var seen = [ObjectIdentifier: Int]()

        func check(_ context: String) {
            for indexPath in list.indexPathsForVisibleItems.sorted() {
                guard let cell = list.cellForItem(at: indexPath) else { continue }
                let key = ObjectIdentifier(cell)
                if let previous = seen[key], previous != indexPath.item { reusedCells.insert(key) }
                seen[key] = indexPath.item

                let expected = CGFloat(Self.heights[indexPath.item])
                XCTAssertEqual(cell.frame.height, expected, accuracy: 0.5,
                               "\(context): item \(indexPath.item) cell keeps another item's height")
                let isStrip = Self.heights[indexPath.item] == 36
                if let strip = Self.firstView(withId: "strip", in: cell.contentView),
                   let block = Self.firstView(withId: "block", in: cell.contentView) {
                    XCTAssertEqual(strip.isHidden, !isStrip, "\(context): item \(indexPath.item) strip visibility")
                    XCTAssertEqual(block.isHidden, isStrip, "\(context): item \(indexPath.item) block visibility")
                }
                // Consecutive items stack with only the item spacing between them.
                let next = IndexPath(item: indexPath.item + 1, section: 0)
                if let nextCell = list.cellForItem(at: next) {
                    XCTAssertEqual(nextCell.frame.minY - cell.frame.maxY, 10, accuracy: 0.5,
                                   "\(context): gap after item \(indexPath.item)")
                }
            }
        }

        // Scroll down and back up a step at a time, as a user would, so cells
        // are recycled between items of different heights.
        let step: CGFloat = 220
        var y: CGFloat = 0
        func scroll(to newY: CGFloat) {
            y = newY
            list.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            list.layoutIfNeeded()
            check("y=\(Int(y))")
            harness.drain(0.02)
        }
        for _ in 0..<2 {
            while y < list.contentSize.height - list.bounds.height { scroll(to: min(list.contentSize.height - list.bounds.height, y + step)) }
            while y > 0 { scroll(to: max(0, y - step)) }
        }

        XCTAssertFalse(reusedCells.isEmpty, "test setup must actually recycle cells between items")
    }
}
