//
//  SelfSizingCollectionRestTests.swift
//  App8EngineTests
//

import XCTest
import UIKit
@testable import App8Engine

/// Non-scrolling self-sizing collections (`scrollEnabled: false`, no item
/// height: the collection is as tall as its measured cells) in the vertical
/// stack of a long scroll page, filled when the data arrives (a report's
/// lists). The page must reach its final height before a scroll comes to rest
/// at its end, and keep it: a collection whose cells are measured again later
/// changes the content height and UIKit moves a scroll resting at its end
/// (scroll-view.md, "The end of the scroll").
@MainActor
final class SelfSizingCollectionRestTests: XCTestCase {

    static let body = "A paragraph in a row, long enough to wrap onto two or three lines next to its thumbnail."

    static func collection(_ id: String, rows: Int) -> String {
        """
        { "type": "collection", "id": "\(id)",
          "content": {
            "properties": {
              "data": "{{length(items) > 0 ? slice(items, 0, \(rows)) : []}}",
              "layout": { "type": "vertical", "itemSpacing": 24, "scrollEnabled": false, "showsScrollIndicator": false }
            },
            "layout": { "constraints": [
              { "type": "top", "target": "superview" },
              { "type": "leading", "target": "superview", "constant": 20 },
              { "type": "trailing", "target": "superview", "constant": -20 },
              { "type": "bottom", "target": "superview" }
            ] },
            "template": { "id": "\(id)Row", "type": "view", "content": { "children": [
              { "id": "\(id)Thumb", "type": "view",
                "content": { "style": { "backgroundColor": "#CCCCCC" },
                             "layout": { "width": 72, "height": 72, "constraints": [
                               { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
                               { "type": "bottom", "target": "superview", "op": "<=" } ] } } },
              { "id": "\(id)Texts", "type": "stackView",
                "content": {
                  "properties": { "axis": "vertical", "spacing": 0, "alignment": "fill" },
                  "layout": { "constraints": [
                    { "type": "top", "target": "superview", "constant": 2 },
                    { "type": "leading", "target": "sibling(\(id)Thumb)", "attribute": "trailing", "constant": 16 },
                    { "type": "trailing", "target": "superview" },
                    { "type": "bottom", "target": "superview" } ] },
                  "children": [
                    { "id": "\(id)Zone", "type": "label", "content": { "properties": { "text": "{{uppercase(item.zone)}}" }, "style": { "text": { "fontSize": 11 } } } },
                    { "id": "\(id)Gap", "type": "view", "content": { "layout": { "height": 4 } } },
                    { "id": "\(id)Title", "type": "label", "content": { "properties": { "text": "{{item.title}}" }, "style": { "text": { "fontSize": 17, "numberOfLines": 0 } } } },
                    { "id": "\(id)Text", "type": "label", "content": { "properties": { "text": "{{item.text}}" }, "style": { "text": { "fontSize": 15, "numberOfLines": 0 } } } }
                  ] } }
            ] } }
          } }
        """
    }

    static func screenJSON(collections: Int) -> String {
        func heading(_ i: Int) -> String {
            #"{ "type": "label", "id": "head\#(i)", "content": { "properties": { "text": "Section \#(i)", "numberOfLines": 0 }, "style": { "text": { "fontSize": 22 } }, "layout": { "constraints": [ { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview", "constant": 20 }, { "type": "trailing", "target": "superview", "constant": -20 }, { "type": "bottom", "target": "superview" } ] } } }"#
        }
        var children = [##"{ "type": "view", "id": "hero", "content": { "style": { "backgroundColor": "#888888" }, "layout": { "height": 420 } } }"##]
        for i in 0..<max(collections, 1) {
            children.append(heading(i))
            if i < collections { children.append(collection("list\(i)", rows: 2 + i % 3)) }
        }
        children.append(#"{ "type": "view", "id": "endSpace", "content": { "layout": { "height": 48 } } }"#)
        return """
        {
          "type": "scrollView", "id": "scroll",
          "content": {
            "variables": {
              "tick": { "type": "number", "initialValue": 0 },
              "items": { "type": "array", "initialValue": [] }
            },
            "properties": { "direction": "vertical", "contentInsetAdjustment": "bottom" },
            "layout": { "constraints": [
              { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
              { "type": "trailing", "target": "superview" }, { "type": "bottom", "target": "superview" } ] },
            "children": [
              { "type": "stackView", "id": "page",
                "content": {
                  "properties": { "axis": "vertical", "spacing": 16, "alignment": "fill" },
                  "layout": { "constraints": [
                    { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
                    { "type": "trailing", "target": "superview" }, { "type": "bottom", "target": "superview" } ] },
                  "children": [ \(children.joined(separator: ",\n")) ]
                } }
            ]
          }
        }
        """
    }

    static let items: [[String: Any]] = (0..<4).map {
        ["zone": "Zone \($0)", "title": "Title \($0) that is a little long", "text": body]
    }

    private func settle(_ h: RenderHarness) {
        h.drain(0.3)
        for _ in 0..<4 { h.superview.layoutIfNeeded() }
        h.drain(0.2)
        for _ in 0..<2 { h.superview.layoutIfNeeded() }
    }

    private func run(collections: Int) throws -> (settled: CGFloat, sizes: [CGFloat], offsets: [CGFloat], rest: CGFloat) {
        let h = RenderHarness(size: CGSize(width: 393, height: 852))
        try h.render(Self.screenJSON(collections: collections))
        settle(h)
        let vm = try XCTUnwrap(h.viewModel("scroll", as: CScrollViewViewModel.self))
        let scroll = try XCTUnwrap(h.find(UIScrollView.self))
        try vm.variableStore.setValue(name: "items", value: Self.items)
        settle(h)

        // Scroll down to the end the way a finger does, a screen at a time.
        var y: CGFloat = 0
        while true {
            let maxOffset = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
            y = min(y + 300, maxOffset)
            scroll.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            h.superview.layoutIfNeeded()
            h.drain(0.02)
            if y >= maxOffset { break }
        }
        h.drain(0.2)
        h.superview.layoutIfNeeded()
        let maxOffset = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
        scroll.setContentOffset(CGPoint(x: 0, y: maxOffset), animated: false)
        h.superview.layoutIfNeeded()
        let settled = scroll.contentSize.height
        let rest = scroll.contentOffset.y

        var sizes: [CGFloat] = []
        var offsets: [CGFloat] = []
        let sizeObs = scroll.observe(\.contentSize, options: [.new]) { sv, _ in
            MainActor.assumeIsolated { sizes.append(sv.contentSize.height) }
        }
        let offsetObs = scroll.observe(\.contentOffset, options: [.new]) { sv, _ in
            MainActor.assumeIsolated { offsets.append(sv.contentOffset.y) }
        }
        defer { sizeObs.invalidate(); offsetObs.invalidate() }
        for tick in 1...6 {
            try vm.variableStore.setValue(name: "tick", value: tick)
            h.drain(0.05)
            for _ in 0..<3 { h.superview.layoutIfNeeded() }
        }
        h.drain(1.0)
        h.superview.layoutIfNeeded()
        return (settled, sizes + [scroll.contentSize.height], offsets + [scroll.contentOffset.y], rest)
    }

    func testSelfSizingCollectionsKeepTheirHeightAtRest() throws {
        let r = try run(collections: 5)
        XCTAssertTrue(r.sizes.allSatisfy { abs($0 - r.settled) < 0.5 },
                      "content heights after rest: \(r.sizes), settled \(r.settled)")
        XCTAssertTrue(r.offsets.allSatisfy { abs($0 - r.rest) < 0.5 },
                      "offsets after rest: \(r.offsets), rest \(r.rest)")
    }

    /// Each collection is exactly as tall as its rows: nothing estimated is left.
    func testSelfSizingCollectionsMatchTheirCells() throws {
        let h = RenderHarness(size: CGSize(width: 393, height: 852))
        try h.render(Self.screenJSON(collections: 2))
        settle(h)
        let vm = try XCTUnwrap(h.viewModel("scroll", as: CScrollViewViewModel.self))
        try vm.variableStore.setValue(name: "items", value: Self.items)
        settle(h)
        var lists: [UICollectionView] = []
        func walk(_ v: UIView) { if let c = v as? UICollectionView { lists.append(c) }; v.subviews.forEach(walk) }
        walk(h.superview)
        XCTAssertEqual(lists.count, 2)
        for list in lists {
            let cells = list.visibleCells.sorted { $0.frame.minY < $1.frame.minY }
            XCTAssertEqual(cells.count, list.numberOfItems(inSection: 0), "every row is realised")
            guard let last = cells.last else { continue }
            XCTAssertEqual(list.bounds.height, last.frame.maxY, accuracy: 0.5, "as tall as its rows")
            for cell in cells {
                let fit = cell.contentView.systemLayoutSizeFitting(
                    CGSize(width: cell.bounds.width, height: 0),
                    withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
                XCTAssertEqual(cell.bounds.height, fit, accuracy: 0.5, "row measured at its real width")
            }
        }
    }
}
