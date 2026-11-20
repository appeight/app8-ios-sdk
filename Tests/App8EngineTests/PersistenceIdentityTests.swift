import XCTest
import UIKit
@testable import App8Engine

/// Two apps opened in one host must not share `persist: true` values: the
/// storage is named by the host's id, then `id`, `bundleId`, `title`.
@MainActor
final class PersistenceIdentityTests: XCTestCase {

    private final class DataSource: App8DataSource, @unchecked Sendable {
        let app: Data
        let hostId: String?
        init(app: [String: Any], hostId: String?) throws {
            self.app = try JSONSerialization.data(withJSONObject: app)
            self.hostId = hostId
        }
        var persistenceId: String? { hostId }
        func getApp() async throws -> Data { app }
        func getStyles() async throws -> [Data] { [] }
        func getComponents() async throws -> [Data] { [] }
        func getComponent(componentId: String) async throws -> Data { throw URLError(.fileDoesNotExist) }
        func getScreen(screenId: String) async throws -> Data {
            Data(#"{ "id": "home", "type": "screen", "content": { "children": [] } }"#.utf8)
        }
        func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    }

    private func app(title: String, id: String? = nil) -> [String: Any] {
        var app: [String: Any] = [
            "title": title,
            "navigation": ["startFlow": "f", "flows": [["id": "f", "startScreen": "home"]]],
            "variables": ["cart": ["type": "array", "initialValue": [], "persist": true]],
        ]
        if let id { app["id"] = id }
        return app
    }

    private func decodeApp(_ json: String) throws -> DSL.Model.App {
        try JSONDecoder().decode(DSL.Model.App.self, from: Data(json.utf8))
    }

    func testPrecedenceHostThenIdThenBundleIdThenTitle() throws {
        let full = try decodeApp(#"{ "id": "app-id", "bundleId": "com.example.b", "title": "T" }"#)
        XCTAssertEqual(full.persistenceId(hostId: "host-1"), "host-1")
        XCTAssertEqual(full.persistenceId(hostId: nil), "app-id", "an app with an id keeps its storage")
        XCTAssertEqual(full.persistenceId(hostId: "  "), "app-id")
        XCTAssertEqual(try decodeApp(#"{ "bundleId": "com.example.b", "title": "T" }"#).persistenceId(hostId: nil), "com.example.b")
        XCTAssertEqual(try decodeApp(#"{ "title": "T" }"#).persistenceId(hostId: nil), "T")
    }

    func testDataSourceDefaultHasNoHostId() throws {
        final class Plain: App8DataSource, @unchecked Sendable {
            func getApp() async throws -> Data { Data() }
            func getStyles() async throws -> [Data] { [] }
            func getComponents() async throws -> [Data] { [] }
            func getScreen(screenId: String) async throws -> Data { Data() }
            func getComponent(componentId: String) async throws -> Data { Data() }
            func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
        }
        XCTAssertNil(Plain().persistenceId)
    }

    /// Starts an app and returns its instance with the cart it sees.
    private func start(_ ds: DataSource) async throws -> (A8, [Any]) {
        let instance = try XCTUnwrap(App8.instance(dataSource: ds) as? A8)
        _ = try await instance.startApp()
        let cart = instance.appService?.appVariableStore.getValue(name: "cart") as? [Any] ?? []
        return (instance, cart)
    }

    private func seed(_ persistenceId: String, cart: [Any]) throws -> UserDefaults {
        let suite = VariablePersistence.suiteName(appId: persistenceId)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(try JSONSerialization.data(withJSONObject: [cart]), forKey: VariablePersistence.keyPrefix + "cart")
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testAppsWithDifferentTitlesDoNotShareValues() async throws {
        let a = "Cart A \(UUID().uuidString)", b = "Cart B \(UUID().uuidString)"
        _ = try seed(a, cart: [["sku": "a1"]])
        addTeardownBlock { UserDefaults(suiteName: VariablePersistence.suiteName(appId: b))?.removePersistentDomain(forName: VariablePersistence.suiteName(appId: b)) }

        let (first, cartA) = try await start(try DataSource(app: app(title: a), hostId: nil))
        XCTAssertEqual(first.context.persistenceId, a)
        XCTAssertEqual(cartA.count, 1)
        let (second, cartB) = try await start(try DataSource(app: app(title: b), hostId: nil))
        XCTAssertEqual(second.context.persistenceId, b)
        XCTAssertTrue(cartB.isEmpty, "a cart from one app must not show in another")
    }

    func testHostIdsKeepAppsWithTheSameFieldsApart() async throws {
        let one = "host-\(UUID().uuidString)", two = "host-\(UUID().uuidString)"
        _ = try seed(one, cart: [["sku": "x"]])
        addTeardownBlock { UserDefaults(suiteName: VariablePersistence.suiteName(appId: two))?.removePersistentDomain(forName: VariablePersistence.suiteName(appId: two)) }

        // Same title (and no id): only the host's identity tells them apart.
        let (first, cartOne) = try await start(try DataSource(app: app(title: "Shop"), hostId: one))
        XCTAssertEqual(first.context.persistenceId, one)
        XCTAssertEqual(cartOne.count, 1)
        let (second, cartTwo) = try await start(try DataSource(app: app(title: "Shop"), hostId: two))
        XCTAssertEqual(second.context.persistenceId, two)
        XCTAssertTrue(cartTwo.isEmpty)
    }
}
