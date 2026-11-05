//
//  NestedScrollStateTests.swift
//  App8EngineTests
//
//  Nested scroll offset memory for reused collection cells (horizontal shelves
//  inside a vertical collection keep their offset across cell reuse).
//

import XCTest
import UIKit
@testable import App8Engine

@MainActor
final class NestedScrollStateTests: XCTestCase {

    // MARK: - Cache

    func testSaveAndRestoreByItemAndNestedId() {
        var cache = NestedScrollOffsetCache()
        cache.save(CGPoint(x: 320, y: 0), itemKey: "/id:skincare", nestedId: "productRow", generation: cache.generation)
        cache.save(CGPoint(x: 80, y: 0), itemKey: "/id:bodycare", nestedId: "productRow", generation: cache.generation)

        XCTAssertEqual(cache.offset(itemKey: "/id:skincare", nestedId: "productRow"), CGPoint(x: 320, y: 0))
        XCTAssertEqual(cache.offset(itemKey: "/id:bodycare", nestedId: "productRow"), CGPoint(x: 80, y: 0))
        XCTAssertNil(cache.offset(itemKey: "/id:skincare", nestedId: "otherRow"))
        XCTAssertNil(cache.offset(itemKey: "/id:new", nestedId: "productRow"))
    }

    func testResetDropsOffsetsAndRejectsStaleSaves() {
        var cache = NestedScrollOffsetCache()
        let oldGeneration = cache.generation
        cache.save(CGPoint(x: 100, y: 0), itemKey: "/#0.0", nestedId: "productRow", generation: oldGeneration)

        cache.reset()
        XCTAssertNil(cache.offset(itemKey: "/#0.0", nestedId: "productRow"))

        // A cell configured for the previous data set ends display after the reload:
        // its offset must not land on the new item at the same index path.
        cache.save(CGPoint(x: 100, y: 0), itemKey: "/#0.0", nestedId: "productRow", generation: oldGeneration)
        XCTAssertNil(cache.offset(itemKey: "/#0.0", nestedId: "productRow"))

        cache.save(CGPoint(x: 50, y: 0), itemKey: "/#0.0", nestedId: "productRow", generation: cache.generation)
        XCTAssertEqual(cache.offset(itemKey: "/#0.0", nestedId: "productRow"), CGPoint(x: 50, y: 0))
    }

    // MARK: - Clamp

    func testClampKeepsOffsetInsideScrollableRange() {
        let insets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        let content = CGSize(width: 1000, height: 430)
        let bounds = CGSize(width: 400, height: 430)

        // Content shrank since the offset was saved → clamp to the new max (1000 + 10 - 400).
        XCTAssertEqual(
            NestedScrollOffsetCache.clamp(CGPoint(x: 5000, y: 0), contentSize: content, boundsSize: bounds, insets: insets),
            CGPoint(x: 610, y: 0)
        )
        XCTAssertEqual(
            NestedScrollOffsetCache.clamp(CGPoint(x: -500, y: -20), contentSize: content, boundsSize: bounds, insets: insets),
            CGPoint(x: -10, y: 0)
        )
        XCTAssertEqual(
            NestedScrollOffsetCache.clamp(CGPoint(x: 300, y: 0), contentSize: content, boundsSize: bounds, insets: insets),
            CGPoint(x: 300, y: 0)
        )
        // Content narrower than bounds → only the rest position is valid.
        XCTAssertEqual(
            NestedScrollOffsetCache.clamp(CGPoint(x: 300, y: 0), contentSize: CGSize(width: 200, height: 430), boundsSize: bounds, insets: insets),
            CGPoint(x: -10, y: 0)
        )
    }

    func testScrollViewSetClampedContentOffset() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 430))
        scrollView.contentSize = CGSize(width: 1000, height: 430)
        scrollView.app8SetClampedContentOffset(CGPoint(x: 250, y: 0))
        XCTAssertEqual(scrollView.contentOffset, CGPoint(x: 250, y: 0))
        scrollView.app8SetClampedContentOffset(CGPoint(x: 9999, y: 0))
        XCTAssertEqual(scrollView.contentOffset, CGPoint(x: 600, y: 0))
        scrollView.app8SetClampedContentOffset(scrollView.app8RestOffset)
        XCTAssertEqual(scrollView.contentOffset, .zero)
    }

    // MARK: - Finding nested scrollables

    private final class FakeShelf: UIView, NestedScrollStateRestorable {
        let id: String
        var offset: CGPoint = .zero
        var restored: [CGPoint?] = []
        init(id: String) { self.id = id; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        var nestedScrollStateId: String? { id }
        var nestedScrollOffset: CGPoint? { offset }
        func restoreNestedScrollOffset(_ offset: CGPoint?) { restored.append(offset) }
    }

    func testRestorablesFindsNestedScrollablesWithoutDescendingIntoThem() {
        let root = UIView()
        let wrapper = UIView()
        let shelf = FakeShelf(id: "productRow")
        let innerShelf = FakeShelf(id: "innerRow")   // inside shelf's own cells — not ours
        shelf.addSubview(innerShelf)
        wrapper.addSubview(shelf)
        root.addSubview(UIView())
        root.addSubview(wrapper)

        let found = NestedScrollOffsetCache.restorables(in: root)
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(found.first === shelf)
    }

    // MARK: - Item identity

    func testItemScrollKeyPrefersItemIdOverIndexPath() {
        let withId = CCollectionViewModel.ItemWrapper(
            index: 3,
            data: AnyCodableValue(value: ["id": "skincare", "title": "Skincare"]),
            templateKey: nil
        )
        let withoutId = CCollectionViewModel.ItemWrapper(
            index: 3,
            data: AnyCodableValue(value: ["title": "Skincare"]),
            templateKey: nil
        )
        XCTAssertEqual(
            CCollectionView.itemScrollKey(withId, sectionKey: "", indexPath: IndexPath(item: 3, section: 0)),
            "/id:skincare"
        )
        XCTAssertEqual(
            CCollectionView.itemScrollKey(withoutId, sectionKey: "", indexPath: IndexPath(item: 3, section: 0)),
            "/#0.3"
        )
    }

    // MARK: - End to end: shelves in a reused vertical list (Facetheory shop shape)

    private func shopJSON() -> String {
        let sections = (0..<20).map { s -> String in
            let products = (0..<10).map { p in #"{"id":"p\#(s)-\#(p)","name":"P\#(p)"}"# }.joined(separator: ",")
            return #"{"id":"s\#(s)","title":"Section \#(s)","products":[\#(products)]}"#
        }.joined(separator: ",")
        return """
        {
          "type": "view", "id": "root",
          "content": {
            "properties": {},
            "variables": { "sections": { "type": "array", "initialValue": [\(sections)] } },
            "layout": { "width": 390, "height": 400 },
            "children": [
              { "type": "collection", "id": "sectionList",
                "content": {
                  "properties": { "data": "{{sections}}", "layout": { "type": "vertical", "itemSpacing": 10, "estimatedItemHeight": 200 } },
                  "layout": { "top": 0, "leading": 0, "width": 390, "height": 400 },
                  "template": { "id": "shopSection", "type": "view",
                    "content": { "layout": { "height": 200 },
                      "children": [
                        { "id": "productRow", "type": "collection",
                          "content": {
                            "properties": { "data": "{{item.products}}",
                              "layout": { "type": "horizontal", "itemWidth": 240, "itemHeight": 180, "itemSpacing": 10 },
                              "template": { "id": "card", "type": "label", "content": { "properties": { "text": "{{item.name}}" } } } },
                            "layout": { "height": 180, "constraints": [
                              { "type": "top", "target": "superview" },
                              { "type": "leading", "target": "superview" },
                              { "type": "trailing", "target": "superview" } ] }
                          } }
                      ] } }
                } }
            ]
          }
        }
        """
    }

    private func shelfScroller(in outer: UICollectionView, item: Int) -> UIScrollView? {
        guard let cell = outer.cellForItem(at: IndexPath(item: item, section: 0)) else { return nil }
        let inner = NestedScrollOffsetCache.restorables(in: cell.contentView).first as? CCollectionView
        guard let innerCV = inner?.subviews.first?.subviews.compactMap({ $0 as? UICollectionView }).first
            ?? Self.firstCollectionView(in: inner) else { return nil }
        cell.layoutIfNeeded()
        innerCV.layoutIfNeeded()
        return innerCV.subviews.compactMap { $0 as? UIScrollView }.first
    }

    private static func firstCollectionView(in view: UIView?) -> UICollectionView? {
        guard let view else { return nil }
        for sub in view.subviews {
            if let cv = sub as? UICollectionView { return cv }
            if let cv = firstCollectionView(in: sub) { return cv }
        }
        return nil
    }

    func testShelfOffsetSurvivesOuterCellReuse() throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 400), inWindow: false)
        try harness.render(shopJSON())
        harness.drain()

        let outer = try XCTUnwrap(Self.firstCollectionView(in: harness.superview))
        outer.layoutIfNeeded()
        harness.drain()

        let first = try XCTUnwrap(shelfScroller(in: outer, item: 0), "orthogonal shelf scroller for item 0")
        first.setContentOffset(CGPoint(x: 300, y: 0), animated: false)
        let firstCell = try XCTUnwrap(outer.cellForItem(at: IndexPath(item: 0, section: 0)))

        // Scroll down a step at a time (as a user would) so cells are recycled
        // across sections, then back up.
        let maxY = outer.contentSize.height - outer.bounds.height
        var sawFirstCellReused = false
        func scroll(to y: CGFloat) {
            outer.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            outer.layoutIfNeeded()
            harness.drain(0.02)
            for indexPath in outer.indexPathsForVisibleItems where indexPath.item != 0 {
                if outer.cellForItem(at: indexPath) === firstCell { sawFirstCellReused = true }
                guard let scroller = shelfScroller(in: outer, item: indexPath.item) else { continue }
                XCTAssertEqual(scroller.contentOffset.x, -scroller.adjustedContentInset.left, accuracy: 0.5,
                               "item \(indexPath.item) must not inherit another section's shelf offset")
            }
        }
        var y: CGFloat = 0
        while y < maxY { y = min(maxY, y + 150); scroll(to: y) }
        while y > 0 { y = max(0, y - 150); scroll(to: y) }

        XCTAssertTrue(sawFirstCellReused, "test setup must actually recycle item 0's cell")

        let restored = try XCTUnwrap(shelfScroller(in: outer, item: 0))
        XCTAssertEqual(restored.contentOffset.x, 300, accuracy: 0.5, "shelf offset must be restored for its section")
    }
}
