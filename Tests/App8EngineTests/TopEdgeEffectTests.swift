//
//  TopEdgeEffectTests.swift
//  App8EngineTests
//
//  The top scroll-edge effect (iOS 26+): nothing at rest; it fades in over
//  16pt once content reaches the bar's bottom edge. Over a hero (an
//  edge-to-edge carousel at the top) only once the hero's bottom gets there.
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

    private typealias Rule = ScreenTopEdgeEffect
    private typealias F = ScreenTopEdgeEffect.Frame
    private let screen = CGSize(width: 402, height: 874)

    // MARK: - Rule

    func testHeroStartsWhenItsBottomReachesTheBar() {
        let frames = [F(x: 0, y: 0, w: 402, h: 480), F(x: 16, y: 492, w: 370, h: 40)]
        XCTAssertEqual(Rule.edgeEffectStart(frames, barBottom: 116, screen: screen), 364)
    }

    func testNoHeroStartsWhenFirstContentReachesTheBar() {
        // Content right under the bar: at once.
        XCTAssertEqual(Rule.edgeEffectStart([F(x: 16, y: 116, w: 370, h: 40)], barBottom: 116, screen: screen), 0)
        // Content further down: once it gets to the bar.
        XCTAssertEqual(Rule.edgeEffectStart([F(x: 16, y: 200, w: 370, h: 40), F(x: 16, y: 260, w: 370, h: 40)], barBottom: 116, screen: screen), 84)
        // Content already under the bar (no hero): at once.
        XCTAssertEqual(Rule.edgeEffectStart([F(x: 16, y: 20, w: 370, h: 40)], barBottom: 116, screen: screen), 0)
        XCTAssertEqual(Rule.edgeEffectStart([], barBottom: 116, screen: screen), 0)
    }

    func testNotAHero() {
        // Not full width, not from the top, not taller than the bar, or (nearly) the whole screen.
        for f in [F(x: 16, y: 0, w: 370, h: 480), F(x: 0, y: 40, w: 402, h: 480),
                  F(x: 0, y: 0, w: 402, h: 100), F(x: 0, y: 0, w: 402, h: 800)] {
            XCTAssertEqual(Rule.heroScrollDistance([f], barBottom: 116, screen: screen), 0, "\(f)")
        }
    }

    func testFadesInOverSixteenPoints() {
        XCTAssertEqual(Rule.visibility(scrolled: 0, start: 0), 0)
        XCTAssertEqual(Rule.visibility(scrolled: 8, start: 0), 0.5)
        XCTAssertEqual(Rule.visibility(scrolled: 16, start: 0), 1)
        XCTAssertEqual(Rule.visibility(scrolled: -40, start: 0), 0)
        XCTAssertEqual(Rule.visibility(scrolled: 363, start: 364), 0)
        XCTAssertEqual(Rule.visibility(scrolled: 372, start: 364), 0.5)
        XCTAssertEqual(Rule.visibility(scrolled: 600, start: 364), 1)
    }

    // MARK: - Screens

    private func alpha(_ vc: ScreenViewController) -> CGFloat { vc.topEdgeEffectOverlay?.alpha ?? -1 }

    func testHeroScreen() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("iOS 26 edge effect") }
        let window = try await Self.start(try Self.envelope(Self.heroScreen, id: "hero"))
        defer { window.rootViewController = nil }
        let vc = try Self.screen("hero", in: window)
        let bar = try XCTUnwrap(vc.navigationController?.navigationBar)
        let start = 480 - bar.convert(bar.bounds, to: vc.view).maxY
        XCTAssertEqual(alpha(vc), 0, "at rest")
        try await Self.scroll(vc, to: 200)
        XCTAssertEqual(alpha(vc), 0, "hero still under the bar")
        try await Self.scroll(vc, to: start + 8)
        XCTAssertEqual(alpha(vc), 0.5, accuracy: 0.05, "half way into the ramp")
        try await Self.scroll(vc, to: start + 40)
        XCTAssertEqual(alpha(vc), 1, "hero gone")
        for sv in Self.views(vc.view).compactMap({ $0 as? UIScrollView }) {
            XCTAssertTrue(sv.topEdgeEffect.isHidden, "system effect shown on \(sv)")
        }
    }

    func testListScreen() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("iOS 26 edge effect") }
        let window = try await Self.start(try Self.envelope(Self.listScreen, id: "list"))
        defer { window.rootViewController = nil }
        let vc = try Self.screen("list", in: window)
        XCTAssertEqual(alpha(vc), 0, "at rest")
        try await Self.scroll(vc, to: 8)
        XCTAssertEqual(alpha(vc), 0.5, accuracy: 0.05)
        try await Self.scroll(vc, to: 200)
        XCTAssertEqual(alpha(vc), 1)
    }

    func testHiddenAndHard() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("iOS 26 edge effect") }
        for (value, expected) in [("hidden", nil), ("hard", ScreenTopEdgeEffect.Style.hard)] as [(String, ScreenTopEdgeEffect.Style?)] {
            let screenJSON = Self.listScreen.replacingOccurrences(
                of: #""navigationBar": { "title": "List" }"#,
                with: #""navigationBar": { "title": "List", "topEdgeEffect": "\#(value)" }"#)
            let window = try await Self.start(try Self.envelope(screenJSON, id: "list"))
            let vc = try Self.screen("list", in: window)
            XCTAssertEqual(vc.topEdgeEffectOverlay?.style, expected, value)
            for sv in Self.views(vc.view).compactMap({ $0 as? UIScrollView }) {
                XCTAssertTrue(sv.topEdgeEffect.isHidden, value)
            }
            window.rootViewController = nil
        }
    }
}

private extension Array {
    func shuffledDeterministic(_ seed: Int) -> [Element] {
        guard !isEmpty else { return self }
        let k = (seed * 3) % count
        return Array(self[k...] + self[..<k])
    }
}
