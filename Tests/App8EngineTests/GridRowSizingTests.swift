//
//  GridRowSizingTests.swift
//  App8EngineTests
//
//  Self-sizing grid rows (collections.md, "Self-sizing grid rows"): without
//  `itemHeight` / `aspectRatio` a grid item is as tall as its content, each
//  row is as tall as its tallest item, and the other items stretch to it.
//  The Facetheory product card hangs its ADD TO BAG footer off a `>=` gap, so
//  its height is ambiguous; cells used to be fitted against the proposed frame
//  (the 470pt `estimatedItemHeight`) and kept ~180pt of empty space above the
//  button. They must take the content's natural (smallest) height instead.
//

import XCTest
@testable import App8Engine

@MainActor
final class GridRowSizingTests: XCTestCase {

    /// Header heights; a card's natural height is header + 10 (min gap) + 40 (footer).
    private static let headers: [Int] = [100, 160, 120, 120, 80, 200, 60, 60]
    private static let estimated: CGFloat = 470

    private static func natural(_ i: Int) -> CGFloat { CGFloat(headers[i] + 50) }

    private static let card = """
    { "id": "card", "type": "view",
      "content": { "children": [
        { "id": "header", "type": "view",
          "content": { "layout": { "height": "{{item.h}}", "constraints": [
            { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
            { "type": "trailing", "target": "superview" } ] } } },
        { "id": "footer", "type": "view",
          "content": { "layout": { "height": 40, "constraints": [
            { "type": "top", "target": "header", "attribute": "bottom", "constant": 10, "op": ">=" },
            { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" },
            { "type": "bottom", "target": "superview" } ] } } }
      ] } }
    """

    private static var itemsJSON: String {
        headers.enumerated().map { #"{"id":"p\#($0.offset)","h":\#($0.element)}"# }.joined(separator: ",")
    }

    private static let gridLayout = """
    { "type": "grid", "columns": 2, "estimatedItemHeight": \(Int(estimated)), "itemSpacing": 10, "lineSpacing": 20,
      "contentInsets": { "left": 10, "right": 10 } }
    """

    /// A plain `layout.type: grid` collection.
    private static var plainGridJSON: String {
        """
        { "type": "view", "id": "root",
          "content": {
            "variables": { "products": { "type": "array", "initialValue": [\(itemsJSON)] } },
            "layout": { "width": 390, "height": 2000 },
            "children": [
              { "type": "collection", "id": "grid",
                "content": {
                  "properties": { "data": "{{products}}", "layout": \(gridLayout) },
                  "layout": { "top": 0, "leading": 0, "width": 390, "height": 2000 },
                  "template": \(card) } }
            ] } }
        """
    }

    /// A grid section in `sectionLayouts` (the Facetheory collection screen).
    private static var sectionGridJSON: String {
        """
        { "type": "view", "id": "root",
          "content": {
            "variables": { "products": { "type": "array", "initialValue": [\(itemsJSON)] } },
            "layout": { "width": 390, "height": 2000 },
            "children": [
              { "type": "collection", "id": "grid",
                "content": {
                  "properties": {
                    "sectionDefinitions": [ { "key": "products", "data": "{{products}}", "templateName": "card" } ],
                    "layout": { "type": "vertical" },
                    "sectionLayouts": { "products": \(gridLayout) } },
                  "layout": { "top": 0, "leading": 0, "width": 390, "height": 2000 },
                  "templates": { "card": \(card) } } }
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

    private static func firstView(withId id: String, in view: UIView) -> UIView? {
        if let c = view as? CView, c.layoutModeId == id { return c }
        for sub in view.subviews { if let v = firstView(withId: id, in: sub) { return v } }
        return nil
    }

    private func assertRowsSizeToTallestItem(_ json: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 2000), inWindow: false)
        try harness.render(json)
        harness.drain()
        let grid = try XCTUnwrap(Self.firstCollectionView(in: harness.superview), file: file, line: line)
        // Bound expressions (item.h) settle a hop later; let the remeasure land.
        for _ in 0..<3 { grid.layoutIfNeeded(); harness.drain(0.05) }

        let count = Self.headers.count
        let section = grid.numberOfSections - 1
        XCTAssertEqual(grid.numberOfItems(inSection: section), count, file: file, line: line)

        var previousRowMaxY: CGFloat?
        for row in stride(from: 0, to: count, by: 2) {
            let tallest = max(Self.natural(row), Self.natural(row + 1))
            var rowMinY: CGFloat?
            for i in [row, row + 1] {
                let cell = try XCTUnwrap(grid.cellForItem(at: IndexPath(item: i, section: section)),
                                         "item \(i) not laid out", file: file, line: line)
                XCTAssertEqual(cell.frame.height, tallest, accuracy: 0.5,
                               "item \(i): the row must be as tall as its tallest natural item", file: file, line: line)
                XCTAssertLessThan(cell.frame.height, Self.estimated - 200,
                                  "item \(i) kept the estimated height", file: file, line: line)
                if let y = rowMinY {
                    XCTAssertEqual(cell.frame.minY, y, accuracy: 0.5, "row \(row / 2) items share a top", file: file, line: line)
                }
                rowMinY = cell.frame.minY
                // The footer sits on the bottom edge of the stretched card.
                let footer = try XCTUnwrap(Self.firstView(withId: "footer", in: cell.contentView), file: file, line: line)
                let bottom = footer.convert(footer.bounds, to: cell.contentView).maxY
                XCTAssertEqual(bottom, cell.bounds.height, accuracy: 0.5,
                               "item \(i): footer pinned to the card's bottom", file: file, line: line)
            }
            if let prev = previousRowMaxY, let y = rowMinY {
                XCTAssertEqual(y - prev, 20, accuracy: 0.5, "line spacing above row \(row / 2)", file: file, line: line)
            }
            previousRowMaxY = (rowMinY ?? 0) + tallest
        }
    }

    func testPlainGridRowsTakeTheTallestNaturalItem() throws {
        try assertRowsSizeToTallestItem(Self.plainGridJSON)
    }

    func testSectionLayoutGridRowsTakeTheTallestNaturalItem() throws {
        try assertRowsSizeToTallestItem(Self.sectionGridJSON)
    }
}
