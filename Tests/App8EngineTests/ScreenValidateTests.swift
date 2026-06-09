//
//  ScreenValidateTests.swift
//  App8EngineTests
//
//  Exercises App8.Debug.validate(screenId:options:) end-to-end (the entry the MCP uses).
//

import XCTest
@testable import App8Engine

private final class ValidateMockDataSource: App8DataSource, @unchecked Sendable {
    var screens: [String: Data] = [:]

    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }

    func getScreen(screenId: String) async throws -> Data {
        guard let data = screens[screenId] else { throw NSError(domain: "test", code: 404) }
        return data
    }
}

@MainActor
final class ScreenValidateTests: XCTestCase {

    private var mockDS: ValidateMockDataSource!
    // Held strongly: App8.Debug references its instance `unowned`, so the
    // DebugInstance must outlive the validate() call.
    private var instance: App8.DebugInstance!

    override func setUp() {
        super.setUp()
        mockDS = ValidateMockDataSource()
    }

    override func tearDown() {
        instance = nil
        mockDS = nil
        super.tearDown()
    }

    private func debug() -> App8.DebugProtocol {
        if instance == nil {
            instance = App8.debugInstance(dataSource: mockDS)
        }
        return instance.debug
    }

    func testValidateScreen_flagsMissingVideoAsset() async throws {
        mockDS.screens["onboarding"] = """
        {
            "type": "screen", "id": "onboarding",
            "content": {
                "children": [
                    {
                        "type": "video", "id": "intro",
                        "content": {
                            "properties": { "type": "localAsset", "name": "missing-intro-clip" },
                            "layout": {}
                        }
                    }
                ]
            }
        }
        """.data(using: .utf8)!

        let result = try await debug().validate(screenId: "onboarding", options: .full)

        // A missing asset is a warning, not an error → screen still "valid".
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.warnings.map(\.code).contains("VID001"),
                      "Expected VID001 but got warnings: \(result.warnings.map(\.code))")
    }

    func testValidateScreen_cleanScreenHasNoIssues() async throws {
        mockDS.screens["clean"] = """
        {
            "type": "screen", "id": "clean",
            "content": { "children": [] }
        }
        """.data(using: .utf8)!

        let result = try await debug().validate(screenId: "clean", options: .full)
        XCTAssertTrue(result.isValid)
        XCTAssertFalse(result.warnings.map(\.code).contains("VID001"))
    }

    func testValidateScreen_missingScreenReportsLoadError() async throws {
        let result = try await debug().validate(screenId: "does-not-exist", options: .structureOnly)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.map(\.code).contains("SCR001"),
                      "Expected SCR001 load error but got: \(result.errors.map(\.code))")
    }
}
