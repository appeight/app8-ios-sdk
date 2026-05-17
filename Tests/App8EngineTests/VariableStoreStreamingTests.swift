//
//  VariableStoreStreamingTests.swift
//  App8EngineTests
//

import XCTest
import Combine
@testable import App8Engine

@MainActor
final class VariableStoreStreamingTests: XCTestCase {
    var store: VariableStore!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        store = VariableStore()
        cancellables = []
    }

    override func tearDown() {
        store = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - VariableStore.setExternalValue

    func testSetExternalValueUpdatesVariable() throws {
        try store.defineVariable(name: "price", definition: VariableDefinition(type: .number, initialValue: 0))
        store.setExternalValue(name: "price", value: 42)
        XCTAssertEqual(store.getValue(name: "price") as? Int, 42)
    }

    func testSetExternalValueFiresAnyVariableChanged() throws {
        try store.defineVariable(name: "price", definition: VariableDefinition(type: .number, initialValue: 0))

        let expectation = XCTestExpectation(description: "Variable changed")
        store.anyVariableChanged
            .filter { $0 == "price" }
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        store.setExternalValue(name: "price", value: 99)
        wait(for: [expectation], timeout: 1.0)
    }

    func testSetExternalValueSilentlyIgnoresUnknownVariable() {
        store.setExternalValue(name: "nonexistent", value: 42)
        XCTAssertNil(store.getValue(name: "nonexistent"))
    }

    func testSetExternalValueUpdatesComputedDependents() throws {
        try store.defineVariable(name: "base", definition: VariableDefinition(type: .number, initialValue: 10))
        try store.defineVariable(name: "doubled", definition: VariableDefinition(type: .number, computed: "{{base * 2}}"))

        XCTAssertEqual(store.getValue(name: "doubled") as? Int, 20)

        store.setExternalValue(name: "base", value: 5)

        XCTAssertEqual(store.getValue(name: "doubled") as? Int, 10)
    }

    // MARK: - ScopedVariableStore.setExternalValue

    func testSetExternalValueOnScopedStoreUpdatesLocalVariable() throws {
        let screenStore = ScopedVariableStore(parent: store)
        try screenStore.defineVariable(name: "liveCount", definition: VariableDefinition(type: .number, initialValue: 0))

        screenStore.setExternalValue(name: "liveCount", value: 7)

        XCTAssertEqual(screenStore.getValue(name: "liveCount") as? Int, 7)
    }

    func testSetExternalValuePropagatesDownScopeChain() throws {
        let screenStore = ScopedVariableStore(parent: store)
        let componentStore = ScopedVariableStore(parent: screenStore)

        try screenStore.defineVariable(name: "liveCount", definition: VariableDefinition(type: .number, initialValue: 0))

        let expectation = XCTestExpectation(description: "Change reached component store")
        componentStore.anyVariableChanged
            .filter { $0 == "liveCount" }
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        screenStore.setExternalValue(name: "liveCount", value: 7)
        wait(for: [expectation], timeout: 1.0)
    }

    func testSetExternalValueForwardsToParentWhenNotLocal() throws {
        let screenStore = ScopedVariableStore(parent: store)
        try store.defineVariable(name: "appLevel", definition: VariableDefinition(type: .number, initialValue: 0))

        screenStore.setExternalValue(name: "appLevel", value: 100)

        XCTAssertEqual(store.getValue(name: "appLevel") as? Int, 100)
    }

    func testSetExternalValueDoesNotAffectSiblingStores() throws {
        let sibling1 = ScopedVariableStore(parent: store)
        let sibling2 = ScopedVariableStore(parent: store)

        try sibling1.defineVariable(name: "x", definition: VariableDefinition(type: .number, initialValue: 0))
        try sibling2.defineVariable(name: "x", definition: VariableDefinition(type: .number, initialValue: 0))

        sibling1.setExternalValue(name: "x", value: 10)

        XCTAssertEqual(sibling1.getValue(name: "x") as? Int, 10)
        XCTAssertEqual(sibling2.getValue(name: "x") as? Int, 0)
    }

    // MARK: - VariableDefinition.isStreaming

    func testVariableDefinitionIsStreamingDefault() {
        let definition = VariableDefinition(type: .number)
        XCTAssertFalse(definition.isStreaming)
    }

    func testVariableDefinitionIsStreamingTrue() {
        let definition = VariableDefinition(type: .number, streaming: true)
        XCTAssertTrue(definition.isStreaming)
    }

    func testVariableDefinitionStreamingDecodable() throws {
        let json = """
        {
            "type": "number",
            "source": "datasources/live",
            "streaming": true
        }
        """.data(using: .utf8)!

        let definition = try JSONDecoder().decode(VariableDefinition.self, from: json)
        XCTAssertTrue(definition.isStreaming)
        XCTAssertEqual(definition.source, "datasources/live")
    }
}
