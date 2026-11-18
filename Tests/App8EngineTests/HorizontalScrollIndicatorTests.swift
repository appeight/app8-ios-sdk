//
//  HorizontalScrollIndicatorTests.swift
//  App8EngineTests
//
//  Horizontal collections (carousels, chip rows) and horizontal sections show
//  no scroll indicator unless `showsScrollIndicator: true`; vertical lists
//  keep theirs by default (collections.md). Horizontal sections scroll in the
//  scroll views UIKit embeds for orthogonal sections, which show an indicator
//  by default, so those are checked too.
//

import XCTest
@testable import App8Engine

@MainActor
final class HorizontalScrollIndicatorTests: XCTestCase {

    private static let items = (1...14).map { #"{"n":\#($0),"s":"\#($0 <= 7 ? "first" : "second")"}"# }.joined(separator: ",")

    private static func collection(_ id: String, top: Int, height: Int, properties: String) -> String {
        """
        { "type": "collection", "id": "\(id)",
          "content": {
            "properties": { "data": "{{items}}", \(properties) },
            "layout": { "top": \(top), "leading": 0, "width": 390, "height": \(height) },
            "template": { "id": "tile-\(id)", "type": "view", "content": { "layout": { "width": 110, "height": 80 } } } } }
        """
    }

    private static let row = #""type": "horizontal", "itemWidth": 110, "itemHeight": 80, "itemSpacing": 10"#

    private static var screenJSON: String {
        """
        { "type": "view", "id": "root",
          "content": {
            "variables": { "items": { "type": "array", "initialValue": [\(items)] } },
            "layout": { "width": 390, "height": 800 },
            "children": [
              \(collection("rowDefault", top: 0, height: 80, properties: #""layout": { \#(row) }"#)),
              \(collection("rowShown", top: 100, height: 80, properties: #""layout": { \#(row), "showsScrollIndicator": true }"#)),
              \(collection("mixed", top: 200, height: 200, properties: #""groupBy": "item.s", "layout": { "type": "vertical", "itemSpacing": 12 }, "defaultSectionLayout": { \#(row) }, "sectionLayouts": { "second": { \#(row), "showsScrollIndicator": true } }"#)),
              \(collection("list", top: 420, height: 200, properties: #""layout": { "type": "vertical" }"#))
            ] } }
        """
    }

    private func collectionViews(in view: UIView) -> [UICollectionView] {
        view.subviews.flatMap { sub -> [UICollectionView] in
            (sub as? UICollectionView).map { [$0] } ?? collectionViews(in: sub)
        }
    }

    /// The orthogonal scrollers of `cv` by the section of the first cell they hold.
    private func orthogonalScrollers(_ cv: UICollectionView) -> [Int: UIScrollView] {
        var out: [Int: UIScrollView] = [:]
        for case let s as UIScrollView in cv.subviews {
            if let cell = s.subviews.compactMap({ $0 as? UICollectionViewCell }).first,
               let section = cv.indexPath(for: cell)?.section {
                out[section] = s
            }
        }
        return out
    }

    func testHorizontalCollectionsHideTheIndicatorUnlessAsked() throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 800))
        try harness.render(Self.screenJSON)
        harness.drain()
        let cvs = collectionViews(in: try XCTUnwrap(harness.superview)).sorted { $0.convert($0.bounds, to: nil).minY < $1.convert($1.bounds, to: nil).minY }
        XCTAssertEqual(cvs.count, 4)
        for cv in cvs { cv.layoutIfNeeded() }
        harness.drain(0.05)
        for cv in cvs { cv.superview?.setNeedsLayout(); cv.superview?.layoutIfNeeded() }

        let (rowDefault, rowShown, mixed, list) = (cvs[0], cvs[1], cvs[2], cvs[3])
        // A plain horizontal collection: its own indicator and its section's scroller.
        XCTAssertFalse(rowDefault.showsHorizontalScrollIndicator)
        let defaultScrollers = orthogonalScrollers(rowDefault)
        XCTAssertFalse(defaultScrollers.isEmpty, "a horizontal collection scrolls in an orthogonal section")
        for s in defaultScrollers.values { XCTAssertFalse(s.showsHorizontalScrollIndicator, "unset: no indicator") }

        XCTAssertTrue(rowShown.showsHorizontalScrollIndicator)
        for s in orthogonalScrollers(rowShown).values { XCTAssertTrue(s.showsHorizontalScrollIndicator, "true: indicator") }

        // A vertical list of horizontal sections: per section.
        let sections = orthogonalScrollers(mixed)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0]?.showsHorizontalScrollIndicator, false, "section 'first', unset")
        XCTAssertEqual(sections[1]?.showsHorizontalScrollIndicator, true, "section 'second', true")

        // A vertical list keeps its indicator by default.
        XCTAssertTrue(list.showsVerticalScrollIndicator)
    }
}
