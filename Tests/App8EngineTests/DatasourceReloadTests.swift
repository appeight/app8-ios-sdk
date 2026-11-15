//
//  DatasourceReloadTests.swift
//  App8EngineTests
//
//  `reloadDatasource` (screen + app variables) and app variables with a
//  `source` loaded at app start.
//

import XCTest
@testable import App8Engine

/// Serves `datasources/items` with a version number that grows per fetch.
private final class CountingDataSource: App8DataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var fetches = 0
    private(set) var screenIds: [String] = []
    var fail = false

    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }

    var fetchCount: Int { lock.withLock { fetches } }

    func getDatasource(screenId: String, datasourceId: String) async throws -> Data {
        let n: Int = lock.withLock {
            fetches += 1
            screenIds.append(screenId)
            return fetches
        }
        if lock.withLock({ fail }) { throw URLError(.notConnectedToInternet) }
        guard datasourceId == "datasources/items" else { throw URLError(.fileDoesNotExist) }
        return Data(#"{ "data": [ { "id": "v\#(n)" } ] }"#.utf8)
    }
}

/// Caches `getDatasource` forever; only `reloadDatasource` returns new bytes.
private final class CachingDataSource: App8DataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var reloads = 0

    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }

    func getDatasource(screenId: String, datasourceId: String) async throws -> Data {
        Data(#"{ "data": [ { "id": "cached" } ] }"#.utf8)
    }

    func reloadDatasource(screenId: String, datasourceId: String) async throws -> Data {
        let n = lock.withLock { reloads += 1; return reloads }
        return Data(#"{ "data": [ { "id": "fresh\#(n)" } ] }"#.utf8)
    }
}

@MainActor
final class DatasourceReloadTests: XCTestCase {

    func testReloadUsesTheDataSourceReloadHook() async throws {
        let harness = RenderHarness(dataSource: CachingDataSource())
        let defs = try JSONDecoder().decode([String: VariableDefinition].self, from: Data("""
        { "catalog": { "type": "array", "initialValue": [], "source": "datasources/items" } }
        """.utf8))
        harness.service.defineAppVariables(defs, appId: "reload-hook-\(UUID().uuidString)")
        await waitFor { !ids(harness.service.appVariableStore.getValue(name: "catalog")).isEmpty }
        XCTAssertEqual(ids(harness.service.appVariableStore.getValue(name: "catalog")), ["cached"], "first load: the regular fetch")

        let ok = await harness.service.reloadDatasource("datasources/items", screenId: "")
        XCTAssertTrue(ok)
        XCTAssertEqual(ids(harness.service.appVariableStore.getValue(name: "catalog")), ["fresh1"], "reload bypasses the cache")
    }

    /// Polls without blocking the main actor (async tests run on it).
    private func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func ids(_ value: Any?) -> [String] {
        (value as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
    }

    func testAppVariableWithSourceLoadsAtStartAndReloads() async throws {
        let dataSource = CountingDataSource()
        let harness = RenderHarness(dataSource: dataSource)
        let defs = try JSONDecoder().decode([String: VariableDefinition].self, from: Data("""
        { "catalog": { "type": "array", "initialValue": [], "source": "datasources/items" } }
        """.utf8))
        harness.service.defineAppVariables(defs, appId: "reload-test-\(UUID().uuidString)")
        // Not blocking: the initial value is there right away.
        XCTAssertEqual(ids(harness.service.appVariableStore.getValue(name: "catalog")), [])
        await waitFor { !ids(harness.service.appVariableStore.getValue(name: "catalog")).isEmpty }
        XCTAssertEqual(ids(harness.service.appVariableStore.getValue(name: "catalog")), ["v1"])
        XCTAssertEqual(dataSource.screenIds.first, "", "app scope fetches with an empty screenId")

        let ok = await harness.service.reloadDatasource("datasources/items", screenId: "home")
        XCTAssertTrue(ok)
        XCTAssertEqual(ids(harness.service.appVariableStore.getValue(name: "catalog")), ["v2"])
    }

    func testPersistedValueShowsUntilSourceLoads() async throws {
        let appId = "reload-persist-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: VariablePersistence.suiteName(appId: appId)))
        defaults.set(try JSONSerialization.data(withJSONObject: [[["id": "stored"]]]), forKey: VariablePersistence.keyPrefix + "catalog")
        defer { defaults.removePersistentDomain(forName: VariablePersistence.suiteName(appId: appId)) }

        let harness = RenderHarness(dataSource: CountingDataSource())
        let defs = try JSONDecoder().decode([String: VariableDefinition].self, from: Data("""
        { "catalog": { "type": "array", "initialValue": [], "source": "datasources/items", "persist": true } }
        """.utf8))
        harness.service.defineAppVariables(defs, appId: appId)
        XCTAssertEqual(ids(harness.service.appVariableStore.getValue(name: "catalog")), ["stored"])
        await waitFor { ids(harness.service.appVariableStore.getValue(name: "catalog")) == ["v1"] }
        XCTAssertEqual(ids(harness.service.appVariableStore.getValue(name: "catalog")), ["v1"])
    }

    func testReloadDatasourceActionUpdatesScreenVariableAndRunsOnSuccess() async throws {
        let dataSource = CountingDataSource()
        let harness = RenderHarness(dataSource: dataSource)
        let screen = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data("""
        {
            "id": "list", "type": "screen",
            "content": {
                "variables": {
                    "items": { "type": "array", "source": "datasources/items" },
                    "status": { "type": "string", "initialValue": "" }
                }
            }
        }
        """.utf8))
        let vc = await harness.service.renderScreen(screen, screenId: "list")
        _ = vc.view
        let root = try XCTUnwrap(harness.viewModel("list", as: CViewModel.self))
        XCTAssertEqual(ids(root.variableStore.getValue(name: "items")), ["v1"])

        let action = try JSONDecoder().decode(DSL.Model.Action.self, from: Data("""
        { "type": "reloadDatasource", "source": "datasources/items",
          "onSuccess": { "type": "updateVariable", "variableName": "status", "value": "reloaded" },
          "onError": { "type": "updateVariable", "variableName": "status", "value": "failed" } }
        """.utf8))
        root.executeAction(action)
        await waitFor { (root.variableStore.getValue(name: "status") as? String) == "reloaded" }
        XCTAssertEqual(ids(root.variableStore.getValue(name: "items")), ["v2"])
        XCTAssertEqual(dataSource.screenIds.last, "list")

        dataSource.fail = true
        root.executeAction(action)
        await waitFor { (root.variableStore.getValue(name: "status") as? String) == "failed" }
        XCTAssertEqual(root.variableStore.getValue(name: "status") as? String, "failed")
        XCTAssertEqual(ids(root.variableStore.getValue(name: "items")), ["v2"], "a failed reload keeps the value")
    }
}
