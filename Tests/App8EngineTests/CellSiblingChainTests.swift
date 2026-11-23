//
//  CellSiblingChainTests.swift
//  App8EngineTests
//
//  In a collection cell template, a view chained under its sibling
//  (`info.top = sibling(photo).bottom + 12`) sits below it, and a
//  `height = superview.width × 1.25` photo resolves against the card's width,
//  not the cell's height (0.7.12).
//

import XCTest
@testable import App8Engine

@MainActor
final class CellSiblingChainTests: XCTestCase {

    static func json(target: String, rootHasHeight: Bool = false, infoStack: Bool = false, relativeTitle: Bool = true) -> String {
        """
        {
          "type": "view", "id": "root",
          "content": {
            "variables": { "items": { "type": "array", "initialValue": [ { "id": "a", "title": "Sample Item A" }, { "id": "b", "title": "Sample Item B" } ] } },
            "layout": { "width": 390, "height": 600 },
            "children": [
              { "type": "collection", "id": "rail",
                "content": {
                  "properties": { "data": "{{items}}", "layout": { "type": "horizontal", "itemWidth": 180, "itemHeight": 330, "itemSpacing": 12 } },
                  "layout": { "top": 0, "leading": 0, "width": 390, "height": 330 },
                  "template": { "id": "card", "type": "view",
                    "content": {
                      \(rootHasHeight ? #""layout": { "constraints": [ { "type": "edges", "target": "superview" } ] },"# : "")
                      "children": [
                        { "id": "photo", "type": "view",
                          "content": { "style": { "material": [ { "id": "photoFill", "type": "fill", "content": { "solid": "#CCCCCC" } } ] },
                            "layout": { "constraints": [
                              { "type": "top", "target": "superview" },
                              { "type": "leading", "target": "superview" },
                              { "type": "trailing", "target": "superview" },
                              { "type": "height", "target": "superview", "attribute": "width", "multiplier": 1.25 } ] } } },
                        \(infoStack ? Self.infoStack(target: target, relativeTitle: relativeTitle) : Self.infoView(target: target))
                      ] } }
                } }
            ]
          }
        }
        """
    }

    static func infoView(target: String) -> String {
        """
        { "id": "info", "type": "view",
          "content": {
            "layout": { "constraints": [
              { "type": "top", "target": "\(target)", "attribute": "bottom", "constant": 12 },
              { "type": "leading", "target": "superview" },
              { "type": "trailing", "target": "superview" },
              { "type": "height", "constant": 40 } ] },
            "children": [
              { "id": "title", "type": "label", "content": { "properties": { "text": "{{item.title}}" },
                "layout": { "constraints": [ { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" } ] } } }
            ] } }
        """
    }

    /// The text column as a stack whose title asks for a minimum height
    /// relative to the stack (`height >= superview + 36`, unsatisfiable).
    static func infoStack(target: String, relativeTitle: Bool = true) -> String {
        """
        { "id": "info", "type": "stackView",
          "content": {
            "properties": { "axis": "vertical", "spacing": 6, "alignment": "fill" },
            "layout": { "constraints": [
              { "type": "top", "target": "\(target)", "attribute": "bottom", "constant": 12 },
              { "type": "leading", "target": "superview" },
              { "type": "trailing", "target": "superview" },
              { "type": "bottom", "target": "superview", "constant": -8, "op": "<=" } ] },
            "children": [
              { "id": "title", "type": "label", "content": { "properties": { "text": "{{item.title}}", "numberOfLines": 2 },
                "layout": { "constraints": [ \(relativeTitle ? #"{ "type": "height", "target": "superview", "constant": 36, "op": ">=" }"# : #"{ "type": "height", "constant": 36, "op": ">=" }"#) ] } } },
              { "id": "price", "type": "label", "content": { "properties": { "text": "$10.00" } } }
            ] } }
        """
    }

    private static func views(withId id: String, in view: UIView) -> [UIView] {
        var out: [UIView] = []
        if let c = view as? CView, c.layoutModeId == id { out.append(c) }
        for sub in view.subviews { out += views(withId: id, in: sub) }
        return out
    }

    private func assertChain(target: String, rootHasHeight: Bool = false, infoStack: Bool = false, relativeTitle: Bool = true, file: StaticString = #filePath, line: UInt = #line) throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 600))
        try harness.render(Self.json(target: target, rootHasHeight: rootHasHeight, infoStack: infoStack, relativeTitle: relativeTitle))
        harness.drain()
        for _ in 0..<3 { harness.superview.layoutIfNeeded() }
        harness.drain()
        if ProcessInfo.processInfo.environment["A8_DUMP"] != nil {
            func dump(_ v: UIView, _ d: Int) { print(String(repeating: " ", count: d) + "\(type(of: v)) \(v.frame) id=\((v as? CView)?.layoutModeId ?? "")"); for s in v.subviews where d < 12 { dump(s, d + 1) } }
            dump(harness.superview, 0)
        }
        let photos = Self.views(withId: "photo", in: harness.superview)
        // The view after the photo in the card (a view or a stack).
        let infos = photos.compactMap { p in p.superview?.subviews.first { $0 !== p && !($0 is MaterialView) } }
        XCTAssertEqual(photos.count, 2, "two cells", file: file, line: line)
        XCTAssertEqual(infos.count, 2, file: file, line: line)
        for (photo, info) in zip(photos, infos) {
            let p = photo.convert(photo.bounds, to: harness.superview)
            let i = info.convert(info.bounds, to: harness.superview)
            XCTAssertEqual(p.width, 180, accuracy: 0.5, "photo spans the card", file: file, line: line)
            XCTAssertEqual(p.height, 225, accuracy: 0.5, "photo height = card width × 1.25, got \(p.height)", file: file, line: line)
            XCTAssertEqual(i.minY, p.maxY + 12, accuracy: 0.5, "info sits 12 pt under the photo (\(i.minY) vs \(p.maxY))", file: file, line: line)
            func labels(_ v: UIView) -> [UILabel] { ((v as? UILabel).map { [$0] } ?? []) + v.subviews.flatMap(labels) }
            let title = labels(info).first { ($0.attributedText?.string ?? $0.text ?? "").hasPrefix("Sample Item") }
            XCTAssertNotNil(title, "the title renders in the info view", file: file, line: line)
            if let title {
                let t = title.convert(title.bounds, to: harness.superview)
                XCTAssertGreaterThanOrEqual(t.minY + 0.5, p.maxY + 12, "title under the photo", file: file, line: line)
                XCTAssertGreaterThan(t.height, 10, "title has a height", file: file, line: line)
            }
            if infoStack {
                let price = labels(info).first { ($0.attributedText?.string ?? $0.text ?? "") == "$10.00" }
                XCTAssertNotNil(price, file: file, line: line)
                if let price, let title {
                    let pr = price.convert(price.bounds, to: harness.superview), t = title.convert(title.bounds, to: harness.superview)
                    XCTAssertGreaterThan(pr.height, 10, "the price is not squeezed", file: file, line: line)
                    XCTAssertGreaterThanOrEqual(pr.minY + 0.5, t.maxY, "price under the title", file: file, line: line)
                }
            }
            if !infoStack { XCTAssertEqual(i.height, 40, accuracy: 0.5, file: file, line: line) }
        }
    }

    func testSiblingChainInCell() throws { try assertChain(target: "sibling(photo)") }
    func testBareIdChainInCell() throws { try assertChain(target: "photo") }
    func testStackChainWithMinTitleHeight() throws { try assertChain(target: "photo", infoStack: true, relativeTitle: false) }
    func testStackChainWithRelativeTitleHeight() throws { try assertChain(target: "photo", infoStack: true) }
    func testSiblingChainInCellWithPinnedRoot() throws { try assertChain(target: "sibling(photo)", rootHasHeight: true) }
}
