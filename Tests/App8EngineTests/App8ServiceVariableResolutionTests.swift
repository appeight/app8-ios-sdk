//
//  App8ServiceVariableResolutionTests.swift
//  App8EngineTests
//
//  Tests that App8Service correctly restricts __datasource_ injection to source-based
//  variables only, so expression initialValues don't get evaluated prematurely.
//

import XCTest
@testable import App8Engine

private final class VariableResolutionTrackingDataSource: App8DataSource, @unchecked Sendable {
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
final class App8ServiceVariableResolutionTests: XCTestCase {

    private var mockDS: VariableResolutionTrackingDataSource!
    private var service: App8Service!

    // Dogs datasource — two items
    private let dogsJSON = """
    {
        "data": [
            { "id": "dog-1", "name": "Buddy", "breed": "Labrador" },
            { "id": "dog-2", "name": "Max",   "breed": "Poodle" }
        ]
    }
    """.data(using: .utf8)!

    // Screen with source-based `dogs` + expression initialValue `selectedDogId`
    private let twoStageScreenJSON = """
    {
        "type": "screen",
        "id": "test-screen",
        "content": {
            "variables": {
                "dogs": {
                    "type": "array",
                    "source": "datasources/dogs"
                },
                "selectedDogId": {
                    "type": "string",
                    "initialValue": "{{first(dogs).id}}"
                }
            }
        }
    }
    """.data(using: .utf8)!

    // Screen with all three stages: dogs (source) → selectedDogId (expression) → selectedDog (computed)
    private let threeStageScreenJSON = """
    {
        "type": "screen",
        "id": "test-screen",
        "content": {
            "variables": {
                "dogs": {
                    "type": "array",
                    "source": "datasources/dogs"
                },
                "selectedDogId": {
                    "type": "string",
                    "initialValue": "{{first(dogs).id}}"
                },
                "selectedDog": {
                    "type": "object",
                    "computed": "{{first(dogs, item.id == selectedDogId)}}"
                }
            }
        }
    }
    """.data(using: .utf8)!

    override func setUp() {
        super.setUp()
        mockDS = VariableResolutionTrackingDataSource()
        mockDS.datasources["datasources/dogs"] = dogsJSON
        service = App8Service(publicDataSource: mockDS, context: App8Context())
    }

    override func tearDown() {
        service = nil
        mockDS = nil
        super.tearDown()
    }

    func testExpressionInitialValueNotInjectedAsDatasourceParam() async throws {
        let component = try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: twoStageScreenJSON)
        _ = await service.renderScreen(component, screenId: "test-screen", params: nil)

        // Only `dogs` (source-based) should trigger getDatasource — not `selectedDogId`
        XCTAssertEqual(
            mockDS.getDatasourceCalls.count, 1,
            "Expected exactly one getDatasource call (for dogs); selectedDogId has no source"
        )
        XCTAssertEqual(
            mockDS.getDatasourceCalls.first?.datasourceId, "datasources/dogs",
            "The single datasource call should be for datasources/dogs"
        )
    }

    func testThreeStageVariableChainRendersWithoutError() async throws {
        let component = try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: threeStageScreenJSON)
        let vc = await service.renderScreen(component, screenId: "test-screen", params: nil)

        // Successful render returns ScreenViewController; error path returns plain UIViewController
        XCTAssertTrue(
            vc is ScreenViewController,
            "Expected ScreenViewController but got \(type(of: vc)) — likely an error screen"
        )

        // Confirm only the dogs source triggered a datasource load
        XCTAssertEqual(
            mockDS.getDatasourceCalls.count, 1,
            "Only dogs (source-based) should call getDatasource"
        )
    }
}
