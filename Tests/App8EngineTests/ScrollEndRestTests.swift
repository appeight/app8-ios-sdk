//
//  ScrollEndRestTests.swift
//  App8EngineTests
//

import XCTest
import UIKit
@testable import App8Engine

/// A vertical scroll view resting at its end stays there while variables it
/// does not show change (a screen timer ticking): no content-size dip, no
/// content-offset change (scroll-view.md, "The end of the scroll").
///
/// Up to 0.7.15 a wrapping label that hugs its wrapped text (`trailing <=`
/// its container, or in a leading-aligned stack) re-measured its wrap on
/// every variable update and was one line tall for a layout pass. UIKit then
/// clamped a resting offset to the shorter content, and after a bounce at the
/// end the content jumped by the label's lost lines.
@MainActor
final class ScrollEndRestTests: XCTestCase {

    static let heading = "A heading long enough to wrap onto a second line"
    static let paragraph = "Sample paragraph text that is long enough to wrap over several lines in a column of about three hundred and fifty points."

    /// A long screen: a hero, hugging headings (`trailing <=`), paragraphs in
    /// a leading-aligned stack, a self-sizing vertical collection with
    /// multi-line rows, and a button-sized block at the end.
    static func screenJSON() -> String {
        func hugging(_ id: String) -> String {
            """
            { "type": "view", "id": "\(id)",
              "content": { "children": [
                { "type": "label", "id": "\(id)T",
                  "content": {
                    "properties": { "text": "\(heading)", "numberOfLines": 0 },
                    "style": { "text": { "fontSize": 28 } },
                    "layout": { "constraints": [
                      { "type": "top", "target": "superview" },
                      { "type": "bottom", "target": "superview" },
                      { "type": "leading", "target": "superview", "constant": 20 },
                      { "type": "trailing", "target": "superview", "constant": -20, "op": "<=" }
                    ] } } }
              ] } }
            """
        }
        func leadingStack(_ id: String) -> String {
            """
            { "type": "stackView", "id": "\(id)",
              "content": {
                "properties": { "axis": "vertical", "spacing": 8, "alignment": "leading" },
                "children": [
                  { "type": "label", "id": "\(id)P",
                    "content": { "properties": { "text": "\(paragraph)", "numberOfLines": 0 },
                                 "style": { "text": { "fontSize": 17 } } } }
                ] } }
            """
        }
        let spacer = #"{ "type": "view", "content": { "layout": { "height": 24 } } }"#
        let rows = (0..<5).map { ##"{ "title": "Row \##($0)", "body": "\##(paragraph)" }"## }.joined(separator: ",")
        let collection = """
            { "type": "collection", "id": "list",
              "content": {
                "properties": { "data": "{{rows}}",
                                "layout": { "type": "vertical", "estimatedItemHeight": 60, "itemSpacing": 12 } },
                "template": { "id": "row", "type": "view", "content": { "children": [
                  { "type": "label", "id": "rowBody",
                    "content": {
                      "properties": { "text": "{{item.body}}", "numberOfLines": 0 },
                      "style": { "text": { "fontSize": 15 } },
                      "layout": { "constraints": [
                        { "type": "top", "target": "superview" },
                        { "type": "bottom", "target": "superview" },
                        { "type": "leading", "target": "superview", "constant": 20 },
                        { "type": "trailing", "target": "superview", "constant": -20, "op": "<=" }
                      ] } } }
                ] } }
              } }
            """
        var children: [String] = [
            ##"{ "type": "view", "id": "hero", "content": { "style": { "backgroundColor": "#888888" }, "layout": { "height": 420 } } }"##
        ]
        for i in 0..<4 {
            children += [hugging("h\(i)"), spacer, leadingStack("s\(i)"), spacer]
        }
        children += [collection, spacer, hugging("last"),
                     ##"{ "type": "view", "id": "end", "content": { "style": { "backgroundColor": "#222222" }, "layout": { "height": 48 } } }"##,
                     #"{ "type": "view", "content": { "layout": { "height": 48 } } }"#]
        return """
        {
          "type": "scrollView", "id": "scroll",
          "content": {
            "variables": {
              "tick": { "type": "number", "initialValue": 0 },
              "rows": { "type": "array", "initialValue": [\(rows)] }
            },
            "properties": { "direction": "vertical", "contentInsetAdjustment": "bottom", "stretchesTopChild": true },
            "layout": { "constraints": [ { "type": "edges", "target": "superview" } ] },
            "children": [
              { "type": "stackView", "id": "stack",
                "content": {
                  "properties": { "axis": "vertical", "spacing": 0, "alignment": "fill" },
                  "layout": { "constraints": [ { "type": "edges", "target": "superview" } ] },
                  "children": [ \(children.joined(separator: ",\n")) ]
                } }
            ]
          }
        }
        """
    }

    func testRestingAtTheEndSurvivesUnrelatedVariableUpdates() throws {
        let harness = RenderHarness(size: CGSize(width: 393, height: 852))
        try harness.render(Self.screenJSON())
        harness.drain(0.4)
        for _ in 0..<4 { harness.superview.layoutIfNeeded() }
        harness.drain(0.2)
        for _ in 0..<2 { harness.superview.layoutIfNeeded() }

        let scroll = try XCTUnwrap(harness.find(UIScrollView.self))
        let settled = scroll.contentSize.height
        XCTAssertGreaterThan(settled, scroll.bounds.height * 1.5, "a long screen")

        // The headings wrap onto two lines and hug their wrapped text.
        let headings = labels(in: scroll, prefix: "A heading")
        XCTAssertEqual(headings.count, 5)
        for label in headings {
            XCTAssertGreaterThan(label.bounds.height, 50, "wraps onto two lines")
            XCTAssertLessThan(label.bounds.width, 353 - 0.5, "hugs its wrapped text")
        }

        // Rest at the end, as a scroll does after its bounce.
        let maxOffset = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
        scroll.setContentOffset(CGPoint(x: 0, y: maxOffset), animated: false)
        harness.superview.layoutIfNeeded()
        let rest = scroll.contentOffset.y
        XCTAssertEqual(rest, maxOffset, accuracy: 0.5)

        let vm = try XCTUnwrap(harness.viewModel("scroll", as: CScrollViewViewModel.self))
        var shortest = settled
        var offsets: Set<CGFloat> = []
        let sizeObservation = scroll.observe(\.contentSize, options: [.new]) { sv, _ in
            MainActor.assumeIsolated { shortest = min(shortest, sv.contentSize.height) }
        }
        let offsetObservation = scroll.observe(\.contentOffset, options: [.new]) { sv, _ in
            MainActor.assumeIsolated { _ = offsets.insert((sv.contentOffset.y * 2).rounded() / 2) }
        }
        defer { sizeObservation.invalidate(); offsetObservation.invalidate() }

        for tick in 1...6 {
            try vm.variableStore.setValue(name: "tick", value: tick)
            harness.drain(0.05)
            for _ in 0..<3 { harness.superview.layoutIfNeeded() }
            XCTAssertEqual(scroll.contentSize.height, settled, accuracy: 0.5, "tick \(tick)")
            XCTAssertEqual(scroll.contentOffset.y, rest, accuracy: 0.5, "tick \(tick): the end moved")
        }
        XCTAssertGreaterThanOrEqual(shortest + 0.5, settled,
                                    "the content was \(settled - shortest) pt short for a layout pass")
        XCTAssertTrue(offsets.allSatisfy { abs($0 - rest) < 0.5 }, "offsets seen: \(offsets.sorted())")
    }

    /// The same text after a width change still wraps again (the hugging
    /// wrap holds only while its lines fit what the container grants).
    func testHuggingWrapStillFollowsANarrowerContainer() throws {
        let harness = RenderHarness(size: CGSize(width: 393, height: 852))
        try harness.render(Self.screenJSON())
        harness.drain(0.4)
        for _ in 0..<4 { harness.superview.layoutIfNeeded() }
        let scroll = try XCTUnwrap(harness.find(UIScrollView.self))
        let before = try XCTUnwrap(labels(in: scroll, prefix: "A heading").first).bounds.height

        harness.window?.frame.size.width = 240
        harness.superview.frame.size.width = 240
        for _ in 0..<3 {
            harness.superview.setNeedsLayout()
            harness.superview.layoutIfNeeded()
            harness.drain(0.1)
        }
        let label = try XCTUnwrap(labels(in: scroll, prefix: "A heading").first)
        XCTAssertLessThanOrEqual(label.bounds.width, 200 + 0.5, "fits the narrower column")
        XCTAssertGreaterThan(label.bounds.height, before + 1, "wraps onto more lines")
        let needed = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height
        XCTAssertGreaterThanOrEqual(label.bounds.height + 1, needed)
    }

    private func labels(in view: UIView, prefix: String) -> [UILabel] {
        var out: [UILabel] = []
        func walk(_ v: UIView) {
            if let l = v as? UILabel, (l.attributedText?.string ?? l.text ?? "").hasPrefix(prefix) { out.append(l) }
            v.subviews.forEach(walk)
        }
        walk(view)
        return out
    }
}
