//
//  ScrollReselectBounceTests.swift
//  App8EngineTests
//
//  navigation.md, "Reselecting the selected tab": tapping the selected tab
//  pops a pushed stack to its root; at the root it scrolls the screen's main
//  vertical scroll view (the outermost visible one, several containers deep
//  in a DSL screen) to its top rest position.
//  scroll-view.md, "Bounce": every vertical scroll view bounces, also when
//  its content fits, unless the DSL sets `bounces: false`.
//

import XCTest
@testable import App8Engine

@MainActor
final class ScrollReselectBounceTests: XCTestCase {

    // MARK: Reselect

    func testReselectWithAPushedScreenPopsToRoot() {
        let root = UIViewController()
        let nav = UINavigationController(rootViewController: root)
        nav.setViewControllers([root, UIViewController(), UIViewController()], animated: false)
        TabBarScreenViewController.handleReselect(of: nav, animated: false)
        XCTAssertEqual(nav.viewControllers.count, 1)
        XCTAssertTrue(nav.viewControllers.first === root)
    }

    func testReselectAtRootScrollsTheMainScrollViewToItsTop() {
        let screen = UIViewController()
        screen.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        // A hidden search grid first in the tree must not win over the list.
        let hidden = UIScrollView(frame: screen.view.bounds)
        hidden.contentSize = CGSize(width: 390, height: 3000)
        hidden.isHidden = true
        let container = UIView(frame: screen.view.bounds)
        let inner = UIView(frame: container.bounds)
        let list = UIScrollView(frame: inner.bounds)
        list.contentSize = CGSize(width: 390, height: 5000)
        list.contentInset.top = 12
        list.contentOffset.y = 2400
        // A sideways shelf inside the list is not the screen's scroll view.
        let shelf = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 200))
        shelf.contentSize = CGSize(width: 1200, height: 200)
        list.addSubview(shelf)
        inner.addSubview(list)
        container.addSubview(inner)
        screen.view.addSubview(hidden)
        screen.view.addSubview(container)

        XCTAssertTrue(TabBarScreenViewController.primaryScrollView(in: screen.view) === list)

        let nav = UINavigationController(rootViewController: screen)
        TabBarScreenViewController.handleReselect(of: nav)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertEqual(list.contentOffset.y, -list.adjustedContentInset.top, accuracy: 0.5)
        XCTAssertEqual(hidden.contentOffset.y, 0)
    }

    // MARK: Bounce

    private func scrollJSON(bounces: Bool?) -> String {
        let prop = bounces.map { #", "bounces": \#($0)"# } ?? ""
        return """
        { "type": "view", "id": "root",
          "content": { "layout": { "width": 390, "height": 844 },
            "children": [
              { "type": "scrollView", "id": "scroll",
                "content": {
                  "properties": { "direction": "vertical"\(prop) },
                  "layout": { "top": 0, "leading": 0, "width": 390, "height": 844 },
                  "children": [
                    { "type": "view", "id": "short",
                      "content": { "layout": { "height": 120, "constraints": [
                        { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
                        { "type": "trailing", "target": "superview" }, { "type": "bottom", "target": "superview" } ] } } }
                  ] } }
            ] } }
        """
    }

    private func scrollView(_ harness: RenderHarness) throws -> UIScrollView {
        let host = try XCTUnwrap(harness.find(CScrollViewView.self))
        return try XCTUnwrap(harness.find(UIScrollView.self, in: host))
    }

    func testAShortVerticalScrollViewStillBounces() throws {
        let harness = RenderHarness(inWindow: false)
        try harness.render(scrollJSON(bounces: nil))
        let scroll = try scrollView(harness)
        XCTAssertTrue(scroll.bounces)
        XCTAssertTrue(scroll.alwaysBounceVertical, "content shorter than the viewport must still bounce")
    }

    func testBouncesFalseTurnsBounceOff() throws {
        let harness = RenderHarness(inWindow: false)
        try harness.render(scrollJSON(bounces: false))
        let scroll = try scrollView(harness)
        XCTAssertFalse(scroll.bounces)
        XCTAssertFalse(scroll.alwaysBounceVertical)
    }
}
