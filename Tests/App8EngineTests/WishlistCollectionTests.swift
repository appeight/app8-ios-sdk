//
//  WishlistCollectionTests.swift
//  App8EngineTests
//
//  A saved-items tab, end to end: a collection whose section reads
//  `{{filter(allProducts, wishlist.includes(item.handle))}}`, a heart button in
//  each card that toggles `wishlist`, an empty-state label, and a large
//  navigation-bar title, in a real tab bar.
//
//  Regressions covered:
//  - Un-hearting a card left it in the list (the section's dependency filter
//    took "filter(allProducts, wishlist" as the variable name, so a `wishlist`
//    change never rebuilt it), and the empty label then drew over stale cards.
//  - Hearting a product while the Wishlist tab was empty at launch never added
//    the card: with the header hidden under the bar, the tab looked blank.
//  - The screen header sat under the navigation bar until the list was nudged:
//    the tab's screen is laid out before its bar is shown, and the list kept
//    its pre-bar offset.
//

import XCTest
import UIKit
@testable import App8Engine

@MainActor
final class WishlistCollectionTests: XCTestCase {

    private static let productsJSON = (1...6)
        .map { #"{"id":"p\#($0)","handle":"h\#($0)","title":"Product \#($0)"}"# }
        .joined(separator: ",")

    /// The collection + empty label of the wishlist screen (a demo app's
    /// screens/wishlist.json, with inline templates instead of components).
    private static func children(products: String = "{{filter(allProducts, wishlist.includes(item.handle))}}") -> String { """
    [
      { "id": "wishlistGrid", "type": "collection",
        "content": {
          "properties": {
            "sectionDefinitions": [
              { "key": "intro", "data": "{{intro}}", "templateName": "intro" },
              { "key": "products", "data": "\(products)", "templateName": "card" }
            ],
            "layout": { "type": "vertical", "contentInsets": { "top": 0, "left": 0, "right": 0, "bottom": 40 } },
            "sectionLayouts": {
              "intro": { "type": "vertical", "estimatedItemHeight": 60 },
              "products": { "type": "grid", "columns": 2, "estimatedItemHeight": 300, "itemSpacing": 10, "lineSpacing": 10 }
            }
          },
          "templates": {
            "intro": { "id": "intro", "type": "view",
              "content": { "layout": { "height": 60 },
                "children": [
                  { "id": "introTitle", "type": "label",
                    "content": { "properties": { "text": "{{item.title}}" },
                      "layout": { "constraints": [ { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" } ] } } }
                ] } },
            "card": { "id": "card", "type": "view",
              "content": { "layout": { "height": 300 },
                "children": [
                  { "id": "cardTitle", "type": "label",
                    "content": { "properties": { "text": "{{item.title}}" },
                      "layout": { "constraints": [ { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" } ] } } },
                  { "id": "cardHeart", "type": "button",
                    "content": { "properties": { "text": "Heart" },
                      "actions": { "tap": [ { "type": "toggleArrayValue", "variableName": "wishlist", "value": "{{item.handle}}" } ] },
                      "layout": { "constraints": [ { "type": "bottom", "target": "superview" }, { "type": "leading", "target": "superview" } ] } } }
                ] } }
          },
          "layout": { "constraints": [
            { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
            { "type": "trailing", "target": "superview" }, { "type": "bottom", "target": "superview" } ] }
        } },
      { "id": "wishlistEmpty", "type": "label",
        "content": {
          "properties": { "text": "Your wishlist is empty", "isHidden": "{{length(wishlist) > 0}}" },
          "layout": { "constraints": [ { "type": "centerX", "target": "superview" }, { "type": "centerY", "target": "superview" } ] }
        } }
    ]
    """ }

    private static let wishlistChildren = children()

    private static let variablesJSON = """
    { "allProducts": { "type": "array", "initialValue": [\(productsJSON)] },
      "intro": { "type": "array", "initialValue": [ { "title": "Wishlist" } ] } }
    """

    private static func defineWishlist(_ handles: [String], in service: App8Service) throws {
        try service.appVariableStore.defineVariable(
            name: "wishlist",
            definition: VariableDefinition(type: .array, initialValue: handles)
        )
    }

    // MARK: - Helpers

    private static func first<T: UIView>(_ type: T.Type, in view: UIView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for sub in view.subviews { if let found = first(type, in: sub) { return found } }
        return nil
    }

    private static func all<T: UIView>(_ type: T.Type, in view: UIView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type, in: $0) }
    }

    private static func emptyLabel(in view: UIView) -> UILabel? {
        all(UILabel.self, in: view).first { $0.text == "Your wishlist is empty" }
    }

    /// Titles of the product cards the collection shows, in order.
    private static func cardTitles(_ cv: UICollectionView) -> [String] {
        cv.layoutIfNeeded()
        return cv.indexPathsForVisibleItems.filter { $0.section == 1 }.sorted().compactMap { ip in
            cv.cellForItem(at: ip).flatMap { first(UILabel.self, in: $0.contentView)?.text }
        }
    }

    private static func isVisible(_ view: UIView) -> Bool {
        var v: UIView? = view
        while let cur = v { if cur.isHidden || cur.alpha < 0.01 { return false }; v = cur.superview }
        return true
    }

    // MARK: - Removing and adding cards

    func testUnheartingACardRemovesItAndEmptyStateShowsAlone() throws {
        try runUnheartFlow(variables: Self.variablesJSON, children: Self.wishlistChildren)
    }

    /// The demo binds the section to a computed screen variable (works on
    /// engines before the dependency fix too); same behaviour.
    func testUnheartingWithAComputedSectionVariable() throws {
        let variables = Self.variablesJSON.replacingOccurrences(
            of: #""intro":"#,
            with: #""wishlistProducts": { "type": "array", "computed": "{{filter(allProducts, wishlist.includes(item.handle))}}" }, "intro":"#
        )
        try runUnheartFlow(variables: variables, children: Self.children(products: "{{wishlistProducts}}"))
    }

    private func runUnheartFlow(variables: String, children: String) throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 844))
        try Self.defineWishlist(["h1", "h2", "h3"], in: harness.service)
        try harness.render("""
        { "type": "view", "id": "wishlist",
          "content": { "properties": {}, "variables": \(variables),
            "layout": { "width": 390, "height": 844 }, "children": \(children) } }
        """)
        harness.drain()

        let cv = try XCTUnwrap(Self.first(UICollectionView.self, in: harness.superview))
        cv.layoutIfNeeded()
        harness.drain()
        XCTAssertEqual(cv.numberOfItems(inSection: 1), 3)
        XCTAssertEqual(Self.cardTitles(cv), ["Product 1", "Product 2", "Product 3"])

        // Tap the heart on the first card, as the user does.
        let firstCard = try XCTUnwrap(cv.cellForItem(at: IndexPath(item: 0, section: 1)))
        let heart = try XCTUnwrap(Self.first(UIButton.self, in: firstCard.contentView))
        harness.fire(heart, .touchUpInside)
        harness.drain()

        XCTAssertEqual(harness.service.appVariableStore.getValue(name: "wishlist") as? [String], ["h2", "h3"])
        XCTAssertEqual(cv.numberOfItems(inSection: 1), 2, "the un-hearted card must leave the list")
        XCTAssertEqual(Self.cardTitles(cv), ["Product 2", "Product 3"])

        // Un-heart the rest: no stale cards under the empty state.
        for _ in 0..<2 {
            let card = try XCTUnwrap(cv.cellForItem(at: IndexPath(item: 0, section: 1)))
            harness.fire(try XCTUnwrap(Self.first(UIButton.self, in: card.contentView)), .touchUpInside)
            harness.drain()
        }
        XCTAssertEqual(cv.numberOfItems(inSection: 1), 0)
        XCTAssertEqual(Self.cardTitles(cv), [])
        XCTAssertEqual(cv.numberOfItems(inSection: 0), 1, "the intro row stays")
        let empty = try XCTUnwrap(Self.emptyLabel(in: harness.superview))
        XCTAssertTrue(Self.isVisible(empty))
    }

    func testHeartingWhileEmptyAtLaunchAddsTheCard() throws {
        // The blank-screen report: empty wishlist at launch, a product hearted
        // elsewhere (the Shop tab), then the Wishlist tab: the empty label hid
        // (it reads `wishlist`) but the list never got the card.
        let harness = RenderHarness(size: CGSize(width: 390, height: 844))
        try Self.defineWishlist([], in: harness.service)
        try harness.render("""
        { "type": "view", "id": "wishlist",
          "content": { "properties": {}, "variables": \(Self.variablesJSON),
            "layout": { "width": 390, "height": 844 }, "children": \(Self.wishlistChildren) } }
        """)
        harness.drain()
        let cv = try XCTUnwrap(Self.first(UICollectionView.self, in: harness.superview))
        XCTAssertEqual(cv.numberOfItems(inSection: 1), 0)
        XCTAssertTrue(Self.isVisible(try XCTUnwrap(Self.emptyLabel(in: harness.superview))))

        try harness.service.appVariableStore.setValue(name: "wishlist", value: ["h4", "h2"])
        harness.drain()

        XCTAssertEqual(cv.numberOfItems(inSection: 1), 2)
        XCTAssertEqual(Self.cardTitles(cv), ["Product 2", "Product 4"], "cards follow allProducts order")
        XCTAssertFalse(Self.isVisible(try XCTUnwrap(Self.emptyLabel(in: harness.superview))))
    }

    func testRemovingCardsWhileScrolledDownKeepsContentOnScreen() throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 400))
        try Self.defineWishlist(["h1", "h2", "h3", "h4", "h5", "h6"], in: harness.service)
        try harness.render("""
        { "type": "view", "id": "wishlist",
          "content": { "properties": {}, "variables": \(Self.variablesJSON),
            "layout": { "width": 390, "height": 400 }, "children": \(Self.wishlistChildren) } }
        """)
        harness.drain()
        let cv = try XCTUnwrap(Self.first(UICollectionView.self, in: harness.superview))
        cv.layoutIfNeeded()
        let bottom = cv.contentSize.height + cv.adjustedContentInset.bottom - cv.bounds.height
        XCTAssertGreaterThan(bottom, 0)
        cv.contentOffset.y = bottom
        harness.drain()

        try harness.service.appVariableStore.setValue(name: "wishlist", value: ["h1"])
        harness.drain()
        cv.layoutIfNeeded()

        let maxY = max(-cv.adjustedContentInset.top, cv.contentSize.height + cv.adjustedContentInset.bottom - cv.bounds.height)
        XCTAssertLessThanOrEqual(cv.contentOffset.y, maxY + 0.5, "offset must stay inside the shorter content")
        XCTAssertEqual(Self.cardTitles(cv), ["Product 1"])
    }

    // MARK: - Large title, list at rest under the bar

    /// A tab's screen is rendered and laid out up front (`setupTabs`), off
    /// window: no safe area, list offset 0. Only when the tab is first shown
    /// does it get the status bar + navigation bar (+ large title) inset, and
    /// UIKit kept the old offset, so the top ~100pt sat under the bar until
    /// the list was nudged. (A logic-test window has no scene, so tab and
    /// navigation containment don't lay views out: the inset arrives here as
    /// `additionalSafeAreaInsets`, as the bars deliver it.)
    func testWishlistScreenShowsALargeTitleAndItsListRestsBelowTheBar() async throws {
        let context = App8Context()
        let service = App8Service(publicDataSource: StubDataSource(), context: context)
        Self.retained.append(service)
        // Taller than the screen, as a real wishlist: UIKit itself pulls a
        // shorter list back to its top on layout.
        try Self.defineWishlist(["h1", "h2", "h3", "h4", "h5", "h6"], in: service)
        let component = try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: Data("""
        { "type": "screen", "id": "wishlist",
          "content": { "navigationBar": { "title": "Wishlist", "largeTitle": true },
            "variables": \(Self.variablesJSON), "children": \(Self.wishlistChildren) } }
        """.utf8))
        let rendered = await service.renderScreen(component, screenId: "wishlist")
        let screen = try XCTUnwrap(rendered as? ScreenViewController)
        try await Task.sleep(nanoseconds: 300_000_000)

        // Large title configuration.
        let nav = UINavigationController(rootViewController: screen)
        nav.setNavigationBarHidden(true, animated: false)
        XCTAssertTrue(nav.navigationBar.prefersLargeTitles, "set when the screen joins its navigation controller")
        XCTAssertEqual(screen.navigationItem.largeTitleDisplayMode, .always)
        XCTAssertEqual(screen.title, "Wishlist")
        let pushed = ScreenViewController(navigationBar: nil, context: context)
        pushed.loadViewIfNeeded()
        XCTAssertEqual(pushed.navigationItem.largeTitleDisplayMode, .never, "other screens in the stack stay inline")

        let cv = try XCTUnwrap(Self.first(UICollectionView.self, in: screen.view))
        screen.view.layoutIfNeeded()
        XCTAssertTrue(screen.contentScrollView(for: .top) === cv, "the large title follows the list")
        XCTAssertEqual(cv.contentOffset.y, 0, accuracy: 0.5, "laid out off-window: no inset yet")

        // The tab is shown: the bars' inset arrives.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        nav.setViewControllers([], animated: false)
        window.rootViewController = screen
        screen.view.frame = window.bounds
        screen.additionalSafeAreaInsets.top = 116
        screen.view.layoutIfNeeded()
        cv.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertGreaterThanOrEqual(cv.adjustedContentInset.top, 116)
        XCTAssertEqual(cv.contentOffset.y, -cv.adjustedContentInset.top, accuracy: 0.5,
                       "the list rests at its top: nothing under the bar")
        let firstCard = try XCTUnwrap(cv.cellForItem(at: IndexPath(item: 0, section: 1)))
        XCTAssertGreaterThanOrEqual(firstCard.convert(firstCard.bounds, to: window).minY, 116 - 0.5)
        XCTAssertEqual(Array(Self.cardTitles(cv).prefix(2)), ["Product 1", "Product 2"])
    }

    private static var retained: [App8Service] = []
}

private final class StubDataSource: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data { Data() }
}
