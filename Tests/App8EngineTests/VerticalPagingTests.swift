//
//  VerticalPagingTests.swift
//  App8EngineTests
//
//  A vertical feed: `layout.type: vertical` with `pagingStyle: paging` and
//  `itemHeight: "fill"`. Every item is the collection's frame, the page
//  starts at `currentPageVariable`, a settled scroll writes the variable and a
//  write scrolls to that page.
//

import Testing
import UIKit
@testable import App8Engine

@MainActor
@Suite("Vertical paging collection")
struct VerticalPagingTests {

    private static func feedJSON(spacing: Int = 0, insets: String = "") -> String {
        let items = (0..<20).map { #"{ "n": \#($0 + 1) }"# }.joined(separator: ", ")
        return """
        {
          "type": "view", "id": "feedRoot",
          "content": {
            "properties": {},
            "variables": { "posts": { "type": "array", "initialValue": [\(items)] } },
            "layout": { "width": 390, "height": 600 },
            "children": [{
              "type": "collection", "id": "feed",
              "content": {
                "properties": {
                  "data": "{{posts}}",
                  "layout": { "type": "vertical", "pagingStyle": "paging", "itemHeight": "fill", "itemSpacing": \(spacing), "currentPageVariable": "feedPage"\(insets) }
                },
                "layout": { "top": 0, "leading": 0, "width": 390, "height": 600 },
                "template": { "id": "feedCell", "type": "view", "content": { "children": [
                  { "type": "label", "id": "feedNumber", "content": { "properties": { "text": "{{item.n}}" }, "layout": { "constraints": [ { "type": "centerX", "target": "superview", "constant": 0 }, { "type": "centerY", "target": "superview", "constant": 0 } ] } } }
                ] } }
              }
            }]
          }
        }
        """
    }

    private static func render(_ json: String, harness: RenderHarness, store: VariableStoreProtocol) throws -> UICollectionView {
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(json.utf8))
        harness.service.renderComponent(component, superview: harness.superview, parentPath: nil, parentVariableStore: store)
        harness.superview.layoutIfNeeded()
        return try #require(collectionViews(in: harness.superview).first)
    }

    private static func collectionViews(in view: UIView) -> [UICollectionView] {
        if let cv = view as? UICollectionView { return [cv] }
        return view.subviews.flatMap { collectionViews(in: $0) }
    }

    private static func labels(in view: UIView) -> [UILabel] {
        ((view as? UILabel).map { [$0] } ?? []) + view.subviews.flatMap { labels(in: $0) }
    }

    private static func settle() async throws {
        for _ in 0..<4 {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    @Test func pagesAreTheFrameAndStartAtTheVariable() async throws {
        let harness = RenderHarness()
        let store = VariableStore()
        try store.defineVariable(name: "feedPage", definition: VariableDefinition(type: .number, initialValue: 3))
        let cv = try Self.render(Self.feedJSON(), harness: harness, store: store)
        try await Self.settle()
        cv.layoutIfNeeded()

        #expect(cv.numberOfItems(inSection: 0) == 20)
        #expect(cv.isPagingEnabled)
        #expect(cv.contentInsetAdjustmentBehavior == .never)
        let attributes = try #require(cv.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        #expect(attributes.frame.height == 600)
        #expect(abs(cv.contentOffset.y - 3 * 600) < 0.5)
        #expect(!cv.visibleCells.isEmpty)
        // The template fills the page: its centered label sits mid-page.
        let cell = try #require(cv.cellForItem(at: IndexPath(item: 3, section: 0)))
        cell.layoutIfNeeded()
        let label = try #require(Self.labels(in: cell).first { $0.text == "4" })
        let center = label.convert(CGPoint(x: label.bounds.midX, y: label.bounds.midY), to: cell)
        #expect(abs(center.y - 300) < 2)
        #expect(abs(center.x - 195) < 2)
    }

    @Test func scrollWritesTheVariableAndAWriteScrolls() async throws {
        let harness = RenderHarness()
        let store = VariableStore()
        try store.defineVariable(name: "feedPage", definition: VariableDefinition(type: .number, initialValue: 0))
        let cv = try Self.render(Self.feedJSON(), harness: harness, store: store)
        try await Self.settle()

        // A settled swipe to page 2 writes it.
        cv.setContentOffset(CGPoint(x: 0, y: 600), animated: false)
        cv.setContentOffset(CGPoint(x: 0, y: 1200), animated: false)
        try await Self.settle()
        #expect(store.getValue(name: "feedPage") as? Int == 2)

        // A write from elsewhere scrolls there (off screen: without
        // animation; on screen the same offset is animated).
        harness.superview.removeFromSuperview()
        try store.setValue(name: "feedPage", value: 9)
        cv.layoutIfNeeded()
        #expect(abs(cv.contentOffset.y - 9 * 600) < 1)
        #expect(store.getValue(name: "feedPage") as? Int == 9)
    }

    @Test func aFlickTurnsOnePageWhenPagesAreNotTheFrame() async throws {
        let harness = RenderHarness()
        let store = VariableStore()
        try store.defineVariable(name: "feedPage", definition: VariableDefinition(type: .number, initialValue: 0))
        // 10 pt spacing: a page is 610 pt, so UIKit's frame paging does not apply.
        let cv = try Self.render(Self.feedJSON(spacing: 10), harness: harness, store: store)
        try await Self.settle()
        #expect(!cv.isPagingEnabled)
        let delegate = try #require(cv.delegate)

        delegate.scrollViewWillBeginDragging?(cv)
        cv.contentOffset = CGPoint(x: 0, y: 100)
        var target = CGPoint(x: 0, y: 5000) // a hard flick UIKit would carry far
        delegate.scrollViewWillEndDragging?(cv, withVelocity: CGPoint(x: 0, y: 4), targetContentOffset: &target)
        #expect(abs(target.y - 610) < 0.5)

        // A slow release under half a page springs back.
        delegate.scrollViewWillBeginDragging?(cv)
        cv.contentOffset = CGPoint(x: 0, y: 200)
        target = CGPoint(x: 0, y: 200)
        delegate.scrollViewWillEndDragging?(cv, withVelocity: .zero, targetContentOffset: &target)
        #expect(abs(target.y) < 0.5)
    }
}
