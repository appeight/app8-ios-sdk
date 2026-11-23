//
//  ScrollContentWrapHeightTests.swift
//  App8EngineTests
//

import XCTest
import UIKit
@testable import App8Engine

/// A vertical scroll view's content size must include multi-line labels at
/// their wrapped height: the last rows must be reachable (0.7.12).
@MainActor
final class ScrollContentWrapHeightTests: XCTestCase {

    static let paragraph = "Sample paragraph text that is long enough to wrap over several lines in a column of about three hundred and fifty points, as body copy does on a phone."

    static func screenJSON(rows: Int = 6) -> String {
        let labels = (0..<4).map { i in
            """
            { "type": "label", "id": "p\(i)",
              "content": {
                "properties": { "text": "\(paragraph)", "numberOfLines": 0 },
                "style": { "text": { "fontSize": 17 } }
              } }
            """
        }
        let rowViews = (0..<rows).map { i in
            """
            { "type": "view", "id": "row\(i)",
              "content": {
                "style": { "backgroundColor": "#DDDDDD" },
                "layout": { "constraints": [ { "type": "height", "constant": 56 } ] }
              } }
            """
        }
        return """
        {
          "type": "scrollView", "id": "scroll",
          "content": {
            "variables": { "tick": { "type": "number", "initialValue": 0 } },
            "layout": { "constraints": [ { "type": "edges", "target": "superview" } ] },
            "children": [
              { "type": "stackView", "id": "stack",
                "content": {
                  "properties": { "axis": "vertical", "spacing": 12 },
                  "layout": { "constraints": [
                    { "type": "top", "target": "superview" },
                    { "type": "bottom", "target": "superview" },
                    { "type": "leading", "target": "superview", "constant": 20 },
                    { "type": "trailing", "target": "superview", "constant": -20 }
                  ] },
                  "children": [ \((labels + rowViews).joined(separator: ",\n")) ]
                } }
            ]
          }
        }
        """
    }

    /// Steps block: wrapper view > stack (20 pt margins) > per-step stacks >
    /// a short title and a wrapping paragraph, under a stretchy hero.
    static func nestedScreenJSON() -> String {
        let steps = (0..<3).map { i in
            """
            { "type": "stackView", "id": "step\(i)",
              "content": {
                "properties": { "axis": "vertical", "spacing": 6, "alignment": "fill" },
                "children": [
                  { "type": "label", "id": "n\(i)", "content": { "properties": { "text": "\(i + 1)" }, "style": { "text": { "fontSize": 28 } } } },
                  { "type": "label", "id": "h\(i)", "content": { "properties": { "text": "Step title" }, "style": { "text": { "fontSize": 17, "fontWeight": "semibold" } } } },
                  { "type": "label", "id": "p\(i)", "content": { "properties": { "text": "\(paragraph)", "numberOfLines": 0 },
                    "style": { "text": { "fontSize": 15, "lineHeight": { "type": "multiplier", "value": 1.4 } } } } }
                ]
              } }
            """
        }
        let rowViews = (0..<6).map { i in
            """
            { "type": "view", "id": "row\(i)",
              "content": {
                "style": { "backgroundColor": "#DDDDDD" },
                "layout": { "constraints": [ { "type": "height", "constant": 56 } ] }
              } }
            """
        }
        return """
        {
          "type": "scrollView", "id": "scroll",
          "content": {
            "properties": { "direction": "vertical", "contentInsetAdjustment": "never", "contentInset": { "bottom": 96 }, "stretchesTopChild": true },
            "layout": { "constraints": [ { "type": "edges", "target": "superview" } ] },
            "children": [
              { "type": "stackView", "id": "stack",
                "content": {
                  "properties": { "axis": "vertical", "spacing": 0, "alignment": "fill" },
                  "layout": { "constraints": [ { "type": "edges", "target": "superview" } ] },
                  "children": [
                    { "type": "view", "id": "hero", "content": { "style": { "backgroundColor": "#888888" },
                      "layout": { "constraints": [ { "type": "height", "target": "superview", "attribute": "width", "multiplier": 1.08 } ] } } },
                    { "type": "view", "id": "stepsBlock",
                      "content": {
                        "children": [
                          { "type": "stackView", "id": "steps",
                            "content": {
                              "properties": { "axis": "vertical", "spacing": 24, "alignment": "fill" },
                              "layout": { "constraints": [
                                { "type": "top", "target": "superview" },
                                { "type": "leading", "target": "superview", "constant": 20 },
                                { "type": "trailing", "target": "superview", "constant": -20 },
                                { "type": "bottom", "target": "superview" }
                              ] },
                              "children": [ \(steps.joined(separator: ",\n")) ]
                            } }
                        ]
                      } },
                    \(rowViews.joined(separator: ",\n"))
                  ]
                } }
            ]
          }
        }
        """
    }

    /// A variable no label uses changes (a screen timer): the wrapping labels
    /// keep their wrap, so the content never gets shorter, not even for one
    /// layout pass. Up to 0.7.11 each update re-measured every wrapping label,
    /// which reported one line for a pass: a scroll that came to rest then
    /// stopped about a line per label short of the end.
    func testUnrelatedVariableUpdateKeepsContentHeight() throws {
        let harness = RenderHarness(size: CGSize(width: 393, height: 852))
        try harness.render(Self.screenJSON())
        harness.drain(0.3)
        for _ in 0..<4 { harness.superview.layoutIfNeeded() }
        let scroll = try XCTUnwrap(harness.find(UIScrollView.self))
        let settled = scroll.contentSize.height
        XCTAssertGreaterThan(settled, 600)
        let vm = try XCTUnwrap(harness.viewModel("scroll", as: CScrollViewViewModel.self))
        var shortest = settled
        let observation = scroll.observe(\.contentSize, options: [.new]) { sv, _ in
            MainActor.assumeIsolated { shortest = min(shortest, sv.contentSize.height) }
        }
        defer { observation.invalidate() }
        for tick in 1...3 {
            try vm.variableStore.setValue(name: "tick", value: tick)
            harness.drain(0.1)
            for _ in 0..<3 { harness.superview.layoutIfNeeded() }
            XCTAssertEqual(scroll.contentSize.height, settled, accuracy: 0.5)
        }
        XCTAssertGreaterThanOrEqual(shortest + 0.5, settled,
                                    "the content was \(settled - shortest) pt short for a layout pass")
    }

    func testContentSizeIncludesWrappedLabelsInNestedStacks() throws {
        try assertContentReachesLastRow(json: Self.nestedScreenJSON(), paragraphs: 3)
    }

    func testContentSizeIncludesWrappedLabels() throws {
        try assertContentReachesLastRow(json: Self.screenJSON(), paragraphs: 4)
    }

    private func assertContentReachesLastRow(json: String, paragraphs: Int) throws {
        let service = App8Service(publicDataSource: ScrollWrapStubDataSource(), context: App8Context())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.makeKeyAndVisible()
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(json.utf8))
        let root = UIView(frame: .zero)
        service.renderComponent(component, superview: root)
        window.addSubview(root)
        root.frame = window.bounds
        for _ in 0..<4 { root.setNeedsLayout(); root.layoutIfNeeded() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        for _ in 0..<4 { root.layoutIfNeeded() }

        let scroll = try XCTUnwrap(firstView(UIScrollView.self, in: root))
        let labels = allViews(UILabel.self, in: scroll).filter { ($0.attributedText?.string ?? $0.text ?? "").hasPrefix("Sample paragraph") }
        XCTAssertEqual(labels.count, paragraphs)
        for label in labels {
            let needed = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height
            XCTAssertGreaterThan(label.bounds.width, 300, "wraps in the 353 pt column")
            XCTAssertGreaterThanOrEqual(label.bounds.height + 1, needed, "label is as tall as its wrapped text")
        }
        let rows = allViews(UIView.self, in: scroll).filter { $0.accessibilityIdentifier == "row5" }
        let lastRow = try XCTUnwrap(rows.first ?? lastRowByHeight(in: scroll))
        let lastBottom = lastRow.convert(lastRow.bounds, to: scroll).maxY
        XCTAssertGreaterThanOrEqual(scroll.contentSize.height + 0.5, lastBottom,
                                    "content size \(scroll.contentSize.height) ends above the last row (\(lastBottom))")
    }

    private func lastRowByHeight(in scroll: UIScrollView) -> UIView? {
        allViews(UIView.self, in: scroll)
            .filter { abs($0.bounds.height - 56) < 0.5 }
            .max { $0.convert($0.bounds, to: scroll).maxY < $1.convert($1.bounds, to: scroll).maxY }
    }

    private func firstView<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let v = view as? T { return v }
        for s in view.subviews { if let v = firstView(type, in: s) { return v } }
        return nil
    }

    private func allViews<T: UIView>(_ type: T.Type, in view: UIView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { allViews(type, in: $0) }
    }
}

private final class ScrollWrapStubDataSource: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data { Data() }
}
