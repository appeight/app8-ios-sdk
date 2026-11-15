//
//  RequestActionTests.swift
//  App8EngineTests
//
//  The `request` action against a stub URLProtocol, plus the host
//  `prepareRequest` hook (authorize / reject).
//

import XCTest
@testable import App8Engine

/// Answers every request from `handler` and records what was sent.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String], Data))?
    nonisolated(unsafe) static var sent: [URLRequest] = []
    nonisolated(unsafe) static var sentBodies: [Data?] = []

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.sent.append(request)
        Self.sentBodies.append(request.httpBody ?? request.httpBodyStream.map(Self.read))
        let (status, headers, body) = Self.handler?(request) ?? (200, [:], Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

private struct Rejected: Error {}

/// Adds a bearer header to one host, rejects every other host.
private final class AuthorizingDataSource: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }

    func prepareRequest(_ request: URLRequest) async throws -> URLRequest {
        guard request.url?.host == "api.example.com" else { throw Rejected() }
        var request = request
        request.setValue("Bearer test-token", forHTTPHeaderField: "Authorization")
        return request
    }
}

@MainActor
final class RequestActionTests: XCTestCase {

    private var harness: RenderHarness!
    private var root: CViewModel!

    override func setUp() async throws {
        StubURLProtocol.sent = []
        StubURLProtocol.sentBodies = []
        StubURLProtocol.handler = nil
        harness = RenderHarness(dataSource: AuthorizingDataSource())
        harness.service.context.urlSession = StubURLProtocol.session()
        try harness.render("""
        {
            "id": "root", "type": "view",
            "content": {
                "variables": {
                    "items": { "type": "array", "initialValue": [ { "id": "i1" }, { "id": "i2" } ] },
                    "note": { "type": "string", "initialValue": "hello" },
                    "lastResponse": { "type": "object" },
                    "status": { "type": "string", "initialValue": "" },
                    "message": { "type": "string", "initialValue": "" }
                },
                "layout": { "width": 390, "height": 844 }
            }
        }
        """)
        root = try XCTUnwrap(harness.viewModel("root", as: CViewModel.self))
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func run(_ json: String) throws {
        let action = try JSONDecoder().decode(DSL.Model.Action.self, from: Data(json.utf8))
        root.executeAction(action)
    }

    private func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func value(_ name: String) -> Any? { root.variableStore.getValue(name: name) }

    func testSuccessRunsOnSuccessWithResponseAndWritesResultVariable() throws {
        StubURLProtocol.handler = { _ in (200, ["Content-Type": "application/json", "X-Trace": "abc"], Data(#"{"ok":true,"count":2}"#.utf8)) }
        try run("""
        { "type": "request", "method": "DELETE", "url": "https://api.example.com/v1/items/{{items[0].id}}",
          "headers": { "Accept": "application/json" }, "body": { "note": "{{note}}" },
          "resultVariable": "lastResponse",
          "onSuccess": [
            { "type": "removeArrayItem", "variableName": "items", "matchBy": "id", "value": "i1" },
            { "type": "updateVariable", "variableName": "status", "value": "{{response.status}}-{{response.body.count}}-{{response.headers['x-trace']}}" }
          ],
          "onError": { "type": "updateVariable", "variableName": "status", "value": "error" } }
        """)
        // The list continues immediately; the response arrives later.
        XCTAssertEqual(value("status") as? String, "")
        waitFor { (value("status") as? String) != "" }

        XCTAssertEqual(value("status") as? String, "200-2-abc")
        XCTAssertEqual((value("items") as? [[String: Any]])?.map { $0["id"] as? String }, ["i2"])
        let response = try XCTUnwrap(value("lastResponse") as? [String: Any])
        XCTAssertEqual(response["status"] as? Int, 200)
        XCTAssertEqual((response["body"] as? [String: Any])?["ok"] as? Bool, true)

        let sent = try XCTUnwrap(StubURLProtocol.sent.first)
        XCTAssertEqual(sent.httpMethod, "DELETE")
        XCTAssertEqual(sent.url?.absoluteString, "https://api.example.com/v1/items/i1")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Accept"), "application/json")
        let body = try XCTUnwrap(StubURLProtocol.sentBodies.first ?? nil)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["note"] as? String, "hello")
    }

    func testNon2xxRunsOnErrorWithStringBody() throws {
        StubURLProtocol.handler = { _ in (404, [:], Data("not found".utf8)) }
        try run("""
        { "type": "request", "url": "https://api.example.com/v1/missing", "body": { "ignored": true },
          "onSuccess": { "type": "updateVariable", "variableName": "status", "value": "ok" },
          "onError": [
            { "type": "updateVariable", "variableName": "status", "value": "s{{response.status}}" },
            { "type": "updateVariable", "variableName": "message", "value": "{{response.body}}" }
          ] }
        """)
        waitFor { (value("status") as? String) != "" }
        XCTAssertEqual(value("status") as? String, "s404")
        XCTAssertEqual(value("message") as? String, "not found")
        let sent = try XCTUnwrap(StubURLProtocol.sent.first)
        XCTAssertEqual(sent.httpMethod, "GET")
        XCTAssertNil(StubURLProtocol.sentBodies.first ?? nil, "GET sends no body")
    }

    func testHostRejectionIsStatusZeroError() throws {
        try run("""
        { "type": "request", "method": "POST", "url": "https://elsewhere.example.org/x", "resultVariable": "lastResponse",
          "onError": { "type": "updateVariable", "variableName": "status", "value": "s{{response.status}}" } }
        """)
        waitFor { (value("status") as? String) != "" }
        XCTAssertEqual(value("status") as? String, "s0")
        XCTAssertTrue(StubURLProtocol.sent.isEmpty, "a rejected request is never sent")
        let response = try XCTUnwrap(value("lastResponse") as? [String: Any])
        XCTAssertTrue(response["body"] is NSNull)
        XCTAssertEqual((response["headers"] as? [String: Any])?.count, 0)
    }

    func testRelativeURLIsStatusZeroError() throws {
        try run("""
        { "type": "request", "url": "/v1/items", "onError": { "type": "updateVariable", "variableName": "status", "value": "s{{response.status}}" } }
        """)
        waitFor { (value("status") as? String) != "" }
        XCTAssertEqual(value("status") as? String, "s0")
    }
}
