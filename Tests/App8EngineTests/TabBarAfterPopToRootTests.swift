import XCTest
import UIKit
@testable import App8Engine

/// An exit action list on a screen that hides the tab bar —
/// `[navigation back toRoot, selectTab]` — runs its steps one after another:
/// the tab switch waits for the pop to finish, so UIKit never switches tabs
/// (an animated transition of its own on iOS 26) in the middle of a pop that
/// brings the tab bar back.
///
/// Logic tests have no host app, and there UIKit never finishes the animated
/// tab switch; the tests check the order of the steps and the bar on the stack
/// that was popped.
@MainActor
final class TabBarAfterPopToRootTests: XCTestCase {
    typealias DS = SearchFillsBarTests.BundleDataSource

    private func bundle() -> [String: Any] {
        let screens: [String: Any] = [
            "tabs": ["type": "tabBarScreen", "id": "tabs", "content": [
                "tabs": [["id": "shop", "label": "Shop", "icon": "house", "screen": "shop"],
                         ["id": "cart", "label": "Cart", "icon": "bag", "screen": "cart"]],
                "initialTab": "shop"] as [String: Any]],
            "shop": ["type": "screen", "id": "shop", "content": [
                "navigationBar": ["title": "Shop"], "children": [] as [Any]] as [String: Any]],
            "cart": ["type": "screen", "id": "cart", "content": [
                "navigationBar": ["title": "Cart"], "children": [] as [Any]] as [String: Any]]
        ]
        return ["bundle": [
            "app": ["title": "T", "navigation": ["startFlow": "f", "flows": [["id": "f", "startScreen": "tabs"]]]],
            "styles": [], "components": [], "screens": screens
        ] as [String: Any]]
    }

    private var window: UIWindow!
    private var instance: App8.Instance!

    override func tearDown() async throws {
        window?.rootViewController = nil
        window = nil
        instance = nil
    }

    private func all(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(all) }

    private func start() async throws -> UITabBarController {
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.makeKeyAndVisible()
        instance = App8.instance(dataSource: try DS(envelope: bundle()))
        window.rootViewController = try await instance.startApp()
        window.layoutIfNeeded()
        for _ in 0..<8 { try await Task.sleep(nanoseconds: 100_000_000) }
        let screen = try XCTUnwrap(all(window).compactMap { $0.next as? ScreenViewController }.first)
        return try XCTUnwrap(screen.tabBarController)
    }

    private func render(_ id: String) async throws -> ScreenViewController {
        let json = ##"{"type":"screen","id":"\##(id)","content":{"hidesTabBar":true,"navigationBar":{"title":"\##(id)"},"children":[]}}"##
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(json.utf8))
        let service = try XCTUnwrap((instance as? A8)?.appService)
        let vc = await service.renderScreen(component, screenId: id)
        return try XCTUnwrap(vc as? ScreenViewController)
    }

    private func settle(_ nav: UINavigationController) async throws {
        for _ in 0..<60 where nav.transitionCoordinator != nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        window.layoutIfNeeded()
    }

    /// Shop root → scan home → report, both hiding the bar (as the skin-scan
    /// screens are pushed).
    private func pushHidingScreens(on tabs: UITabBarController) async throws -> UINavigationController {
        let nav = try XCTUnwrap(tabs.selectedViewController as? UINavigationController)
        nav.pushViewController(try await render("scanHome"), animated: true)
        try await settle(nav)
        nav.pushViewController(try await render("scanReport"), animated: true)
        try await settle(nav)
        XCTAssertTrue(tabs.tabBar.isHidden, "precondition: the report hides the bar")
        return nav
    }

    private func post(_ type: NavigationRequestType) {
        NotificationCenter.default.post(name: .app8NavigationRequest, object: NavigationRequest(type: type))
    }

    /// Runs `[first, selectTab id]` as one action list does, and samples until
    /// the tab is selected: the switch must not land while `nav` still animates.
    private func runThenSelect(_ first: NavigationRequestType, tab: String, index: Int,
                               on tabs: UITabBarController, nav: UINavigationController,
                               file: StaticString = #filePath, line: UInt = #line) async throws {
        let selectedBefore = tabs.selectedIndex
        post(first)
        post(.selectTab(index: nil, id: tab))
        var sawTransition = false
        for _ in 0..<150 {
            if nav.transitionCoordinator != nil { sawTransition = true }
            if index != selectedBefore, tabs.selectedIndex == index {
                XCTAssertNil(nav.transitionCoordinator, "the tab switched while the pop was still running", file: file, line: line)
                break
            }
            if index == selectedBefore, sawTransition, nav.transitionCoordinator == nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(sawTransition, "the pop animates", file: file, line: line)
        XCTAssertEqual(tabs.selectedIndex, index, file: file, line: line)
    }

    // MARK: - [back toRoot, selectTab]

    /// "View bag": back to the Shop root, then the Cart tab.
    func testSelectOtherTabWaitsForPopToRoot() async throws {
        let tabs = try await start()
        let nav = try await pushHidingScreens(on: tabs)
        try await runThenSelect(.popToRoot, tab: "cart", index: 1, on: tabs, nav: nav)
        XCTAssertEqual(nav.viewControllers.count, 1)
        XCTAssertFalse(tabs.tabBar.isHidden, "tab bar hidden")
        XCTAssertEqual(tabs.tabBar.transform, .identity)
    }

    /// "Back to shop": back to the Shop root, then the (already selected) Shop tab.
    func testSelectSameTabAfterPopToRoot() async throws {
        let tabs = try await start()
        let nav = try await pushHidingScreens(on: tabs)
        try await runThenSelect(.popToRoot, tab: "shop", index: 0, on: tabs, nav: nav)
        try await settle(nav)
        XCTAssertEqual(nav.viewControllers.count, 1)
        let bar = tabs.tabBar
        XCTAssertFalse(bar.isHidden, "tab bar hidden")
        XCTAssertEqual(bar.transform, .identity, "tab bar left below the screen")
        let frame = bar.convert(bar.bounds, to: window)
        XCTAssertLessThan(frame.minY, window.bounds.maxY - 20, "tab bar below the screen: \(frame)")
        let root = try XCTUnwrap(nav.viewControllers.first)
        XCTAssertGreaterThan(root.view.safeAreaInsets.bottom, 40, "the root screen does not lay out for the bar")
    }

    /// A single back step from the screen above the root, then another tab.
    func testSelectOtherTabWaitsForPop() async throws {
        let tabs = try await start()
        let nav = try XCTUnwrap(tabs.selectedViewController as? UINavigationController)
        nav.pushViewController(try await render("scanReport"), animated: true)
        try await settle(nav)
        try await runThenSelect(.pop, tab: "cart", index: 1, on: tabs, nav: nav)
        XCTAssertEqual(nav.viewControllers.count, 1)
        XCTAssertFalse(tabs.tabBar.isHidden, "tab bar hidden")
        XCTAssertEqual(tabs.tabBar.transform, .identity)
    }

    /// A tab switch that arrives while a push still animates waits for it.
    func testSelectTabWaitsForARunningPush() async throws {
        let tabs = try await start()
        let nav = try XCTUnwrap(tabs.selectedViewController as? UINavigationController)
        let report = try await render("scanReport")
        nav.pushViewController(report, animated: true)
        XCTAssertNotNil(nav.transitionCoordinator)
        post(.selectTab(index: nil, id: "cart"))
        for _ in 0..<150 where tabs.selectedIndex != 1 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(tabs.selectedIndex, 1)
        XCTAssertTrue(nav.topViewController === report)
        XCTAssertNil(nav.transitionCoordinator, "the tab switched while the push was still running")
    }
}
