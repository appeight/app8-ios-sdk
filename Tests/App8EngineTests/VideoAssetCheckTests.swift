//
//  VideoAssetCheckTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

private final class VideoScreenMockDataSource: App8DataSource, @unchecked Sendable {
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

private func screenWithVideo(_ videoJSON: String) -> Data {
    """
    {
        "type": "screen",
        "id": "test-screen",
        "content": {
            "children": [ \(videoJSON) ]
        }
    }
    """.data(using: .utf8)!
}

final class VideoAssetCheckTests: XCTestCase {

    private var mockDS: VideoScreenMockDataSource!

    override func setUp() {
        super.setUp()
        mockDS = VideoScreenMockDataSource()
    }

    override func tearDown() {
        mockDS = nil
        super.tearDown()
    }

    private func runCheck(_ videoJSON: String) async -> App8.DiagnosticReport.Section {
        mockDS.screens["test-screen"] = screenWithVideo(videoJSON)
        let result = await ScreenCheck.run(
            screenIds: ["test-screen"],
            dataSource: mockDS,
            resolvedStyles: [:],
            templateResolver: nil,
            resolvePointers: false
        )
        return result.sections.first { $0.label == "Screen: test-screen" } ?? result.sections[0]
    }

    func testVID001_firesForMissingLocalAsset() async {
        let section = await runCheck("""
        {
            "type": "video", "id": "intro-video",
            "content": {
                "properties": { "type": "localAsset", "name": "definitely-missing-asset-xyz" },
                "layout": {}
            }
        }
        """)
        let codes = section.warnings.map(\.code)
        XCTAssertTrue(codes.contains("VID001"), "Expected VID001 but got: \(codes)")
    }

    func testVID001_noFireForNoneType() async {
        let section = await runCheck("""
        {
            "type": "video", "id": "empty-video",
            "content": { "properties": { "type": "none" }, "layout": {} }
        }
        """)
        XCTAssertFalse(section.warnings.map(\.code).contains("VID001"))
    }

    func testVID001_skipsExpressionNames() async {
        // {{...}} names can only resolve at runtime — a static bundle lookup would be wrong.
        let section = await runCheck("""
        {
            "type": "video", "id": "dynamic-video",
            "content": {
                "properties": { "type": "localAsset", "name": "{{videoName}}" },
                "layout": {}
            }
        }
        """)
        XCTAssertFalse(section.warnings.map(\.code).contains("VID001"))
    }

    func testVID001_noFireForRemoteAsset() async {
        // remoteAsset videos resolve at runtime via the data source, not the
        // app bundle — VID001 (a bundle-presence check) must not flag them.
        let section = await runCheck("""
        {
            "type": "video", "id": "remote-video",
            "content": {
                "properties": { "type": "remoteAsset", "name": "shutterAnimation", "id": "asset-123" },
                "layout": {}
            }
        }
        """)
        XCTAssertFalse(section.warnings.map(\.code).contains("VID001"))
    }

    func testVID001_findsNestedVideo() async {
        // Video buried inside a container child should still be flagged (recursion).
        let section = await runCheck("""
        {
            "type": "view", "id": "wrapper",
            "content": {
                "properties": {},
                "layout": {},
                "children": [
                    {
                        "type": "video", "id": "nested-video",
                        "content": {
                            "properties": { "type": "localAsset", "name": "missing-nested" },
                            "layout": {}
                        }
                    }
                ]
            }
        }
        """)
        let videoWarning = section.warnings.first { $0.code == "VID001" }
        XCTAssertNotNil(videoWarning)
        XCTAssertEqual(videoWarning?.context?["assetName"], "missing-nested")
    }

    func testVID001_findsVideoInsideCollectionTemplate() async {
        // Collections hold cell templates outside `content.children` — a missing
        // asset in a cell template must still be flagged.
        let section = await runCheck("""
        {
            "type": "collection", "id": "feed",
            "content": {
                "properties": { "data": "{{items}}", "templateKey": "kind" },
                "layout": {},
                "templates": {
                    "hero": {
                        "type": "video", "id": "cellVideo",
                        "content": {
                            "properties": { "type": "localAsset", "name": "missing-cell-clip" },
                            "layout": {}
                        }
                    }
                }
            }
        }
        """)
        let videoWarning = section.warnings.first { $0.code == "VID001" }
        XCTAssertNotNil(videoWarning, "VID001 should fire for a video in a collection template")
        XCTAssertEqual(videoWarning?.context?["assetName"], "missing-cell-clip")
    }
}
