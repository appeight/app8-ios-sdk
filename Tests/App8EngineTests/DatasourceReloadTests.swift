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

/// Serves `datasources/history` as `{ "entries": [...] }` (configurable).
private final class HistoryDataSource: App8DataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [[String: Any]] = []
    func set(_ list: [[String: Any]]) { lock.withLock { entries = list } }

    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data {
        let list = lock.withLock { entries }
        return try JSONSerialization.data(withJSONObject: ["data": ["entries": list]])
    }
}

@MainActor
final class DatasourceReloadTests: XCTestCase {

    /// An empty state and a filled state switched by `isHidden` expressions
    /// over a computed app variable that merges a persisted array with an
    /// app-scope datasource object: exactly one of them shows, before and
    /// after the source loads, with and without entries.
    func testEmptyAndFilledStatesFollowComputedAppVariable() async throws {
        let dataSource = HistoryDataSource()
        let harness = RenderHarness(dataSource: dataSource)
        let defs = try JSONDecoder().decode([String: VariableDefinition].self, from: Data("""
        {
            "h_local": { "type": "array", "initialValue": [] },
            "h_remote": { "type": "object", "initialValue": {}, "source": "datasources/history" },
            "h_all": { "type": "array", "computed": "{{uniqueBy(concat(h_local, h_remote.entries), 'id')}}" }
        }
        """.utf8))
        harness.service.defineAppVariables(defs, appId: "empty-filled-\(UUID().uuidString)")
        try harness.render("""
        {
            "id": "home", "type": "view",
            "content": {
                "variables": {
                    "latest": { "type": "object", "computed": "{{first(h_all)}}" },
                    "days": { "type": "number", "computed": "{{latest == null ? 0 : max(0, 7 - daysBetween(latest.createdAt, now()))}}" }
                },
                "layout": { "width": 390, "height": 844 },
                "children": [
                    { "id": "empty", "type": "view",
                      "content": { "properties": { "isHidden": "{{h_all.length > 0}}" }, "layout": { "top": 0, "leading": 0, "width": 100, "height": 100 } } },
                    { "id": "full", "type": "view",
                      "content": { "properties": { "isHidden": "{{h_all.length == 0}}" }, "layout": { "top": 0, "leading": 0, "width": 100, "height": 100 },
                        "children": [ { "id": "type", "type": "label", "content": { "properties": { "text": "{{latest.label}}" } } } ] } }
                ]
            }
        }
        """)
        let registry = harness.service.componentRegistry.viewRegistry
        func shown() -> [String] {
            ["home.empty", "home.full"].filter { registry.view(forId: $0)?.isHidden == false }
        }
        try await Task.sleep(nanoseconds: 200_000_000)  // main-queue hops run while the test awaits
        XCTAssertEqual(shown(), ["home.empty"], "before the source loads")
        try await Task.sleep(nanoseconds: 200_000_000)  // main-queue hops run while the test awaits
        XCTAssertEqual(shown(), ["home.empty"], "loaded, no entries")

        dataSource.set([["id": "a", "label": "Dry", "createdAt": "2026-11-10T09:00:00Z"]])
        let ok = await harness.service.reloadDatasource("datasources/history", screenId: "home")
        XCTAssertTrue(ok)
        let store = harness.service.appVariableStore
        XCTAssertEqual(((store.getValue(name: "h_remote") as? [String: Any])?["entries"] as? [Any])?.count, 1, "the source value")
        XCTAssertEqual((store.getValue(name: "h_all") as? [Any])?.count, 1, "the computed app variable follows the source")
        try await Task.sleep(nanoseconds: 200_000_000)  // main-queue hops run while the test awaits
        XCTAssertEqual(shown(), ["home.full"], "one entry")
    }

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

    func testNavigationBarButtonRunsAnyActionInTheScreenScope() async throws {
        let harness = RenderHarness(dataSource: CountingDataSource())
        let screen = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data("""
        {
            "id": "detail", "type": "screen",
            "content": {
                "variables": { "status": { "type": "string", "initialValue": "" } },
                "navigationBar": { "title": "Detail", "rightActions": [
                    { "icon": "trash", "action": { "type": "updateVariable", "variableName": "status", "value": "tapped" } }
                ] }
            }
        }
        """.utf8))
        let rendered = await harness.service.renderScreen(screen, screenId: "detail")
        let vc = try XCTUnwrap(rendered as? ScreenViewController)
        _ = vc.view
        let root = try XCTUnwrap(harness.viewModel("detail", as: CViewModel.self))
        let item = try XCTUnwrap(vc.navigationItem.rightBarButtonItems?.first)
        XCTAssertNotNil(item)
        let action = try JSONDecoder().decode(DSL.Model.Action.self, from: Data(#"{ "type": "updateVariable", "variableName": "status", "value": "tapped" }"#.utf8))
        vc.executeBarAction(action)
        XCTAssertEqual(root.variableStore.getValue(name: "status") as? String, "tapped", "not only navigation types run from a bar button")
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
