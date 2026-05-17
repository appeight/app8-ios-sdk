//
//  ScreenReferenceWalkerTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

private final class WalkerMockDataSource: App8DataSource, @unchecked Sendable {
    var screens: [String: Data] = [:]

    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }

    func getScreen(screenId: String) async throws -> Data {
        guard let data = screens[screenId] else {
            throw NSError(domain: "test", code: 404)
        }
        return data
    }
}

private let appJSON = """
{
    "title": "Test",
    "navigation": {
        "startFlow": "main",
        "flows": [{ "id": "main", "startScreen": "home" }]
    }
}
""".data(using: .utf8)!

private func decodeApp() throws -> DSL.Model.App {
    try JSONDecoder().decode(DSL.Model.App.self, from: appJSON)
}

final class ScreenReferenceWalkerTests: XCTestCase {

    private var mockDS: WalkerMockDataSource!

    override func setUp() {
        super.setUp()
        mockDS = WalkerMockDataSource()
    }

    override func tearDown() {
        mockDS = nil
        super.tearDown()
    }

    // MARK: navigationBar.titleView

    func test_titleView_actionIsDiscovered() async throws {
        // Home screen's nav bar title view contains a tappable avatar that navigates to settings.
        mockDS.screens["home"] = """
        {
            "type": "screen",
            "id": "home",
            "content": {
                "navigationBar": {
                    "titleView": {
                        "id": "navTitleStack",
                        "type": "stackView",
                        "content": {
                            "properties": { "axis": "horizontal" },
                            "children": [
                                {
                                    "id": "avatarBtn",
                                    "type": "view",
                                    "content": {
                                        "actions": {
                                            "tap": { "type": "navigation", "nextScreen": "settings", "presentation": "push" }
                                        }
                                    }
                                }
                            ]
                        }
                    }
                }
            }
        }
        """.data(using: .utf8)!
        mockDS.screens["settings"] = """
        { "type": "screen", "id": "settings", "content": {} }
        """.data(using: .utf8)!

        let walker = ScreenReferenceWalker(dataSource: mockDS)
        let (ids, refs) = await walker.discoverAllScreens(app: try decodeApp())

        XCTAssertTrue(ids.contains("settings"), "Expected `settings` reachable via titleView; got \(ids)")
        XCTAssertTrue(refs.contains(where: { $0.targetScreenId == "settings" && $0.path.contains("titleView") }),
                      "Expected reference path to mention titleView; got \(refs.map(\.path))")
    }

    // MARK: navigationBar.rightActions

    func test_rightActions_pluralActionsAreDiscovered() async throws {
        mockDS.screens["home"] = """
        {
            "type": "screen",
            "id": "home",
            "content": {
                "navigationBar": {
                    "rightActions": [
                        { "title": "A", "action": { "type": "navigation", "nextScreen": "alpha", "presentation": "push" } },
                        { "title": "B", "action": { "type": "navigation", "nextScreen": "beta", "presentation": "push" } }
                    ]
                }
            }
        }
        """.data(using: .utf8)!
        mockDS.screens["alpha"] = """
        { "type": "screen", "id": "alpha", "content": {} }
        """.data(using: .utf8)!
        mockDS.screens["beta"] = """
        { "type": "screen", "id": "beta", "content": {} }
        """.data(using: .utf8)!

        let walker = ScreenReferenceWalker(dataSource: mockDS)
        let (ids, _) = await walker.discoverAllScreens(app: try decodeApp())

        XCTAssertTrue(ids.contains("alpha"), "Expected `alpha` in \(ids)")
        XCTAssertTrue(ids.contains("beta"), "Expected `beta` in \(ids)")
    }

    // MARK: Collection templates

    func test_collectionTemplates_heterogeneousTemplatesAreDiscovered() async throws {
        mockDS.screens["home"] = """
        {
            "type": "screen",
            "id": "home",
            "content": {
                "children": [{
                    "id": "list",
                    "type": "collection",
                    "content": {
                        "properties": { "data": "{{items}}", "templateKey": "kind" },
                        "templates": {
                            "event": {
                                "id": "eventCell",
                                "type": "view",
                                "content": {
                                    "actions": {
                                        "tap": { "type": "navigation", "nextScreen": "event-detail", "presentation": "push" }
                                    }
                                }
                            },
                            "calendar": {
                                "id": "calCell",
                                "type": "view",
                                "content": {
                                    "actions": {
                                        "tap": { "type": "navigation", "nextScreen": "calendar-detail", "presentation": "push" }
                                    }
                                }
                            }
                        }
                    }
                }]
            }
        }
        """.data(using: .utf8)!
        mockDS.screens["event-detail"] = """
        { "type": "screen", "id": "event-detail", "content": {} }
        """.data(using: .utf8)!
        mockDS.screens["calendar-detail"] = """
        { "type": "screen", "id": "calendar-detail", "content": {} }
        """.data(using: .utf8)!

        let walker = ScreenReferenceWalker(dataSource: mockDS)
        let (ids, refs) = await walker.discoverAllScreens(app: try decodeApp())

        XCTAssertTrue(ids.contains("event-detail"), "Expected `event-detail` in \(ids)")
        XCTAssertTrue(ids.contains("calendar-detail"), "Expected `calendar-detail` in \(ids)")
        XCTAssertTrue(refs.contains(where: { $0.targetScreenId == "event-detail" && $0.path.contains("templates[event]") }),
                      "Expected path to mention templates[event]; got \(refs.map(\.path))")
    }

    func test_collectionSingleTemplate_isDiscovered() async throws {
        mockDS.screens["home"] = """
        {
            "type": "screen",
            "id": "home",
            "content": {
                "children": [{
                    "id": "list",
                    "type": "collection",
                    "content": {
                        "properties": { "data": "{{items}}" },
                        "template": {
                            "id": "cell",
                            "type": "view",
                            "content": {
                                "actions": {
                                    "tap": { "type": "navigation", "nextScreen": "detail", "presentation": "push" }
                                }
                            }
                        }
                    }
                }]
            }
        }
        """.data(using: .utf8)!
        mockDS.screens["detail"] = """
        { "type": "screen", "id": "detail", "content": {} }
        """.data(using: .utf8)!

        let walker = ScreenReferenceWalker(dataSource: mockDS)
        let (ids, _) = await walker.discoverAllScreens(app: try decodeApp())

        XCTAssertTrue(ids.contains("detail"), "Expected `detail` in \(ids)")
    }
}
