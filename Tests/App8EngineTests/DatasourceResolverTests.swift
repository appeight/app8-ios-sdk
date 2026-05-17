//
//  DatasourceResolverTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

final class MockDataSource: A8.DataSourceProtocol, @unchecked Sendable {
    var datasources: [String: Data] = [:]
    var shouldThrowError = false

    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getAllScreenIds() async throws -> [String]? { nil }
    func streamScreen(screenId: String) -> AsyncStream<Data>? { nil }
    func streamDatasource(screenId: String, datasourceId: String, componentPath: String?) -> AsyncStream<Data>? { nil }
    func streamStyles() -> AsyncStream<Data>? { nil }

    func getDatasource(screenId: String, datasourceId: String) async throws -> Data {
        if shouldThrowError {
            throw DatasourceError.notFound(screenId: screenId, datasourceId: datasourceId)
        }
        guard let data = datasources[datasourceId] else {
            throw DatasourceError.notFound(screenId: screenId, datasourceId: datasourceId)
        }
        return data
    }
}

final class DatasourceResolverTests: XCTestCase {
    var mockDataSource: MockDataSource!

    override func setUp() {
        super.setUp()
        mockDataSource = MockDataSource()
    }

    override func tearDown() {
        mockDataSource = nil
        super.tearDown()
    }

    func testResolveDatasourcesWithNoSources() async throws {
        let variables: [String: VariableDefinition] = [
            "name": VariableDefinition(type: .string, initialValue: "Alice"),
            "age": VariableDefinition(type: .number, initialValue: 30)
        ]

        let resolved = try await DatasourceResolver.resolveDatasources(
            screenId: "test-screen",
            variables: variables,
            dataSource: mockDataSource
        )

        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual(resolved["name"]?.rawInitialValue as? String, "Alice")
        XCTAssertEqual(resolved["age"]?.rawInitialValue as? Int, 30)
        XCTAssertNil(resolved["name"]?.source)
        XCTAssertNil(resolved["age"]?.source)
    }

    func testResolveDatasourcesLoadsExternalData() async throws {
        let jsonData = """
        {
            "data": [
                {"id": "1", "name": "Item 1"},
                {"id": "2", "name": "Item 2"}
            ]
        }
        """.data(using: .utf8)!
        mockDataSource.datasources["datasources/items"] = jsonData

        let variables: [String: VariableDefinition] = [
            "items": VariableDefinition(type: .array, source: "datasources/items")
        ]

        let resolved = try await DatasourceResolver.resolveDatasources(
            screenId: "test-screen",
            variables: variables,
            dataSource: mockDataSource
        )

        XCTAssertEqual(resolved.count, 1)
        XCTAssertNil(resolved["items"]?.source, "Source should be cleared after resolution")

        let items = resolved["items"]?.rawInitialValue as? [[String: Any]]
        XCTAssertNotNil(items)
        XCTAssertEqual(items?.count, 2)
        XCTAssertEqual(items?[0]["id"] as? String, "1")
        XCTAssertEqual(items?[0]["name"] as? String, "Item 1")
    }

    func testResolveDatasourcesWithRawArrayFormat() async throws {
        let jsonData = """
        [
            {"id": "1", "title": "First"},
            {"id": "2", "title": "Second"}
        ]
        """.data(using: .utf8)!
        mockDataSource.datasources["datasources/posts"] = jsonData

        let variables: [String: VariableDefinition] = [
            "posts": VariableDefinition(type: .array, source: "datasources/posts")
        ]

        let resolved = try await DatasourceResolver.resolveDatasources(
            screenId: "test-screen",
            variables: variables,
            dataSource: mockDataSource
        )

        let posts = resolved["posts"]?.rawInitialValue as? [[String: Any]]
        XCTAssertNotNil(posts)
        XCTAssertEqual(posts?.count, 2)
    }

    func testResolveDatasourcesValidatesType() async throws {
        // Datasource returns an object but the variable expects an array.
        let jsonData = """
        {
            "data": {"key": "value"}
        }
        """.data(using: .utf8)!
        mockDataSource.datasources["datasources/items"] = jsonData

        let variables: [String: VariableDefinition] = [
            "items": VariableDefinition(type: .array, source: "datasources/items")
        ]

        do {
            _ = try await DatasourceResolver.resolveDatasources(
                screenId: "test-screen",
                variables: variables,
                dataSource: mockDataSource
            )
            XCTFail("Should have thrown type mismatch error")
        } catch let error as DatasourceError {
            if case .typeMismatch(let datasourceId, let expected, _) = error {
                XCTAssertEqual(datasourceId, "datasources/items")
                XCTAssertEqual(expected, .array)
            } else {
                XCTFail("Expected typeMismatch error, got: \(error)")
            }
        }
    }

    func testResolveDatasourcesHandlesNotFound() async throws {
        let variables: [String: VariableDefinition] = [
            "missing": VariableDefinition(type: .array, source: "datasources/nonexistent")
        ]

        do {
            _ = try await DatasourceResolver.resolveDatasources(
                screenId: "test-screen",
                variables: variables,
                dataSource: mockDataSource
            )
            XCTFail("Should have thrown not found error")
        } catch let error as DatasourceError {
            if case .notFound(let screenId, let datasourceId) = error {
                XCTAssertEqual(screenId, "test-screen")
                XCTAssertEqual(datasourceId, "datasources/nonexistent")
            } else {
                XCTFail("Expected notFound error, got: \(error)")
            }
        }
    }

    func testResolveDatasourcesParallelLoading() async throws {
        let itemsData = """
        {"data": [{"id": "1"}]}
        """.data(using: .utf8)!
        let usersData = """
        {"data": [{"id": "u1"}]}
        """.data(using: .utf8)!
        let postsData = """
        {"data": [{"id": "p1"}]}
        """.data(using: .utf8)!

        mockDataSource.datasources["datasources/items"] = itemsData
        mockDataSource.datasources["datasources/users"] = usersData
        mockDataSource.datasources["datasources/posts"] = postsData

        let variables: [String: VariableDefinition] = [
            "items": VariableDefinition(type: .array, source: "datasources/items"),
            "users": VariableDefinition(type: .array, source: "datasources/users"),
            "posts": VariableDefinition(type: .array, source: "datasources/posts")
        ]

        let resolved = try await DatasourceResolver.resolveDatasources(
            screenId: "test-screen",
            variables: variables,
            dataSource: mockDataSource
        )

        XCTAssertEqual(resolved.count, 3)
        XCTAssertNotNil(resolved["items"]?.rawInitialValue)
        XCTAssertNotNil(resolved["users"]?.rawInitialValue)
        XCTAssertNotNil(resolved["posts"]?.rawInitialValue)
    }

    func testHasExternalDatasources() {
        let noSources: [String: VariableDefinition] = [
            "name": VariableDefinition(type: .string, initialValue: "Test")
        ]
        XCTAssertFalse(DatasourceResolver.hasExternalDatasources(noSources))

        let withSource: [String: VariableDefinition] = [
            "items": VariableDefinition(type: .array, source: "datasources/items")
        ]
        XCTAssertTrue(DatasourceResolver.hasExternalDatasources(withSource))

        XCTAssertFalse(DatasourceResolver.hasExternalDatasources(nil))
    }
}
