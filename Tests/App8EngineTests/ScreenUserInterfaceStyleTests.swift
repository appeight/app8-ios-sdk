//
//  ScreenUserInterfaceStyleTests.swift
//  App8EngineTests
//
//  Screen-level `userInterfaceStyle` ("light" | "dark"): decoding (lenient),
//  the screen's own override, the navigation bar and status bar following the
//  top screen across push and pop, and presented alerts.
//

import XCTest
import UIKit
@testable import App8Engine

@MainActor
final class ScreenUserInterfaceStyleTests: XCTestCase {
    private typealias DS = SearchFillsBarTests.BundleDataSource

    // MARK: - Decoding

    private func decodeStyle(_ value: String?) throws -> DSL.Model.App.UserInterfaceStyle? {
        let field = value.map { "\"userInterfaceStyle\": \($0)," } ?? ""
        let json = """
        { "type": "screen", "id": "s", "content": { \(field) "children": [] } }
        """
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(json.utf8))
        let entity: DSL.Model.Component.View.Entity = try XCTUnwrap(component.asConcreteEntity())
        return entity.content.userInterfaceStyle
    }

    func testDecodesLightAndDark() throws {
        XCTAssertEqual(try decodeStyle("\"light\""), .light)
        XCTAssertEqual(try decodeStyle("\"dark\""), .dark)
        XCTAssertEqual(try decodeStyle("\"dark\"")?.ui, .dark)
    }

    func testAbsentIsNil() throws {
        XCTAssertNil(try decodeStyle(nil))
        XCTAssertNil(try decodeStyle("null"))
    }

    func testUnknownValuesAreIgnored() throws {
        XCTAssertNil(try decodeStyle("\"purple\""))
        XCTAssertNil(try decodeStyle("\"Dark\""))
        XCTAssertNil(try decodeStyle("5"))
        XCTAssertNil(try decodeStyle("{ \"light\": true }"))
    }

    // MARK: - Screen view controller

    func testScreenOverridesAndKeepsItsStyleOverAppAppearance() {
        let context = App8Context()
        context.appearance.userInterfaceStyle = .light
        let dark = ScreenViewController(navigationBar: nil, userInterfaceStyle: .dark, context: context)
        let plain = ScreenViewController(navigationBar: nil, context: context)
        _ = dark.view; _ = plain.view
        XCTAssertEqual(dark.overrideUserInterfaceStyle, .dark)
        XCTAssertEqual(plain.overrideUserInterfaceStyle, .light)
        XCTAssertEqual(dark.preferredStatusBarStyle, .lightContent)

        context.appearance.userInterfaceStyle = .unspecified
        XCTAssertEqual(dark.overrideUserInterfaceStyle, .dark, "the screen's own style wins over the host's")
        XCTAssertEqual(plain.overrideUserInterfaceStyle, .unspecified)

        let light = ScreenViewController(navigationBar: nil, userInterfaceStyle: .light, context: context)
        _ = light.view
        XCTAssertEqual(light.overrideUserInterfaceStyle, .light)
        XCTAssertEqual(light.preferredStatusBarStyle, .darkContent)
    }

    // MARK: - Push / pop in a light app

    private static func envelope() -> [String: Any] {
        let fill: [String: Any] = ["light": "#F3F4F6", "dark": "#1F2937"]
        func card(_ id: String) -> [String: Any] {
            ["type": "view", "id": id, "content": [
                "style": ["material": [["id": "cardFill", "type": "fill", "content": ["solid": fill]]]],
                "layout": ["height": 80, "constraints": [
                    ["type": "top", "target": "safeArea"],
                    ["type": "leading", "target": "superview"], ["type": "trailing", "target": "superview"]
                ]]
            ] as [String: Any]]
        }
        return ["bundle": [
            "app": ["title": "T", "defaultUserInterfaceStyle": "light",
                    "navigation": ["startFlow": "f", "flows": [["id": "f", "startScreen": "home"]]]],
            "styles": [], "components": [],
            "screens": [
                "home": ["type": "screen", "id": "home", "content": [
                    "navigationBar": ["title": "Home"],
                    "children": [card("homeCard")]
                ] as [String: Any]],
                "darkScreen": ["type": "screen", "id": "darkScreen", "content": [
                    "userInterfaceStyle": "dark",
                    "navigationBar": ["title": "Dark", "rightActions": [["icon": "heart", "action": ["type": "dismiss"]]]],
                    "children": [card("darkCard")]
                ] as [String: Any]]
            ] as [String: Any]
        ] as [String: Any]]
    }

    private func start() async throws -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.makeKeyAndVisible()
        let instance = App8.instance(dataSource: try DS(envelope: Self.envelope()))
        window.rootViewController = try await instance.startApp()
        window.layoutIfNeeded()
        for _ in 0..<6 { try await Task.sleep(nanoseconds: 100_000_000) }
        return window
    }

    private func views(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(views) }

    private func screen(_ id: String, in window: UIWindow) throws -> ScreenViewController {
        try XCTUnwrap(views(window).compactMap { $0.next as? ScreenViewController }.first { $0.screenId == id })
    }

    /// The controller UIKit asks for the status bar style.
    private func statusBarController(_ window: UIWindow) -> UIViewController? {
        var vc = window.rootViewController
        while let child = vc?.childForStatusBarStyle { vc = child }
        return vc
    }

    /// Any layer in `view` (its own or a fill sublayer) painted `color`.
    private func paints(_ view: UIView, _ color: UIColor) -> Bool {
        func rgba(_ c: UIColor) -> [CGFloat] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return [r, g, b, a]
        }
        let target = rgba(color)
        func layers(_ l: CALayer) -> [CALayer] { [l] + (l.sublayers ?? []).flatMap(layers) }
        var colors = layers(view.layer).compactMap { $0.backgroundColor.map(UIColor.init(cgColor:)) }
        if let bg = view.backgroundColor { colors.append(bg.resolvedColor(with: view.traitCollection)) }
        return colors.contains { zip(rgba($0), target).allSatisfy { abs($0 - $1) < 0.01 } }
    }

    private func settle(_ nav: UINavigationController, count: Int) async throws {
        for _ in 0..<40 {
            if nav.viewControllers.count == count, nav.transitionCoordinator == nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    func testDarkScreenDrivesChromeAndPopRestoresLight() async throws {
        let window = try await start()
        defer { window.rootViewController = nil }
        let home = try screen("home", in: window)
        let nav = try XCTUnwrap(home.navigationController)
        let bar = nav.navigationBar

        XCTAssertEqual(home.traitCollection.userInterfaceStyle, .light)
        XCTAssertEqual(bar.traitCollection.userInterfaceStyle, .light)
        XCTAssertTrue(statusBarController(window) === home)
        XCTAssertNotEqual(statusBarController(window)?.preferredStatusBarStyle, .lightContent)

        NotificationCenter.default.post(name: .app8NavigationRequest,
                                        object: NavigationRequest(type: .push(screenId: "darkScreen", params: [:])))
        try await settle(nav, count: 2)

        let dark = try XCTUnwrap(nav.topViewController as? ScreenViewController)
        XCTAssertEqual(dark.screenId, "darkScreen")
        XCTAssertEqual(dark.overrideUserInterfaceStyle, .dark)
        XCTAssertEqual(dark.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(bar.overrideUserInterfaceStyle, .dark)
        XCTAssertEqual(bar.traitCollection.userInterfaceStyle, .dark, "the navigation bar follows the top screen")
        XCTAssertTrue(statusBarController(window) === dark)
        XCTAssertEqual(statusBarController(window)?.preferredStatusBarStyle, .lightContent)

        // {light, dark} colours inside the screen resolve dark.
        let card = try XCTUnwrap(views(dark.view).first { $0.accessibilityIdentifier == "darkCard" })
        XCTAssertEqual(card.traitCollection.userInterfaceStyle, .dark)
        let darkHex = try XCTUnwrap(UIColor(withHexString: "#1F2937"))
        XCTAssertTrue(paints(card, darkHex), "the card paints the dark side of its colour")
        XCTAssertFalse(paints(card, try XCTUnwrap(UIColor(withHexString: "#F3F4F6"))))

        // The light root below is unaffected.
        XCTAssertEqual(home.traitCollection.userInterfaceStyle, .light)

        NotificationCenter.default.post(name: .app8NavigationRequest, object: NavigationRequest(type: .pop))
        try await settle(nav, count: 1)

        XCTAssertTrue(nav.topViewController === home)
        XCTAssertNotEqual(bar.overrideUserInterfaceStyle, .dark)
        XCTAssertEqual(bar.traitCollection.userInterfaceStyle, .light, "popping back restores the light bar")
        XCTAssertTrue(statusBarController(window) === home)
        XCTAssertNotEqual(statusBarController(window)?.preferredStatusBarStyle, .lightContent)
    }

    func testAlertFromDarkScreenIsDark() async throws {
        let window = try await start()
        defer { window.rootViewController = nil }
        let root = try XCTUnwrap(window.rootViewController)
        let nav = try XCTUnwrap(try screen("home", in: window).navigationController)

        NotificationCenter.default.post(name: .app8NavigationRequest,
                                        object: NavigationRequest(type: .push(screenId: "darkScreen", params: [:])))
        try await settle(nav, count: 2)

        // The engine presents from the window's root (light): the alert takes
        // the dark screen's style.
        let darkAlert = UIAlertController(title: "b", message: nil, preferredStyle: .alert)
        root.app8PresentInScreenStyle(darkAlert, animated: false)
        XCTAssertEqual(darkAlert.overrideUserInterfaceStyle, .dark)
        XCTAssertEqual(darkAlert.traitCollection.userInterfaceStyle, .dark)
        root.dismiss(animated: false)
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    func testAlertFromLightScreenFollowsApp() async throws {
        let window = try await start()
        defer { window.rootViewController = nil }
        let root = try XCTUnwrap(window.rootViewController)

        // From the light root: left to the app's style.
        let lightAlert = UIAlertController(title: "a", message: nil, preferredStyle: .alert)
        root.app8PresentInScreenStyle(lightAlert, animated: false)
        XCTAssertEqual(lightAlert.overrideUserInterfaceStyle, .unspecified)
        XCTAssertEqual(lightAlert.traitCollection.userInterfaceStyle, .light)
        root.dismiss(animated: false)
        try await Task.sleep(nanoseconds: 300_000_000)
    }
}
