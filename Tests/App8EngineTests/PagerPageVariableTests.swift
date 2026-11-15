//
//  PagerPageVariableTests.swift
//  App8EngineTests
//
//  Two native pagers bound to one `currentPageVariable` (a product gallery and
//  a second gallery with fewer images, e.g. another product screen further
//  down the navigation stack). A pager that cannot reach the shared page must
//  follow as far as it can without writing its own page back, otherwise the
//  pagers drag the variable (and each other) back and forth.
//

import Testing
import UIKit
@testable import App8Engine

@MainActor
@Suite("Pager currentPageVariable")
struct PagerPageVariableTests {

    private static func pagerJSON(id: String, pages: Int) -> String {
        let items = (0..<pages).map { #"{ "id": "p\#($0)" }"# }.joined(separator: ", ")
        return """
        {
          "type": "view", "id": "\(id)Root",
          "content": {
            "properties": {},
            "variables": { "pages": { "type": "array", "initialValue": [\(items)] } },
            "layout": { "width": 390, "height": 500 },
            "children": [{
              "type": "collection", "id": "\(id)",
              "content": {
                "properties": {
                  "data": "{{pages}}",
                  "layout": { "type": "horizontal", "itemHeight": 500, "pagingStyle": "paging", "currentPageVariable": "galleryPage" }
                },
                "layout": { "top": 0, "leading": 0, "width": 390, "height": 500 },
                "template": { "id": "\(id)Page", "type": "view", "content": { "layout": { "height": 10 } } }
              }
            }]
          }
        }
        """
    }

    private static func render(_ json: String, service: App8Service, store: VariableStoreProtocol, in superview: UIView) throws {
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(json.utf8))
        service.renderComponent(component, superview: superview, parentPath: nil, parentVariableStore: store)
        superview.layoutIfNeeded()
    }

    private static func collectionViews(in view: UIView) -> [UICollectionView] {
        if let cv = view as? UICollectionView { return [cv] }
        return view.subviews.flatMap { collectionViews(in: $0) }
    }

    private static func page(of cv: UICollectionView) -> Int {
        Int((cv.contentOffset.x / max(1, cv.bounds.width)).rounded())
    }

    @Test func pagerThatCannotReachThePageDoesNotWriteItBack() async throws {
        let harness = RenderHarness()
        let store = VariableStore()
        try store.defineVariable(name: "galleryPage", definition: VariableDefinition(type: .number, initialValue: 0))

        var writes: [Int] = []
        let counter = store.anyVariableChanged
            .filter { $0 == "galleryPage" }
            .sink { _ in
                if let value = store.getValue(name: "galleryPage") as? Int { writes.append(value) }
            }
        defer { counter.cancel() }

        // The visible pager has 5 pages; the other one (off screen, as on a
        // screen further down the stack) has only 2.
        try Self.render(Self.pagerJSON(id: "visiblePager", pages: 5), service: harness.service, store: store, in: harness.superview)
        let offscreen = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        try Self.render(Self.pagerJSON(id: "hiddenPager", pages: 2), service: harness.service, store: store, in: offscreen)
        try await Task.sleep(nanoseconds: 400_000_000)

        let visible = try #require(Self.collectionViews(in: harness.superview).first)
        let hidden = try #require(Self.collectionViews(in: offscreen).first)
        visible.layoutIfNeeded()
        hidden.layoutIfNeeded()
        #expect(visible.numberOfItems(inSection: 0) == 5)
        #expect(hidden.numberOfItems(inSection: 0) == 2)

        // The user pages the visible pager to page 3.
        writes.removeAll()
        visible.contentOffset = CGPoint(x: visible.bounds.width * 3, y: 0)

        #expect(store.getValue(name: "galleryPage") as? Int == 3)
        #expect(writes == [3])
        // The short pager follows as far as it can and stays there.
        #expect(Self.page(of: hidden) == 1)
        #expect(Self.page(of: visible) == 3)

        // Paging on: the hidden pager (sitting on its last page) keeps following,
        // and every write comes from the pager the user moved.
        visible.contentOffset = CGPoint(x: visible.bounds.width * 4, y: 0)
        visible.contentOffset = CGPoint(x: 0, y: 0)
        #expect(writes == [3, 4, 0])
        #expect(Self.page(of: hidden) == 0)

        // A write from elsewhere (an action) moves both, nobody writes back.
        writes.removeAll()
        try store.setValue(name: "galleryPage", value: 1)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        #expect(writes == [1])
        #expect(Self.page(of: hidden) == 1)

        // The hidden pager's own page changes (the user swipes it once its
        // screen is back): that is a real change and is written.
        hidden.contentOffset = .zero
        #expect(store.getValue(name: "galleryPage") as? Int == 0)
    }
}
