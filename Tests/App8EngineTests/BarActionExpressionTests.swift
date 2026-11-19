import XCTest
import UIKit
@testable import App8Engine

/// Bar items (navigation.md, Bar Action): `icon`, `label` and `color` are
/// expressions in the screen's scope and follow their variables. The item is
/// updated in place: the same `UIBarButtonItem` gets the new image, title or tint.
@MainActor
final class BarActionExpressionTests: XCTestCase {
    private typealias DS = SearchFillsBarTests.BundleDataSource

    private static func bundle(navigationBar: [String: Any]) -> [String: Any] {
        ["bundle": [
            "app": ["title": "T", "navigation": ["startFlow": "f", "flows": [["id": "f", "startScreen": "home"]]]],
            "styles": [], "components": [],
            "screens": [
                "home": ["type": "screen", "id": "home", "content": [
                    "variables": [
                        "liked": ["type": "array", "initialValue": [] as [Any]],
                        "product": ["type": "object", "initialValue": ["handle": "p1"]],
                    ] as [String: Any],
                    "navigationBar": navigationBar,
                    "children": [] as [Any]
                ] as [String: Any]]
            ] as [String: Any]
        ] as [String: Any]]
    }

    private static let heart = "{{includes(liked, product.handle) ? 'heart.fill' : 'heart'}}"
    private static let toggle: [[String: Any]] = [
        ["type": "toggleArrayValue", "variableName": "liked", "value": "{{product.handle}}"],
        ["type": "haptic", "hapticStyle": "light"],
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

    private func settle() async throws {
        for _ in 0..<3 { try await Task.sleep(nanoseconds: 100_000_000) }
    }

    func testRightActionsIconFollowsVariable() async throws {
        let window = try await start(Self.bundle(navigationBar: ["title": "Product", "rightActions": [
            ["icon": Self.heart, "color": "{{includes(liked, product.handle) ? '#FF2D55' : '#000000'}}", "action": Self.toggle],
            ["icon": "square.and.arrow.up", "action": ["type": "dismiss"]],
        ]]))
        defer { window.rootViewController = nil }
        let screen = try homeScreen(in: window)
        let items = try XCTUnwrap(screen.navigationItem.rightBarButtonItems).reversed().map { $0 }
        XCTAssertEqual(items.count, 2)
        let like = items[0]
        XCTAssertEqual(like.image, UIImage(systemName: "heart"), "resolved, not the raw expression")
        XCTAssertEqual(like.tintColor, UIColor(withHexString: "#000000"))

        like.primaryAction?.performWithSender(nil, target: nil)
        try await settle()
        let after = try XCTUnwrap(screen.navigationItem.rightBarButtonItems).reversed().map { $0 }
        XCTAssertTrue(after[0] === like, "the same item is updated in place")
        XCTAssertEqual(like.image, UIImage(systemName: "heart.fill"))
        XCTAssertEqual(like.tintColor, UIColor(withHexString: "#FF2D55"))
        XCTAssertEqual(items[1].image, UIImage(systemName: "square.and.arrow.up"))

        like.primaryAction?.performWithSender(nil, target: nil)
        try await settle()
        XCTAssertEqual(like.image, UIImage(systemName: "heart"), "toggles back")
    }

    func testSingleRightActionAndLeftActionLabelFollowVariables() async throws {
        let window = try await start(Self.bundle(navigationBar: [
            "title": "Product",
            "leftAction": ["label": "{{liked.length}} saved", "action": ["type": "dismiss"]],
            "rightAction": ["icon": Self.heart, "action": Self.toggle],
        ]))
        defer { window.rootViewController = nil }
        let screen = try homeScreen(in: window)
        let left = try XCTUnwrap(screen.navigationItem.leftBarButtonItem)
        let right = try XCTUnwrap(screen.navigationItem.rightBarButtonItems?.first)
        XCTAssertEqual(left.title, "0 saved")
        XCTAssertEqual(right.image, UIImage(systemName: "heart"))

        right.primaryAction?.performWithSender(nil, target: nil)
        try await settle()
        XCTAssertEqual(left.title, "1 saved")
        XCTAssertEqual(right.image, UIImage(systemName: "heart.fill"))
    }
}
