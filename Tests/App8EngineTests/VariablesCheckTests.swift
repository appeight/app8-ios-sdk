//
//  VariablesCheckTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

private final class ScreenMockDataSource: App8DataSource, @unchecked Sendable {
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

private func screenJSON(variables: String) -> Data {
    """
    {
        "type": "screen",
        "id": "test-screen",
        "content": {
            "variables": \(variables)
        }
    }
    """.data(using: .utf8)!
}

final class VariablesCheckTests: XCTestCase {

    private var mockDS: ScreenMockDataSource!

    override func setUp() {
        super.setUp()
        mockDS = ScreenMockDataSource()
    }

    override func tearDown() {
        mockDS = nil
        super.tearDown()
    }

    private func runCheck(variables: String) async -> App8.DiagnosticReport.Section {
        mockDS.screens["test-screen"] = screenJSON(variables: variables)
        return await VariablesCheck.run(
            screenIds: ["test-screen"],
            dataSource: mockDS,
            templateResolver: nil,
            validateDatasources: false
        )
    }

    // MARK: - VAR004: schema without preview

    func testVAR004_firesWhenSchemaWithoutPreviewOrSource() async {
        let section = await runCheck(variables: """
        {
            "listing": { "type": "object", "schema": "datasources/listings" }
        }
        """)
        let codes = section.warnings.map(\.code)
        XCTAssertTrue(codes.contains("VAR004"), "Expected VAR004 but got: \(codes)")
    }

    func testVAR004_noFireWhenPreviewDefined() async {
        let section = await runCheck(variables: """
        {
            "listing": {
                "type": "object",
                "schema": "datasources/listings",
                "preview": { "source": "datasources/listings", "index": 0 }
            }
        }
        """)
        let codes = section.warnings.map(\.code)
        XCTAssertFalse(codes.contains("VAR004"), "VAR004 should not fire when preview is defined")
    }

    func testVAR004_noFireWhenSourceDefined() async {
        // Source-based variables are auto-populated — no preview needed
        let section = await runCheck(variables: """
        {
            "listing": {
                "type": "object",
                "schema": "datasources/listings",
                "source": "datasources/listings"
            }
        }
        """)
        let codes = section.warnings.map(\.code)
        XCTAssertFalse(codes.contains("VAR004"), "VAR004 should not fire for source-based variables")
    }

    func testVAR004_noFireWhenNoSchema() async {
        // Variables without schema are not input params — no VAR004
        let section = await runCheck(variables: """
        {
            "count": { "type": "number", "initialValue": 0 }
        }
        """)
        let codes = section.warnings.map(\.code)
        XCTAssertFalse(codes.contains("VAR004"), "VAR004 should not fire for variables without schema")
    }

    // MARK: - VAR005: preview with both value and source

    func testVAR005_firesWhenBothValueAndSourceSet() async {
        let section = await runCheck(variables: """
        {
            "listing": {
                "type": "object",
                "schema": "datasources/listings",
                "preview": { "source": "datasources/listings", "index": 0, "value": {"title": "Fallback"} }
            }
        }
        """)
        let codes = section.warnings.map(\.code)
        XCTAssertTrue(codes.contains("VAR005"), "Expected VAR005 but got: \(codes)")
    }

    func testVAR005_noFireWhenOnlySourceSet() async {
        let section = await runCheck(variables: """
        {
            "listing": {
                "type": "object",
                "schema": "datasources/listings",
                "preview": { "source": "datasources/listings", "index": 0 }
            }
        }
        """)
        let codes = section.warnings.map(\.code)
        XCTAssertFalse(codes.contains("VAR005"), "VAR005 should not fire when only source is set")
    }

    func testVAR005_noFireWhenOnlyValueSet() async {
        let section = await runCheck(variables: """
        {
            "listing": {
                "type": "object",
                "schema": "datasources/listings",
                "preview": { "value": {"title": "Sample", "location": "NYC"} }
            }
        }
        """)
        let codes = section.warnings.map(\.code)
        XCTAssertFalse(codes.contains("VAR005"), "VAR005 should not fire when only value is set")
    }

    // MARK: - Combined

    func testVAR004AndVAR005_bothFire() async {
        // Schema without preview + a different variable with ambiguous preview
        let section = await runCheck(variables: """
        {
            "navParam": { "type": "object", "schema": "datasources/items" },
            "previewVar": {
                "type": "object",
                "schema": "datasources/listings",
                "preview": { "source": "datasources/listings", "value": {"title": "X"} }
            }
        }
        """)
        let codes = section.warnings.map(\.code)
        XCTAssertTrue(codes.contains("VAR004"), "Expected VAR004")
        XCTAssertTrue(codes.contains("VAR005"), "Expected VAR005")
    }
}
