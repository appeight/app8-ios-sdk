//
//  TopEdgeEffectTests.swift
//  App8EngineTests
//
//  The top scroll-edge effect (iOS 26+) is UIKit's own UIScrollEdgeEffect:
//  `navigationBar.topEdgeEffect` maps one to one to its style, `hidden` hides
//  it, and App8 draws nothing of its own over or under the bar.
//

import XCTest
import UIKit
@testable import App8Engine

@MainActor
final class TopEdgeEffectTests: XCTestCase {
    private typealias DS = SearchFillsBarTests.BundleDataSource

    nonisolated static func fill(_ hex: String) -> String {
        #"{ "material": [ { "id": "f", "type": "fill", "content": { "solid": "\#(hex)" } } ] }"#
    }

    nonisolated static func row(_ i: Int) -> String {
        """
        { "type": "label", "id": "row\(i)", "content": {
            "properties": { "text": "Row \(i): the quick brown fox jumps over the lazy dog" },
            "style": { "text": { "fontSize": 17, "numberOfLines": 0 } } } }
        """
    }

    nonisolated static func page(_ i: Int, _ colors: [String]) -> String {
        let stripes = colors.enumerated().map { j, c in
            """
            { "type": "view", "id": "p\(i)s\(j)", "content": { "style": \(fill(c)), "layout": { "height": 60 } } }
            """
        }.joined(separator: ",")
        return """
        { "type": "stackView", "id": "page\(i)", "content": {
            "properties": { "axis": "vertical" },
            "layout": { "width": 402 },
            "children": [ \(stripes) ] } }
        """
    }

    /// An edge-to-edge 480pt carousel of striped pages, then text rows.
    nonisolated static let heroScreen: String = {
        let palette = ["#1E3A5F", "#F2C14E", "#F78154", "#4D9078", "#B4436C", "#5FAD56", "#2E86AB", "#A23B72"]
        let pages = (0..<3).map { page($0, palette.shuffledDeterministic($0)) }.joined(separator: ",")
        let rows = (0..<24).map(row).joined(separator: ",")
        return """
        { "type": "screen", "id": "hero", "content": {
          "navigationBar": { "title": "Detail", "rightActions": [ { "icon": "heart", "action": { "type": "dismiss" } } ] },
          "children": [
            { "type": "scrollView", "id": "page", "content": {
                "properties": { "direction": "vertical", "contentInsetAdjustment": "never" },
                "layout": { "constraints": [
                  { "type": "top", "target": "superview" }, { "type": "bottom", "target": "superview" },
                  { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" } ] },
                "children": [
                  { "type": "stackView", "id": "column", "content": {
                      "properties": { "axis": "vertical", "spacing": 12 },
                      "layout": { "constraints": [
                        { "type": "top", "target": "superview" }, { "type": "bottom", "target": "superview" },
                        { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" },
                        { "type": "width", "target": "superview" } ] },
                      "children": [
                        { "type": "scrollView", "id": "carousel", "content": {
                            "properties": { "direction": "horizontal", "pagingEnabled": true, "showsIndicator": false },
                            "layout": { "height": 480 },
                            "children": [
                              { "type": "stackView", "id": "pages", "content": {
                                  "properties": { "axis": "horizontal" },
                                  "layout": { "constraints": [
                                    { "type": "top", "target": "superview" }, { "type": "bottom", "target": "superview" },
                                    { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" },
                                    { "type": "height", "target": "superview" } ] },
                                  "children": [ \(pages) ] } }
                            ] } },
                        \(rows)
                      ] } }
                ] } }
          ] } }
        """
    }()

    nonisolated static let listScreen: String = {
        let rows = (0..<30).map(row).joined(separator: ",")
        return """
        { "type": "screen", "id": "list", "content": {
          "navigationBar": { "title": "List" },
          "children": [
            { "type": "scrollView", "id": "page", "content": {
                "properties": { "direction": "vertical", "contentInsetAdjustment": "automatic" },
                "layout": { "constraints": [
                  { "type": "top", "target": "superview" }, { "type": "bottom", "target": "superview" },
                  { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" } ] },
                "children": [
                  { "type": "stackView", "id": "column", "content": {
                      "properties": { "axis": "vertical", "spacing": 12 },
                      "layout": { "constraints": [
                        { "type": "top", "target": "superview" }, { "type": "bottom", "target": "superview" },
                        { "type": "leading", "target": "superview", "constant": 16 },
                        { "type": "trailing", "target": "superview", "constant": -16 },
                        { "type": "width", "target": "superview", "constant": -32 } ] },
                      "children": [ \(rows) ] } }
                ] } }
          ] } }
        """
    }()

    static func envelope(_ screenJSON: String, id: String) throws -> [String: Any] {
        let screen = try JSONSerialization.jsonObject(with: Data(screenJSON.utf8))
        return ["bundle": [
            "app": ["title": "T", "navigation": ["startFlow": "f", "flows": [["id": "f", "startScreen": id]]]],
            "styles": [], "components": [],
            "screens": [id: screen]
        ] as [String: Any]]
    }

    static func start(_ env: [String: Any]) async throws -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.makeKeyAndVisible()
        let instance = App8.instance(dataSource: try DS(envelope: env))
        window.rootViewController = try await instance.startApp()
        window.layoutIfNeeded()
        for _ in 0..<8 { try await Task.sleep(nanoseconds: 100_000_000) }
        return window
    }

    static func views(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(views) }

    static func screen(_ id: String, in window: UIWindow) throws -> ScreenViewController {
        try XCTUnwrap(views(window).compactMap { $0.next as? ScreenViewController }.first { $0.screenId == id })
    }

    /// Scrolls the screen's main scroll view `distance` points from rest.
    static func scroll(_ vc: ScreenViewController, to distance: CGFloat) async throws {
        let sv = try XCTUnwrap(ScreenViewController.firstVerticalScrollView(in: vc.rootContainerView))
        sv.setContentOffset(CGPoint(x: 0, y: distance - sv.adjustedContentInset.top), animated: false)
        sv.window?.layoutIfNeeded()
        for _ in 0..<4 { try await Task.sleep(nanoseconds: 100_000_000) }
    }

    /// Scroll views of the screen, the nested horizontal carousel included.
    private func scrollViews(_ vc: ScreenViewController) -> [UIScrollView] {
        Self.views(vc.rootContainerView).compactMap { $0 as? UIScrollView }
    }

    /// Views App8 added to the screen outside its content: none (no overlay,
    /// tint or backdrop of its own between the content and the bar).
    private func chromeOverlays(_ vc: ScreenViewController) -> [UIView] {
        Self.views(vc.view).filter { v in
            v !== vc.view && !v.isDescendant(of: vc.rootContainerView)
                && (v is UIVisualEffectView || v.layer is CAGradientLayer
                    || (v.backgroundColor.map { $0.cgColor.alpha > 0.01 } ?? false))
        }
    }

    func testDefaultIsTheSystemEffect() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("iOS 26 edge effect") }
        for (json, id) in [(Self.listScreen, "list"), (Self.heroScreen, "hero")] {
            let window = try await Self.start(try Self.envelope(json, id: id))
            let vc = try Self.screen(id, in: window)
            for distance: CGFloat in [0, 200, 700] {
                try await Self.scroll(vc, to: distance)
                for sv in scrollViews(vc) {
                    XCTAssertFalse(sv.topEdgeEffect.isHidden, "\(id) @\(distance): \(sv)")
                    XCTAssertEqual(sv.topEdgeEffect.style, .automatic, "\(id) @\(distance)")
                }
                XCTAssertEqual(chromeOverlays(vc), [], "\(id) @\(distance)")
            }
            window.rootViewController = nil
        }
    }

    func testAuthoredStylesMapToTheSystemStyles() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("iOS 26 edge effect") }
        let cases: [(String, UIScrollEdgeEffect.Style?)] = [("automatic", .automatic), ("soft", .soft), ("hard", .hard), ("hidden", nil)]
        for (value, expected) in cases {
            let screenJSON = Self.listScreen.replacingOccurrences(
                of: #""navigationBar": { "title": "List" }"#,
                with: #""navigationBar": { "title": "List", "topEdgeEffect": "\#(value)" }"#)
            let window = try await Self.start(try Self.envelope(screenJSON, id: "list"))
            let vc = try Self.screen("list", in: window)
            try await Self.scroll(vc, to: 200)
            let page = try XCTUnwrap(ScreenViewController.firstVerticalScrollView(in: vc.rootContainerView))
            if let expected {
                XCTAssertFalse(page.topEdgeEffect.isHidden, value)
                XCTAssertEqual(page.topEdgeEffect.style, expected, value)
            } else {
                for sv in scrollViews(vc) { XCTAssertTrue(sv.topEdgeEffect.isHidden, value) }
            }
            XCTAssertEqual(chromeOverlays(vc), [], value)
            window.rootViewController = nil
        }
    }

    func testStyleMapping() {
        guard #available(iOS 26.0, *) else { return }
        XCTAssertEqual(ScreenViewController.systemTopEdgeStyle(.automatic), .automatic)
        XCTAssertEqual(ScreenViewController.systemTopEdgeStyle(.soft), .soft)
        XCTAssertEqual(ScreenViewController.systemTopEdgeStyle(.hard), .hard)
        XCTAssertNil(ScreenViewController.systemTopEdgeStyle(.hidden))
    }
}

private extension Array {
    func shuffledDeterministic(_ seed: Int) -> [Element] {
        guard !isEmpty else { return self }
        let k = (seed * 3) % count
        return Array(self[k...] + self[..<k])
    }
}
