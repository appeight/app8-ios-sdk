import XCTest
import UIKit
@testable import App8Engine

/// Regression for the demostore shop/cart/account "hang": the preview host
/// never produced a render because the app crashed. `navigationBar.search`
/// with `placement: integrated` + `fillsBar: true` moved
/// `searchBarPlacementBarButtonItem` into `leftBarButtonItems`, which UIKit
/// rejects on iPhone (iOS 26.2) with NSInvalidArgumentException
/// "only supported in UIToolbar" from `viewWillAppear`.
/// A regression shows up as the test process crashing (uncaught ObjC exception).
@MainActor
final class SearchFillsBarTests: XCTestCase {
    final class BundleDataSource: App8DataSource, @unchecked Sendable {
        let app: Data; let styles: [Data]; let components: [Data]
        let screens: [String: Data]; let datasources: [String: [String: Data]]
        init(envelope: [String: Any]) throws {
            let b = envelope["bundle"] as! [String: Any]
            func d(_ v: Any) throws -> Data { try JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed]) }
            app = try d(b["app"]!)
            styles = try (b["styles"] as? [Any] ?? []).map(d)
            components = try (b["components"] as? [Any] ?? []).map(d)
            screens = try (b["screens"] as! [String: Any]).mapValues(d)
            datasources = try (b["datasources"] as? [String: [String: Any]] ?? [:]).mapValues { try $0.mapValues(d) }
        }
        func getApp() async throws -> Data { app }
        func getStyles() async throws -> [Data] { styles }
        func getComponents() async throws -> [Data] { components }
        func getComponent(componentId: String) async throws -> Data { throw URLError(.fileDoesNotExist) }
        func getScreen(screenId: String) async throws -> Data { guard let s = screens[screenId] else { throw URLError(.fileDoesNotExist) }; return s }
        func getDatasource(screenId: String, datasourceId: String) async throws -> Data {
            guard let d = datasources[screenId]?[datasourceId] else { throw URLError(.fileDoesNotExist) }; return d
        }
        func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
        func getAllScreenIds() async throws -> [String]? { Array(screens.keys) }
        func streamScreen(screenId: String) -> AsyncStream<Data>? { nil }
        func streamDatasource(screenId: String, datasourceId: String, componentPath: String?) -> AsyncStream<Data>? { nil }
        func streamStyles() -> AsyncStream<Data>? { nil }
    }

    private static func startAndSettle(_ ds: App8DataSource) async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.makeKeyAndVisible()
        let instance = App8.instance(dataSource: ds)
        let root = try await instance.startApp()
        window.rootViewController = root
        window.layoutIfNeeded()
        for _ in 0..<5 { try await Task.sleep(nanoseconds: 100_000_000) }
        window.rootViewController = nil
    }

    private static func searchScreen() -> [String: Any] {
        ["type": "screen", "id": "shop", "content": [
            "navigationBar": ["search": ["placeholder": "Search", "bindVariable": "q", "placement": "integrated", "fillsBar": true]],
            "variables": ["q": ["type": "string", "initialValue": ""]],
            "children": [] as [Any]
        ] as [String: Any]]
    }

    /// demostore shop: integrated + fillsBar search inside a tab crashed the
    /// host (NSInvalidArgumentException "only supported in UIToolbar").
    func testFillsBarSearchInTabDoesNotThrow() async throws {
        let env: [String: Any] = ["bundle": [
            "app": ["title": "T", "navigation": ["startFlow": "f", "flows": [["id": "f", "startScreen": "tabs"]]]],
            "styles": [], "components": [],
            "screens": [
                "tabs": ["type": "tabBarScreen", "id": "tabs", "content": [
                    "tabs": [["id": "shop", "label": "Shop", "icon": "magnifyingglass", "screen": "shop"]],
                    "initialTab": "shop"] as [String: Any]],
                "shop": Self.searchScreen()
            ] as [String: Any]
        ] as [String: Any]]
        try await Self.startAndSettle(try BundleDataSource(envelope: env))
    }

    func testFillsBarSearchPlainScreenDoesNotThrow() async throws {
        let env: [String: Any] = ["bundle": [
            "app": ["title": "T", "navigation": ["startFlow": "f", "flows": [["id": "f", "startScreen": "shop"]]]],
            "styles": [], "components": [],
            "screens": ["shop": Self.searchScreen()] as [String: Any]
        ] as [String: Any]]
        try await Self.startAndSettle(try BundleDataSource(envelope: env))
    }

    /// DemoStore shop: the fillsBar field is centred with equal side gaps,
    /// floats 10pt below the status bar, and content starts 10pt below it.
    func testFillsBarSearchGeometry() async throws {
        guard #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iOS 26 iPhone layout") }
        let env: [String: Any] = ["bundle": [
            "app": ["title": "T", "navigation": ["startFlow": "f", "flows": [["id": "f", "startScreen": "tabs"]]]],
            "styles": [], "components": [],
            "screens": [
                "tabs": ["type": "tabBarScreen", "id": "tabs", "content": [
                    "tabs": [["id": "shop", "label": "Shop", "icon": "magnifyingglass", "screen": "shop"]],
                    "initialTab": "shop"] as [String: Any]],
                "shop": Self.searchScreen()
            ] as [String: Any]
        ] as [String: Any]]
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.makeKeyAndVisible()
        let instance = App8.instance(dataSource: try BundleDataSource(envelope: env))
        window.rootViewController = try await instance.startApp()
        window.layoutIfNeeded()
        for _ in 0..<8 { try await Task.sleep(nanoseconds: 100_000_000) }
        defer { window.rootViewController = nil }

        func all(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(all) }
        let views = all(window)
        let field = try XCTUnwrap(views.compactMap { $0 as? UISearchTextField }.first)
        let screen = try XCTUnwrap(views.compactMap { $0.next as? ScreenViewController }.first)
        let frame = field.convert(field.bounds, to: window)
        let safeTop = window.safeAreaInsets.top

        XCTAssertEqual(frame.minX, window.bounds.width - frame.maxX, accuracy: 0.5, "side gaps \(frame)")
        XCTAssertEqual(frame.minY, safeTop + 10, accuracy: 0.5, "top gap \(frame)")
        XCTAssertEqual(screen.view.safeAreaInsets.top, frame.maxY + 10, accuracy: 0.5, "content top")
    }
    /// DemoStore shop -> product (push) and back (pop): the shop's fillsBar
    /// gap moves the shared navigation bar, so the bar has to stay where it is
    /// across the transition. It used to be dropped by the pushed screen, and
    /// UIKit applied that only once the transition finished: the back button
    /// jumped 10pt up right after the push, the field 10pt down after the pop.
    func testFillsBarGapKeepsBarStillAcrossPushAndPop() async throws {
        guard #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iOS 26 iPhone layout") }
        let env: [String: Any] = ["bundle": [
            "app": ["title": "T", "navigation": ["startFlow": "f", "flows": [["id": "f", "startScreen": "tabs"]]]],
            "styles": [], "components": [],
            "screens": [
                "tabs": ["type": "tabBarScreen", "id": "tabs", "content": [
                    "tabs": [["id": "shop", "label": "Shop", "icon": "magnifyingglass", "screen": "shop"]],
                    "initialTab": "shop"] as [String: Any]],
                "shop": Self.searchScreen()
            ] as [String: Any]
        ] as [String: Any]]
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.makeKeyAndVisible()
        let instance = App8.instance(dataSource: try BundleDataSource(envelope: env))
        window.rootViewController = try await instance.startApp()
        window.layoutIfNeeded()
        for _ in 0..<8 { try await Task.sleep(nanoseconds: 100_000_000) }
        defer { window.rootViewController = nil }

        func all(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(all) }
        let shop = try XCTUnwrap(all(window).compactMap { $0.next as? ScreenViewController }.first)
        let nav = try XCTUnwrap(shop.navigationController)
        func barFrame() -> CGRect {
            nav.view.layoutIfNeeded()
            return nav.navigationBar.convert(nav.navigationBar.bounds, to: window)
        }
        /// Waits for the transition to finish, then samples the bar at
        /// completion and again one run loop later.
        func settle(on top: UIViewController) async throws -> (CGRect, CGRect) {
            for _ in 0..<40 where nav.topViewController !== top || nav.transitionCoordinator != nil {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertTrue(nav.topViewController === top)
            let atEnd = barFrame()
            try await Task.sleep(nanoseconds: 50_000_000)
            return (atEnd, barFrame())
        }

        let start = barFrame()
        XCTAssertEqual(start.minY, window.safeAreaInsets.top + 10, accuracy: 0.5, "shop bar \(start)")

        let detailJSON = ##"{"type":"screen","id":"detail","content":{"navigationBar":{"tintColor":"#2D4D3A"},"children":[]}}"##
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(detailJSON.utf8))
        let service = try XCTUnwrap((instance as? A8)?.appService)
        let detail = await service.renderScreen(component, screenId: "detail")

        nav.pushViewController(detail, animated: true)
        let (pushEnd, pushNext) = try await settle(on: detail)
        XCTAssertEqual(pushEnd, start, "bar moved by the push")
        XCTAssertEqual(pushNext, pushEnd, "bar jumped after the push")

        nav.popViewController(animated: true)
        let (popEnd, popNext) = try await settle(on: shop)
        XCTAssertEqual(popEnd, start, "bar moved by the pop")
        XCTAssertEqual(popNext, popEnd, "bar jumped after the pop")
    }
}
