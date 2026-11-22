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

    /// The bar style under test (default: the edge stripe).
    private var barStyle: [String: Any] = ["variant": "text", "shape": "edge", "height": 32, "background": "#000000",
                                           "selection": "opacity", "unselectedOpacity": 0.3]
    private var bagBadge = "3"
    private var styles: [Any] = []

    private func bundle() -> [String: Any] {
        let screens: [String: Any] = [
            "tabs": ["type": "tabBarScreen", "id": "tabs", "content": [
                "tabs": [["id": "home", "label": "HOME", "icon": "house", "screen": "home"],
                         ["id": "saved", "label": "SAVED", "icon": "star", "screen": "home", "badge": "2"],
                         ["id": "bag", "label": "BAG", "icon": "bag", "screen": "bag", "badge": bagBadge]],
                "initialTab": "home", "badgeColor": "#FFFFFF", "badgeTextColor": "#000000",
                "barStyle": barStyle] as [String: Any]],
            "home": ["type": "screen", "id": "home", "content": [
                "navigationBar": ["hidden": true], "children": [] as [Any]] as [String: Any]],
            "bag": ["type": "screen", "id": "bag", "content": [
                "navigationBar": ["hidden": true], "children": [] as [Any]] as [String: Any]]
        ]
        return ["bundle": [
            "app": ["title": "T", "navigation": ["startFlow": "f", "flows": [["id": "f", "startScreen": "tabs"]]]],
            "styles": styles, "components": [], "screens": screens
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

    // MARK: - Flat floating bar

    private func useFloating() {
        barStyle = ["variant": "text", "shape": "floating", "background": "#000000", "cornerRadius": 0, "height": 32,
                    "selection": "opacity", "unselectedOpacity": 0.3, "badgePlacement": "inline",
                    "text": ["fontSize": 12, "fontWeight": "semibold", "color": "#FFFFFF"]]
        bagBadge = "12"
    }

    func testFlatFloatingBarHasThePlatterFrame() async throws {
        useFloating()
        let (tabs, home) = try await start()
        XCTAssertTrue(tabs.tabBar.isHidden, "a non-glass bar is engine-drawn")
        let bar = try XCTUnwrap(all(tabs.view).compactMap { $0 as? StyledTabBarView }.first)
        let frame = bar.convert(bar.bounds, to: tabs.view)
        let device = tabs.view.safeAreaInsets.bottom
        let expected = TabBarScreenViewController.engineBarFrame(edge: false, height: 32, in: tabs.view.bounds.size, safeAreaBottom: device)
        XCTAssertEqual(frame.minX, 21)
        XCTAssertEqual(tabs.view.bounds.width - frame.maxX, 21)
        XCTAssertEqual(frame.height, 32)
        XCTAssertEqual(frame, expected)
        XCTAssertEqual(bar.bottomExtension, 0)
        XCTAssertEqual(home.view.safeAreaInsets.bottom, tabs.view.bounds.height - frame.minY, accuracy: 0.5,
                       "the tab screen's safe area reaches the bar's top edge")
        // Inline badges sit on the label's line, 4 pt after it.
        let badges = all(bar).compactMap { $0 as? UILabel }.filter { $0.text == "2" || $0.text == "12" }
        XCTAssertEqual(badges.count, 2)
        for badge in badges where !badge.isHidden {
            XCTAssertEqual(badge.frame.midY, bar.bounds.midY, accuracy: 0.5)
        }
        // A picture of the bar for review.
        tabs.view.backgroundColor = .white
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: tabs.view.bounds.width, height: 120))
        let image = renderer.image { ctx in
            ctx.cgContext.translateBy(x: 0, y: 120 - tabs.view.bounds.height)
            tabs.view.layer.render(in: ctx.cgContext)
        }
        try? image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/a8-flat-tabbar.png"))
    }

    // MARK: - Material background (blur + tint)

    private func all(_ v: CALayer) -> [CALayer] { [v] + (v.sublayers ?? []).flatMap(all) }

    /// `background` naming a material style (a blur layer and a tint) draws
    /// both on the engine-drawn bar.
    func testMaterialBackgroundDrawsBlurOnly() async throws {
        styles = [[["id": "tabBarBg", "type": "material", "content": [
            ["id": "tabBarBlur", "type": "visualEffect", "content": ["blur": "systemMaterialDark"]]]]]]
        barStyle = ["variant": "text", "shape": "floating", "background": "tabBarBg", "cornerRadius": 0, "height": 50,
                    "sideInset": 16, "bottomOffset": 10, "selection": "opacity", "unselectedOpacity": 0.3]
        let (tabs, _) = try await start()
        let bar = try XCTUnwrap(all(tabs.view).compactMap { $0 as? StyledTabBarView }.first)
        bar.layoutIfNeeded()
        let blur = all(bar).compactMap { $0 as? UIVisualEffectView }.first { $0.effect != nil }
        XCTAssertNotNil(blur, "a blur view")
        XCTAssertEqual(blur.map { $0.convert($0.bounds, to: bar).width } ?? 0, bar.bounds.width, accuracy: 1)
    }

    func testMaterialBackgroundDrawsBlurAndTint() async throws {
        styles = [[["id": "tabBarBg", "type": "material", "content": [
            ["id": "tabBarBlur", "type": "visualEffect", "content": ["blur": "systemMaterialDark"]],
            ["id": "tabBarTint", "type": "fill", "content": ["solid": "#00000080"]]]]]]
        barStyle = ["variant": "text", "shape": "floating", "background": "tabBarBg", "cornerRadius": 0, "height": 50,
                    "sideInset": 16, "bottomOffset": 10, "selection": "opacity", "unselectedOpacity": 0.3]
        let (tabs, _) = try await start()
        let bar = try XCTUnwrap(all(tabs.view).compactMap { $0 as? StyledTabBarView }.first)
        bar.layoutIfNeeded()
        let views = all(bar)
        let blur = views.compactMap { $0 as? UIVisualEffectView }.first { $0.effect != nil }
        XCTAssertNotNil(blur, "a blur view")
        if let blur {
            let frame = blur.convert(blur.bounds, to: bar)
            XCTAssertEqual(frame.width, bar.bounds.width, accuracy: 1, "the blur fills the bar")
            XCTAssertEqual(frame.height, bar.bounds.height, accuracy: 1)
            XCTAssertFalse(blur.isHidden)
            XCTAssertGreaterThan(blur.alpha, 0.5)
        }
        let tint = all(bar.layer).first { layer in
            guard let color = layer.backgroundColor.map(UIColor.init(cgColor:)) else { return false }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return abs(a - 0.5) < 0.02 && r < 0.01 && layer.bounds.width >= bar.bounds.width - 1
        }
        XCTAssertNotNil(tint, "a 50% black tint filling the bar")
        // The tint sits above the blur (array order), not under it.
        let material = try XCTUnwrap(all(bar).compactMap { $0 as? MaterialView }.first)
        XCTAssertEqual(material.stackedTypeKeys, [.visualEffect, .fill])
    }
}
