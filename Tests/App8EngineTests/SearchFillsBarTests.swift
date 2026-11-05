import XCTest
import UIKit
@testable import App8Engine

/// Regression for the facetheory shop/cart/account "hang": the preview host
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

    /// facetheory shop: integrated + fillsBar search inside a tab crashed the
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
}
