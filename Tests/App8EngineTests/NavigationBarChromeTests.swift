import XCTest
import UIKit
@testable import App8Engine

/// The navigation bar and the content under it:
/// - a bar button's `navigation` action keeps its `presentation` (a sheet is
///   presented as a sheet, not pushed);
/// - a short vertical page starts below the bar (UIKit only insets a nested
///   scroll view for `.automatic` while its content overflows);
/// - on iOS 26 the bar tracks the page's scroll view and its top edge effect
///   is the soft one (progressive blur), not the hard band UIKit picks.
@MainActor
final class NavigationBarChromeTests: XCTestCase {
    private typealias DS = SearchFillsBarTests.BundleDataSource

    private static func bundle(homeChildren: [Any], rightAction: [String: Any]) -> [String: Any] {
        ["bundle": [
            "app": ["title": "T", "navigation": ["startFlow": "f", "flows": [["id": "f", "startScreen": "home"]]]],
            "styles": [], "components": [],
            "screens": [
                "home": ["type": "screen", "id": "home", "content": [
                    "navigationBar": ["title": "Home", "rightActions": [["icon": "questionmark.circle", "action": rightAction]]],
                    "children": homeChildren
                ] as [String: Any]],
                "info": ["type": "screen", "id": "info", "content": [
                    "navigationBar": ["hidden": true],
                    "children": [] as [Any]
                ] as [String: Any]]
            ] as [String: Any]
        ] as [String: Any]]
    }

    private static let shortPage: [String: Any] = [
        "type": "scrollView", "id": "page",
        "content": [
            "properties": ["direction": "vertical", "contentInsetAdjustment": "automatic"],
            "layout": ["constraints": [
                ["type": "top", "target": "superview"], ["type": "bottom", "target": "superview"],
                ["type": "leading", "target": "superview"], ["type": "trailing", "target": "superview"]
            ]],
            "children": [[
                "type": "view", "id": "box",
                "content": ["layout": ["height": 120, "constraints": [
                    ["type": "top", "target": "superview"], ["type": "bottom", "target": "superview"],
                    ["type": "leading", "target": "superview"], ["type": "trailing", "target": "superview"],
                    ["type": "width", "target": "superview"]
                ]]] as [String: Any]
            ]]
        ] as [String: Any]
    ]

    private func start(_ env: [String: Any]) async throws -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.makeKeyAndVisible()
        let instance = App8.instance(dataSource: try DS(envelope: env))
        window.rootViewController = try await instance.startApp()
        window.layoutIfNeeded()
        for _ in 0..<6 { try await Task.sleep(nanoseconds: 100_000_000) }
        return window
    }

    private func views(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(views) }

    private func homeScreen(in window: UIWindow) throws -> ScreenViewController {
        try XCTUnwrap(views(window).compactMap { $0.next as? ScreenViewController }.first { $0.screenId == "home" })
    }

    func testBarTintColorTintsBarButtons() async throws {
        var env = Self.bundle(homeChildren: [], rightAction: ["type": "dismiss"])
        var bundle = env["bundle"] as! [String: Any]
        var screens = bundle["screens"] as! [String: Any]
        var home = screens["home"] as! [String: Any]
        var content = home["content"] as! [String: Any]
        content["navigationBar"] = ["title": "Home", "tintColor": "#2D4D3A", "rightActions": [
            ["icon": "questionmark.circle", "action": ["type": "dismiss"]],
            ["icon": "trash", "style": "destructive", "action": ["type": "dismiss"]],
            ["icon": "star", "color": "#FF9500", "action": ["type": "dismiss"]],
        ]]
        home["content"] = content; screens["home"] = home; bundle["screens"] = screens; env["bundle"] = bundle
        let window = try await start(env)
        defer { window.rootViewController = nil }
        let screen = try homeScreen(in: window)
        let items = try XCTUnwrap(screen.navigationItem.rightBarButtonItems).reversed().map { $0 }
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].tintColor, UIColor(withHexString: "#2D4D3A"), "bar tintColor tints the button")
        XCTAssertEqual(items[1].tintColor, .systemRed, "destructive keeps red")
        XCTAssertEqual(items[2].tintColor, UIColor(withHexString: "#FF9500"), "an action's own color wins")
    }

    func testBarButtonSheetPresentsAsSheet() async throws {
        let action: [String: Any] = ["type": "navigation", "nextScreen": "info", "presentation": "sheet", "detents": ["large"], "grabber": true]
        let window = try await start(Self.bundle(homeChildren: [], rightAction: action))
        defer { window.rootViewController = nil }
        let home = try homeScreen(in: window)
        let nav = try XCTUnwrap(home.navigationController)
        let item = try XCTUnwrap(home.navigationItem.rightBarButtonItems?.first)
        item.primaryAction?.performWithSender(nil, target: nil)
        for _ in 0..<10 { try await Task.sleep(nanoseconds: 100_000_000) }

        XCTAssertEqual(nav.viewControllers.count, 1, "the sheet screen was pushed")
        let presented = try XCTUnwrap(window.rootViewController?.presentedViewController ?? nav.presentedViewController, "nothing presented")
        XCTAssertEqual(presented.modalPresentationStyle, .pageSheet)
        XCTAssertEqual(presented.sheetPresentationController?.prefersGrabberVisible, true)
        presented.dismiss(animated: false)
    }

    func testShortVerticalPageStartsBelowBar() async throws {
        let window = try await start(Self.bundle(homeChildren: [Self.shortPage], rightAction: ["type": "dismiss"]))
        defer { window.rootViewController = nil }
        let home = try homeScreen(in: window)
        let bar = try XCTUnwrap(home.navigationController?.navigationBar)
        let scroll = try XCTUnwrap(views(home.view).compactMap { $0 as? UIScrollView }.first { $0.contentSize.height > 0 })
        let barBottom = bar.convert(bar.bounds, to: window).maxY
        // The content's origin (scroll view bounds space), at rest.
        let contentTop = scroll.convert(CGPoint.zero, to: window).y
        XCTAssertGreaterThan(barBottom, 40)
        XCTAssertEqual(contentTop, barBottom, accuracy: 1, "content top \(contentTop), bar bottom \(barBottom)")
    }

    func testBarTracksPageScrollViewOnIOS26() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("iOS 26 bar") }
        // The page sits a few containers deep, as DSL pages do.
        let nested: [String: Any] = ["type": "view", "id": "outer", "content": [
            "layout": ["constraints": [
                ["type": "top", "target": "superview"], ["type": "bottom", "target": "superview"],
                ["type": "leading", "target": "superview"], ["type": "trailing", "target": "superview"]
            ]],
            "children": [Self.shortPage]
        ] as [String: Any]]
        let window = try await start(Self.bundle(homeChildren: [nested], rightAction: ["type": "dismiss"]))
        defer { window.rootViewController = nil }
        let home = try homeScreen(in: window)
        let page = try XCTUnwrap(views(home.view).compactMap { $0 as? UIScrollView }.first)
        // Without a tracked scroll view the bar draws a blurred band instead
        // of the scroll view's edge effect.
        XCTAssertTrue(home.contentScrollView(for: .top) === page, "bar tracks \(String(describing: home.contentScrollView(for: .top)))")
        // Left automatic, UIKit draws the hard style here: a solid band.
        XCTAssertTrue(page.topEdgeEffect.style == .soft, "top edge \(page.topEdgeEffect.style)")
    }
}
