//
//  ReparentComputedTests.swift
//  App8EngineTests
//
//  A reused collection cell reparents its template's variable store to the
//  new item's cell store. Computed variables of the template (a selected
//  option, the value derived from it) must follow the new item at once;
//  they used to keep the previous item's values, so a reused card showed
//  another item's number.
//

import XCTest
@testable import App8Engine

@MainActor
final class ReparentComputedTests: XCTestCase {

    private func cellStore(_ value: Int, parent: VariableStoreProtocol) throws -> ScopedVariableStore {
        let store = ScopedVariableStore(parent: parent)
        try store.defineVariable(name: "item", definition: VariableDefinition(type: .object, initialValue: ["value": value, "options": [["value": value * 10]]]))
        return store
    }

    func testComputedVariablesFollowTheNewParentOnReparent() throws {
        let root = ScopedVariableStore(parent: nil)
        let first = try cellStore(1, parent: root)
        let second = try cellStore(2, parent: root)

        let template = ScopedVariableStore(parent: first)
        try template.defineVariable(name: "option", definition: VariableDefinition(type: .object, computed: "{{first(item.options)}}"))
        try template.defineVariable(name: "shown", definition: VariableDefinition(type: .number, computed: "{{option != null ? option.value : item.value}}"))
        // A child scope (a nested component) with its own computed variable.
        let child = ScopedVariableStore(parent: template)
        try child.defineVariable(name: "label", definition: VariableDefinition(type: .string, computed: "{{'#' + item.value}}"))
        XCTAssertEqual((template.getValue(name: "shown") as? NSNumber)?.intValue, 10)

        template.reparent(to: second)
        // Synchronously, before any main-queue hop.
        XCTAssertEqual((template.getValue(name: "shown") as? NSNumber)?.intValue, 20)
        XCTAssertEqual(child.getValue(name: "label") as? String, "#2")
    }
}
