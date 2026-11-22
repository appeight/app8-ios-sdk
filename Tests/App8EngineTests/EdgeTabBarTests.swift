import XCTest
import UIKit
@testable import App8Engine

/// `barStyle.shape: "edge"` (tab-bar-screen.md, "Edge stripe"): a full-width
/// square stripe flush with the bottom edge, `height` above the bottom safe
/// area; tab screens' bottom safe area is that height plus the device inset;
/// a `hidesTabBar` push hides it and its inset.
@MainActor
final class EdgeTabBarTests: XCTestCase {
    typealias DS = SearchFillsBarTests.BundleDataSource

    private func bundle() -> [String: Any] {
        let screens: [String: Any] = [
            "tabs": ["type": "tabBarScreen", "id": "tabs", "content": [
                "tabs": [["id": "home", "label": "HOME", "icon": "house", "screen": "home"],
                         ["id": "bag", "label": "BAG", "icon": "bag", "screen": "bag", "badge": "3"]],
                "initialTab": "home", "badgeColor": "#FFFFFF", "badgeTextColor": "#000000",
                "barStyle": ["variant": "text", "shape": "edge", "height": 32, "background": "#000000",
                             "selection": "opacity", "unselectedOpacity": 0.3]] as [String: Any]],
            "home": ["type": "screen", "id": "home", "content": [
                "navigationBar": ["hidden": true], "children": [] as [Any]] as [String: Any]],
            "bag": ["type": "screen", "id": "bag", "content": [
                "navigationBar": ["hidden": true], "children": [] as [Any]] as [String: Any]]
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

    private func start() async throws -> (UITabBarController, ScreenViewController) {
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.makeKeyAndVisible()
        instance = App8.instance(dataSource: try DS(envelope: bundle()))
        window.rootViewController = try await instance.startApp()
        window.layoutIfNeeded()
        for _ in 0..<8 { try await Task.sleep(nanoseconds: 100_000_000) }
        window.layoutIfNeeded()
        let screen = try XCTUnwrap(all(window).compactMap { $0.next as? ScreenViewController }.first)
        return (try XCTUnwrap(screen.tabBarController), screen)
    }

    private func settle(_ nav: UINavigationController) async throws {
        for _ in 0..<60 where nav.transitionCoordinator != nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        window.layoutIfNeeded()
    }

    func testStripeIsFlushFullWidthAndOwnsTheSafeArea() async throws {
        let (tabs, home) = try await start()
        XCTAssertTrue(tabs.tabBar.isHidden, "the system bar (platter, glass, lens) is not shown")
        let stripe = try XCTUnwrap(all(tabs.view).compactMap { $0 as? StyledTabBarView }.first)
        XCTAssertTrue(stripe.superview === tabs.view)
        let device = tabs.view.safeAreaInsets.bottom
        let frame = stripe.convert(stripe.bounds, to: tabs.view)
        XCTAssertEqual(frame.minX, 0)
        XCTAssertEqual(frame.width, tabs.view.bounds.width)
        XCTAssertEqual(frame.height, 32)
        XCTAssertEqual(frame.maxY + device, tabs.view.bounds.maxY, accuracy: 0.5, "height above the bottom safe area")
        XCTAssertEqual(stripe.bottomExtension, device, "its background runs under the home indicator")
        XCTAssertEqual(home.view.safeAreaInsets.bottom, 32 + device, accuracy: 0.5)
        XCTAssertEqual(home.tabStripeInset, 32)
    }

    func testHidesTabBarPushHidesTheStripeAndItsInset() async throws {
        let (tabs, home) = try await start()
        let nav = try XCTUnwrap(home.navigationController)
        let json = ##"{"type":"screen","id":"detail","content":{"hidesTabBar":true,"navigationBar":{"hidden":true},"children":[]}}"##
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(json.utf8))
        let service = try XCTUnwrap((instance as? A8)?.appService)
        let rendered = await service.renderScreen(component, screenId: "detail")
        let detail = try XCTUnwrap(rendered as? ScreenViewController)
        nav.pushViewController(detail, animated: true)
        try await settle(nav)
        let stripe = try XCTUnwrap(all(tabs.view).compactMap { $0 as? StyledTabBarView }.first)
        let device = tabs.view.safeAreaInsets.bottom
        XCTAssertFalse(detail.hidesBottomBarWhenPushed, "UIKit's own hiding is taken over")
        XCTAssertTrue(detail.app8HidesTabBar)
        XCTAssertTrue(tabs.tabBar.isHidden)
        XCTAssertEqual(detail.tabStripeInset, 0)
        XCTAssertEqual(detail.view.safeAreaInsets.bottom, device, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(stripe.frame.minY, tabs.view.bounds.maxY, "slid below the bottom edge")
        nav.popViewController(animated: true)
        try await settle(nav)
        XCTAssertEqual(stripe.transform, .identity)
        XCTAssertEqual(home.view.safeAreaInsets.bottom, 32 + device, accuracy: 0.5)
    }
}
