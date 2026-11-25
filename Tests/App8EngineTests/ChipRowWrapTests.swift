//
//  ChipRowWrapTests.swift
//  App8EngineTests
//

import XCTest
import UIKit
@testable import App8Engine

/// Chips: wrapping labels (`numberOfLines: 0`) inside padded views, laid out
/// in horizontal `fill` stacks that sit in a leading-aligned vertical stack
/// (a report's filter chips), on a long scroll resting at its end.
///
/// Each chip must measure its wrap once, against the width its row really
/// grants, and keep it while unrelated variables change. A chip that wraps
/// narrower than its text for a pass makes its row taller, the scroll content
/// taller or shorter, and UIKit then moves a scroll resting at its end
/// (scroll-view.md, "The end of the scroll").
@MainActor
final class ChipRowWrapTests: XCTestCase {

    static let chipTexts = [["Wrinkles", "Pigmentation", "Redness", "Pores"],
                            ["Hydration", "Texture", "Dark circles"],
                            ["Firmness", "Oiliness"]]

    static func chip(_ id: String, _ text: String) -> String {
        """
        { "type": "view", "id": "\(id)",
          "content": {
            "style": { "material": [ { "id": "\(id)F", "type": "fill", "content": { "solid": "{{selected == '\(id)' ? '#111111' : '#00000000'}}" } } ] },
            "layout": { "constraints": [ { "type": "height", "constant": 36, "op": ">=" } ] },
            "children": [
              { "type": "label", "id": "\(id)L",
                "content": {
                  "properties": { "text": "{{ready ? '\(text)' : ''}}" },
                  "style": { "text": { "fontSize": 12, "numberOfLines": 0, "alignment": "center" } },
                  "layout": { "constraints": [
                    { "type": "top", "target": "superview", "constant": 9 },
                    { "type": "leading", "target": "superview", "constant": 14 },
                    { "type": "trailing", "target": "superview", "constant": -14 },
                    { "type": "bottom", "target": "superview", "constant": -9 }
                  ] } } }
            ] } }
        """
    }

    /// The report's packing (a prefab's chip rows): layer i has a chip in every row r <= i, shown only in the
    /// row its estimated width lands in (`chipRow<i>`), hidden in the others. The texts arrive with the data.
    static let layerLabels = ["Oil & shine", "Tired under-eyes", "Spots", "Lines"]

    static func packedChips(_ prefix: String) -> (json: String, variables: String) {
        let n = layerLabels.count
        func w(_ i: Int) -> String { "(length(layers) > \(i) ? length(layers[\(i)]) * 7 + 30 : 0)" }
        var vars = [#""chipRow0": { "type": "number", "computed": "{{0}}" }"#,
                    "\"chipEnd0\": { \"type\": \"number\", \"computed\": \"{{\(w(0))}}\" }"]
        for i in 1..<n {
            let fits = "chipEnd\(i - 1) + 8 + \(w(i)) <= 320"
            vars.append("\"chipRow\(i)\": { \"type\": \"number\", \"computed\": \"{{\(fits) ? chipRow\(i - 1) : chipRow\(i - 1) + 1}}\" }")
            vars.append("\"chipEnd\(i)\": { \"type\": \"number\", \"computed\": \"{{\(fits) ? chipEnd\(i - 1) + 8 + \(w(i)) : \(w(i))}}\" }")
        }
        let rows = (0..<n).map { r in
            let chips = (r..<n).map { i -> String in
                let id = "\(prefix)chip_\(r)_\(i)"
                return """
                { "type": "view", "id": "\(id)",
                  "content": {
                    "properties": { "isHidden": "{{length(layers) <= \(i) || chipRow\(i) != \(r)}}" },
                    "style": { "material": [ { "id": "\(id)F", "type": "fill", "content": { "solid": "{{selected == \(i) ? '#111111' : '#00000000'}}" } } ] },
                    "layout": { "constraints": [ { "type": "height", "constant": 36, "op": ">=" } ] },
                    "children": [
                      { "type": "label", "id": "\(id)L",
                        "content": {
                          "properties": { "text": "{{length(layers) > \(i) ? layers[\(i)] : ''}}" },
                          "style": { "text": { "fontSize": 12, "numberOfLines": 0, "alignment": "center", "color": "{{selected == \(i) ? '#FFFFFF' : '#111111'}}" } },
                          "layout": { "constraints": [
                            { "type": "top", "target": "superview", "constant": 9 },
                            { "type": "leading", "target": "superview", "constant": 14 },
                            { "type": "trailing", "target": "superview", "constant": -14 },
                            { "type": "bottom", "target": "superview", "constant": -9 }
                          ] } } }
                    ] } }
                """
            }.joined(separator: ",")
            return """
            { "type": "stackView", "id": "\(prefix)row\(r)",
              "content": {
                "properties": { "axis": "horizontal", "spacing": 8, "distribution": "fill", "alignment": "fill",
                                "isHidden": "{{!(\((r..<n).map { "(length(layers) > \($0) && chipRow\($0) == \(r))" }.joined(separator: " || ")))}}" },
                "children": [ \(chips) ] } }
            """
        }.joined(separator: ",")
        let json = """
            { "type": "view", "id": "\(prefix)chipsBox", "content": { "children": [
              { "type": "stackView", "id": "\(prefix)chips",
                "content": {
                  "properties": { "axis": "vertical", "spacing": 8, "alignment": "leading" },
                  "layout": { "constraints": [
                    { "type": "top", "target": "superview" },
                    { "type": "leading", "target": "superview", "constant": 20 },
                    { "type": "trailing", "target": "superview", "constant": -20 },
                    { "type": "bottom", "target": "superview" }
                  ] },
                  "children": [ \(rows) ] } }
            ] } }
            """
        return (json, vars.joined(separator: ",\n"))
    }

    static func packedScreenJSON() -> String {
        let top = packedChips("t"), end = packedChips("e")
        func text(_ i: Int) -> String {
            #"{ "type": "label", "id": "para\#(i)", "content": { "properties": { "text": "\#(ScrollEndRestTests.paragraph)", "numberOfLines": 0 }, "style": { "text": { "fontSize": 17 } } } }"#
        }
        var children = [##"{ "type": "view", "id": "hero", "content": { "style": { "backgroundColor": "#888888" }, "layout": { "height": 380 } } }"##, top.json]
        for i in 0..<8 { children.append(text(i)) }
        children += [end.json, #"{ "type": "view", "id": "endSpace", "content": { "layout": { "height": 48 } } }"#]
        return """
        {
          "type": "scrollView", "id": "scroll",
          "content": {
            "variables": {
              "tick": { "type": "number", "initialValue": 0 },
              "selected": { "type": "number", "initialValue": 0 },
              "layers": { "type": "array", "initialValue": [] },
              \(top.variables)
            },
            "properties": { "direction": "vertical", "contentInsetAdjustment": "bottom" },
            "layout": { "constraints": [ { "type": "edges", "target": "superview" } ] },
            "children": [
              { "type": "stackView", "id": "stack",
                "content": {
                  "properties": { "axis": "vertical", "spacing": 12, "alignment": "fill" },
                  "layout": { "constraints": [ { "type": "edges", "target": "superview" } ] },
                  "children": [ \(children.joined(separator: ",\n")) ]
                } }
            ]
          }
        }
        """
    }

    func testPackedChipsFromLateDataStayOneLineAndTheEndStaysPut() throws {
        let h = RenderHarness(size: CGSize(width: 393, height: 852))
        try h.render(Self.packedScreenJSON())
        settle(h)
        let vm = try XCTUnwrap(h.viewModel("scroll", as: CScrollViewViewModel.self))
        let scroll = try XCTUnwrap(h.find(UIScrollView.self))
        try vm.variableStore.setValue(name: "layers", value: Self.layerLabels)
        settle(h)

        func visibleChips() -> [UILabel] {
            var out: [UILabel] = []
            func walk(_ v: UIView) {
                if v.isHidden { return }
                if let l = v as? UILabel, Self.layerLabels.contains(l.attributedText?.string ?? l.text ?? "") { out.append(l) }
                v.subviews.forEach(walk)
            }
            walk(scroll)
            return out
        }
        let oneLine = ceil(UIFont.systemFont(ofSize: 12).lineHeight)
        let chips = visibleChips()
        XCTAssertEqual(chips.count, 8)
        for l in chips {
            XCTAssertLessThan(l.bounds.height, oneLine * 1.5, "'\(l.attributedText?.string ?? "")' fits its row on one line: \(l.bounds)")
        }
        let settled = scroll.contentSize.height
        let maxOffset = settled + scroll.adjustedContentInset.bottom - scroll.bounds.height
        scroll.setContentOffset(CGPoint(x: 0, y: maxOffset), animated: false)
        h.superview.layoutIfNeeded()
        let rest = scroll.contentOffset.y
        var sizes: Set<CGFloat> = []
        let obs = scroll.observe(\.contentSize, options: [.new]) { sv, _ in
            MainActor.assumeIsolated { _ = sizes.insert((sv.contentSize.height * 2).rounded() / 2) }
        }
        defer { obs.invalidate() }
        for tick in 1...6 {
            try vm.variableStore.setValue(name: "tick", value: tick)
            if tick == 3 { try vm.variableStore.setValue(name: "selected", value: 2) }
            h.drain(0.05)
            for _ in 0..<3 { h.superview.layoutIfNeeded() }
            XCTAssertEqual(scroll.contentOffset.y, rest, accuracy: 0.5, "tick \(tick): the end moved")
        }
        h.drain(0.3)
        h.superview.layoutIfNeeded()
        XCTAssertEqual(scroll.contentSize.height, settled, accuracy: 0.5, "after rest")
        XCTAssertTrue(sizes.allSatisfy { abs($0 - settled) < 0.5 }, "content heights seen: \(sizes.sorted()), settled \(settled)")
    }

    static func screenJSON(chipRows: [[String]] = chipTexts, withChips: Bool = true) -> String {
        let rows = chipRows.enumerated().map { r, texts in
            """
            { "type": "stackView", "id": "row\(r)",
              "content": {
                "properties": { "axis": "horizontal", "spacing": 8, "distribution": "fill", "alignment": "fill" },
                "children": [ \(texts.enumerated().map { chip("chip\(r)_\($0.offset)", $0.element) }.joined(separator: ",")) ] } }
            """
        }.joined(separator: ",")
        let chips = """
            { "type": "view", "id": "chipsBox", "content": { "children": [
              { "type": "stackView", "id": "chips",
                "content": {
                  "properties": { "axis": "vertical", "spacing": 8, "alignment": "leading" },
                  "layout": { "constraints": [
                    { "type": "top", "target": "superview" },
                    { "type": "leading", "target": "superview", "constant": 20 },
                    { "type": "trailing", "target": "superview", "constant": -20 },
                    { "type": "bottom", "target": "superview" }
                  ] },
                  "children": [ \(rows) ] } }
            ] } }
            """
        let paragraph = ScrollEndRestTests.paragraph
        func text(_ i: Int) -> String { """
            { "type": "label", "id": "para\(i)", "content": { "properties": { "text": "\(paragraph)", "numberOfLines": 0 },
              "style": { "text": { "fontSize": 17 } } } }
            """ }
        var children = [##"{ "type": "view", "id": "hero", "content": { "style": { "backgroundColor": "#888888" }, "layout": { "height": 380 } } }"##]
        if withChips { children.append(chips) }
        for i in 0..<8 { children.append(text(i)) }
        if withChips { children.append(chips.replacingOccurrences(of: "\"chips", with: "\"endchips").replacingOccurrences(of: "\"chip", with: "\"endchip").replacingOccurrences(of: "\"row", with: "\"endrow")) }
        children.append(#"{ "type": "view", "id": "endSpace", "content": { "layout": { "height": 48 } } }"#)
        return """
        {
          "type": "scrollView", "id": "scroll",
          "content": {
            "variables": {
              "tick": { "type": "number", "initialValue": 0 },
              "ready": { "type": "boolean", "initialValue": false },
              "selected": { "type": "string", "initialValue": "" }
            },
            "properties": { "direction": "vertical", "contentInsetAdjustment": "bottom" },
            "layout": { "constraints": [ { "type": "edges", "target": "superview" } ] },
            "children": [
              { "type": "stackView", "id": "stack",
                "content": {
                  "properties": { "axis": "vertical", "spacing": 12, "alignment": "fill" },
                  "layout": { "constraints": [ { "type": "edges", "target": "superview" } ] },
                  "children": [ \(children.joined(separator: ",\n")) ]
                } }
            ]
          }
        }
        """
    }

    private func settle(_ h: RenderHarness) {
        h.drain(0.3)
        for _ in 0..<4 { h.superview.layoutIfNeeded() }
        h.drain(0.2)
        for _ in 0..<2 { h.superview.layoutIfNeeded() }
    }

    private func chipLabels(_ v: UIView) -> [UILabel] {
        var out: [UILabel] = []
        func walk(_ v: UIView) {
            if let l = v as? UILabel, Self.chipTexts.joined().contains(l.attributedText?.string ?? l.text ?? "") { out.append(l) }
            v.subviews.forEach(walk)
        }
        walk(v)
        return out
    }

    func testChipsWrapOnceAndAScrollAtTheEndStaysPut() throws {
        let h = RenderHarness(size: CGSize(width: 393, height: 852))
        try h.render(Self.screenJSON())
        settle(h)
        let vm = try XCTUnwrap(h.viewModel("scroll", as: CScrollViewViewModel.self))
        let scroll = try XCTUnwrap(h.find(UIScrollView.self))

        // The data arrives after the first layout, as a scan does.
        try vm.variableStore.setValue(name: "ready", value: true)
        settle(h)

        let chips = chipLabels(scroll)
        XCTAssertEqual(chips.count, 18)
        let oneLine = ceil(UIFont.systemFont(ofSize: 12).lineHeight)
        for l in chips {
            XCTAssertLessThan(l.bounds.height, oneLine * 1.5, "'\(l.attributedText?.string ?? "")' fits its row on one line: \(l.bounds)")
        }

        let settled = scroll.contentSize.height
        let maxOffset = settled + scroll.adjustedContentInset.bottom - scroll.bounds.height
        scroll.setContentOffset(CGPoint(x: 0, y: maxOffset), animated: false)
        h.superview.layoutIfNeeded()
        let rest = scroll.contentOffset.y

        var sizes: Set<CGFloat> = []
        let obs = scroll.observe(\.contentSize, options: [.new]) { sv, _ in
            MainActor.assumeIsolated { _ = sizes.insert((sv.contentSize.height * 2).rounded() / 2) }
        }
        defer { obs.invalidate() }
        for tick in 1...6 {
            try vm.variableStore.setValue(name: "tick", value: tick)
            if tick == 3 { try vm.variableStore.setValue(name: "selected", value: "chip0_1") }
            h.drain(0.05)
            for _ in 0..<3 { h.superview.layoutIfNeeded() }
            XCTAssertEqual(scroll.contentSize.height, settled, accuracy: 0.5, "tick \(tick)")
            XCTAssertEqual(scroll.contentOffset.y, rest, accuracy: 0.5, "tick \(tick): the end moved")
        }
        h.drain(0.3)
        h.superview.layoutIfNeeded()
        XCTAssertEqual(scroll.contentSize.height, settled, accuracy: 0.5, "after rest")
        XCTAssertTrue(sizes.allSatisfy { abs($0 - settled) < 0.5 }, "content heights seen: \(sizes.sorted()), settled \(settled)")
    }

    /// A wrapping label hidden at first (outside a stack) measures when shown:
    /// it wraps to its container instead of keeping its unwrapped width.
    func testLabelShownLaterWrapsToItsContainer() throws {
        let h = RenderHarness(size: CGSize(width: 393, height: 852))
        try h.render("""
        { "type": "view", "id": "root",
          "content": {
            "variables": { "shown": { "type": "boolean", "initialValue": false } },
            "children": [
              { "type": "view", "id": "box",
                "content": {
                  "properties": { "isHidden": "{{!shown}}" },
                  "layout": { "constraints": [
                    { "type": "top", "target": "superview", "constant": 100 },
                    { "type": "leading", "target": "superview", "constant": 20 },
                    { "type": "trailing", "target": "superview", "constant": -20 }
                  ] },
                  "children": [
                    { "type": "label", "id": "para",
                      "content": {
                        "properties": { "text": "\(ScrollEndRestTests.paragraph)", "numberOfLines": 0 },
                        "style": { "text": { "fontSize": 17 } },
                        "layout": { "constraints": [
                          { "type": "top", "target": "superview" }, { "type": "bottom", "target": "superview" },
                          { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" }
                        ] } } }
                  ] } }
            ] } }
        """)
        settle(h)
        let vm = try XCTUnwrap(h.viewModel("root", as: CViewModel.self))
        try vm.variableStore.setValue(name: "shown", value: true)
        settle(h)
        var label: UILabel?
        func walk(_ v: UIView) { if let l = v as? UILabel, (l.text ?? l.attributedText?.string ?? "").hasPrefix("Sample") { label = l }; v.subviews.forEach(walk) }
        walk(h.superview)
        let l = try XCTUnwrap(label)
        XCTAssertLessThanOrEqual(l.bounds.width, 353 + 0.5, "fits its container")
        let needed = l.sizeThatFits(CGSize(width: l.bounds.width, height: .greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(l.bounds.height, 40, "wraps onto several lines")
        XCTAssertGreaterThanOrEqual(l.bounds.height + 1, needed, "shows all its lines")
    }
}
