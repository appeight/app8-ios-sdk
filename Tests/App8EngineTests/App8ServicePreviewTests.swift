//
//  App8ServicePreviewTests.swift
//  App8EngineTests
//
//  App8Service resolves preview values as a fallback when a variable
//  is not provided via navigation params.
//

import XCTest
@testable import App8Engine

private final class PreviewTrackingDataSource: App8DataSource, @unchecked Sendable {
    var datasources: [String: Data] = [:]
    var getDatasourceCalls: [(screenId: String, datasourceId: String)] = []

    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }

    func getDatasource(screenId: String, datasourceId: String) async throws -> Data {
        getDatasourceCalls.append((screenId: screenId, datasourceId: datasourceId))
        guard let data = datasources[datasourceId] else {
            throw NSError(domain: "test", code: 404, userInfo: [NSLocalizedDescriptionKey: "Not found: \(datasourceId)"])
        }
        return data
    }
}

@MainActor
final class App8ServicePreviewTests: XCTestCase {

    private var mockDS: PreviewTrackingDataSource!
    private var service: App8Service!

    // Screen with a `listing` variable that has preview but no source or initialValue
    private let screenJSON = """
    {
        "type": "screen",
        "id": "test-screen",
        "content": {
            "variables": {
                "listing": {
                    "type": "object",
                    "schema": "datasources/listings",
                    "preview": { "source": "datasources/listings", "index": 0 }
                }
            }
        }
    }
    """.data(using: .utf8)!

    // Datasource returning one listing item
    private let listingDatasourceJSON = """
    {
        "data": [
            { "title": "Preview Listing", "location": "New York", "price": "$120/night" }
        ]
    }
    """.data(using: .utf8)!

    override func setUp() {
        super.setUp()
        mockDS = PreviewTrackingDataSource()
        mockDS.datasources["datasources/listings"] = listingDatasourceJSON
        service = App8Service(publicDataSource: mockDS, context: App8Context())
    }

    override func tearDown() {
        service = nil
        mockDS = nil
        super.tearDown()
    }

    private func decodeScreen() throws -> DSL.Model.Component.`Any` {
        try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: screenJSON)
    }

    func testPreviewDatasourceLoadedWhenNoNavParam() async throws {
        let component = try decodeScreen()
        _ = await service.renderScreen(component, screenId: "test-screen", params: nil)
        XCTAssertTrue(
            mockDS.getDatasourceCalls.contains { $0.datasourceId == "datasources/listings" },
            "Expected getDatasource to be called for 'datasources/listings' as preview fallback"
        )
    }

    func testPreviewDatasourceSkippedWhenNavParamProvided() async throws {
        let component = try decodeScreen()
        let navParam = ["title": "Real Listing", "location": "Boston"]
        _ = await service.renderScreen(component, screenId: "test-screen", params: ["listing": navParam])
        XCTAssertFalse(
            mockDS.getDatasourceCalls.contains { $0.datasourceId == "datasources/listings" },
            "getDatasource should NOT be called for 'datasources/listings' when nav param provides the value"
        )
    }

    func testPreviewSkippedForSourceBasedVariable() async throws {
        // A variable with `source` is handled by DatasourceResolver, not the preview block
        let screenWithSourceJSON = """
        {
            "type": "screen",
            "id": "test-screen",
            "content": {
                "variables": {
                    "items": {
                        "type": "array",
                        "source": "datasources/listings",
                        "preview": { "source": "datasources/listings", "index": 0 }
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let component = try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: screenWithSourceJSON)
        _ = await service.renderScreen(component, screenId: "test-screen", params: nil)

        // DatasourceResolver calls getDatasource for the __datasource_ load, not the preview block.
        // Either way, the call should come from DatasourceResolver (not the preview path).
        // The preview block is guarded by !definition.hasExternalSource.
        let previewCalls = mockDS.getDatasourceCalls
        // At most one call (from DatasourceResolver). The preview block should not add a second.
        XCTAssertLessThanOrEqual(previewCalls.filter { $0.datasourceId == "datasources/listings" }.count, 1,
            "Preview block should not double-load a source-based variable's datasource")
    }

    func testLiteralPreviewDoesNotCallDatasource() async throws {
        let screenWithLiteralPreviewJSON = """
        {
            "type": "screen",
            "id": "test-screen",
            "content": {
                "variables": {
                    "listing": {
                        "type": "object",
                        "schema": "datasources/listings",
                        "preview": { "value": { "title": "Literal Preview", "location": "NYC" } }
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let component = try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: screenWithLiteralPreviewJSON)
        _ = await service.renderScreen(component, screenId: "test-screen", params: nil)

        XCTAssertFalse(
            mockDS.getDatasourceCalls.contains { $0.datasourceId == "datasources/listings" },
            "Literal preview values should not trigger a datasource fetch"
        )
    }
}
