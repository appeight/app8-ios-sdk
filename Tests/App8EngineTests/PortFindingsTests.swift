//
//  PortFindingsTests.swift
//  App8EngineTests
//
//  Regression tests for engine bugs found while porting App8 to Android.
//  See NOTES-android.md at the repo root for the cross-platform contract.
//

import XCTest
import UIKit
@testable import App8Engine

@MainActor
final class PortFindingsTests: XCTestCase {

    // MARK: - #1 datePicker time / dateAndTime keep the time

    private func renderDatePicker(mode: String, harness: RenderHarness) throws {
        try harness.render("""
        {
          "type": "view", "id": "root",
          "content": {
            "properties": {},
            "variables": { "when": { "type": "string", "initialValue": "2026-01-01" } },
            "layout": { "width": 390, "height": 400 },
            "children": [
              { "type": "datePicker", "id": "dp",
                "content": {
                  "properties": { "datePickerMode": "\(mode)", "displayStyle": "wheels", "bindVariable": "when" },
                  "layout": { "top": 0, "leading": 0 }
                } }
            ]
          }
        }
        """)
    }

    private func pick(_ date: Date, harness: RenderHarness) throws -> String? {
        let picker = try XCTUnwrap(harness.find(UIDatePicker.self))
        picker.date = date
        harness.fire(picker, .valueChanged)
        harness.drain()
        let rootVM = try XCTUnwrap(harness.viewModel("root", as: CViewModel.self))
        return rootVM.variableStore.getValue(name: "when") as? String
    }

    private func localDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testDatePickerTimeModeStoresTime() throws {
        let harness = RenderHarness()
        try renderDatePicker(mode: "time", harness: harness)
        let date = localDate(2026, 3, 4, 14, 30)
        let stored = try XCTUnwrap(try pick(date, harness: harness))
        XCTAssertTrue(stored.contains("T14:30:00"), "time mode must keep the time, got \(stored)")
        let parsed = ISO8601DateFormatter().date(from: stored)
        XCTAssertEqual(parsed, date)
    }

    func testDatePickerDateAndTimeModeStoresTime() throws {
        let harness = RenderHarness()
        try renderDatePicker(mode: "dateAndTime", harness: harness)
        let date = localDate(2026, 3, 4, 9, 5)
        let stored = try XCTUnwrap(try pick(date, harness: harness))
        XCTAssertTrue(stored.hasPrefix("2026-03-04T09:05:00"), "got \(stored)")
        XCTAssertEqual(ISO8601DateFormatter().date(from: stored), date)
    }

    func testDatePickerDateModeStillStoresDateOnly() throws {
        let harness = RenderHarness()
        try renderDatePicker(mode: "date", harness: harness)
        let stored = try pick(localDate(2026, 3, 4, 14, 30), harness: harness)
        XCTAssertEqual(stored, "2026-03-04")
    }

    // MARK: - #2 textView fires onTextChange (with $value) like textField

    func testTextViewFiresOnTextChange() throws {
        let harness = RenderHarness()
        try harness.render("""
        {
          "type": "view", "id": "root",
          "content": {
            "properties": {},
            "variables": {
              "note": { "type": "string", "initialValue": "" },
              "last": { "type": "string", "initialValue": "" }
            },
            "layout": { "width": 390, "height": 400 },
            "children": [
              { "type": "textView", "id": "tv",
                "content": {
                  "properties": { "bindVariable": "note" },
                  "layout": { "top": 0, "leading": 0, "width": 300, "height": 100 },
                  "actions": { "onTextChange": { "type": "updateVariable", "variableName": "last", "value": "{{$value}}" } }
                } }
            ]
          }
        }
        """)
        let textView = try XCTUnwrap(harness.find(UITextView.self))
        textView.text = "hello"
        textView.delegate?.textViewDidChange?(textView)
        harness.drain()
        let rootVM = try XCTUnwrap(harness.viewModel("root", as: CViewModel.self))
        XCTAssertEqual(rootVM.variableStore.getValue(name: "last") as? String, "hello")
        XCTAssertEqual(rootVM.variableStore.getValue(name: "note") as? String, "hello")
    }

    // MARK: - #3 resetVariables restores initial values per scope

    private func resetAction(_ scope: String?) throws -> DSL.Model.Action {
        let json = scope.map { #"{"type":"resetVariables","scope":"\#($0)"}"# } ?? #"{"type":"resetVariables"}"#
        return try JSONDecoder().decode(DSL.Model.Action.self, from: Data(json.utf8))
    }

    /// app (VariableStore) <- screen (Scoped) <- component (Scoped)
    private func makeChain() throws -> (VariableStore, ScopedVariableStore, ScopedVariableStore) {
        let app = VariableStore()
        try app.defineVariable(name: "cart", definition: VariableDefinition(type: .number, initialValue: 1))
        let screen = ScopedVariableStore(parent: app)
        try screen.defineVariable(name: "email", definition: VariableDefinition(type: .string, initialValue: "a@b.c"))
        try screen.defineVariable(name: "greeting", definition: VariableDefinition(type: .string, initialValue: "{{'hi ' + email}}"))
        try screen.defineVariable(name: "emailLength", definition: VariableDefinition(type: .number, computed: "{{email.length}}"))
        let component = ScopedVariableStore(parent: screen)
        try component.defineVariable(name: "draft", definition: VariableDefinition(type: .string, initialValue: "x"))
        try app.setValue(name: "cart", value: 5)
        try screen.setValue(name: "email", value: "changed@example.com")
        try screen.setValue(name: "greeting", value: "yo")
        try component.setValue(name: "draft", value: "y")
        return (app, screen, component)
    }

    private func runReset(_ scope: String?, on store: VariableStoreProtocol) throws {
        try VariableActionHandler().execute(action: resetAction(scope), store: store, context: VariableContext(store: store))
    }

    func testResetVariablesScreenScopeRestoresInitialValues() throws {
        let (app, screen, component) = try makeChain()
        try runReset("screen", on: component)
        XCTAssertEqual(component.getValue(name: "draft") as? String, "x")
        XCTAssertEqual(screen.getValue(name: "email") as? String, "a@b.c")
        XCTAssertEqual(screen.getValue(name: "greeting") as? String, "hi a@b.c", "expression initialValue restores its evaluated value")
        XCTAssertEqual(screen.getValue(name: "emailLength") as? Int, 5, "computed dependents recompute")
        XCTAssertEqual(app.getValue(name: "cart") as? Int, 5, "screen scope leaves app variables alone")
    }

    func testResetVariablesDefaultScopeIsScreen() throws {
        let (app, screen, _) = try makeChain()
        try runReset(nil, on: screen)
        XCTAssertEqual(screen.getValue(name: "email") as? String, "a@b.c")
        XCTAssertEqual(app.getValue(name: "cart") as? Int, 5)
    }

    func testResetVariablesComponentScope() throws {
        let (_, screen, component) = try makeChain()
        try runReset("component", on: component)
        XCTAssertEqual(component.getValue(name: "draft") as? String, "x")
        XCTAssertEqual(screen.getValue(name: "email") as? String, "changed@example.com")
    }

    func testResetVariablesAppAndAllScopes() throws {
        var (app, screen, component) = try makeChain()
        try runReset("app", on: component)
        XCTAssertEqual(app.getValue(name: "cart") as? Int, 1)
        XCTAssertEqual(screen.getValue(name: "email") as? String, "changed@example.com")

        (app, screen, component) = try makeChain()
        try runReset("all", on: component)
        XCTAssertEqual(app.getValue(name: "cart") as? Int, 1)
        XCTAssertEqual(screen.getValue(name: "email") as? String, "a@b.c")
        XCTAssertEqual(component.getValue(name: "draft") as? String, "x")
        XCTAssertTrue(component.hasVariable(name: "draft"), "reset never deletes variables")
    }

    // MARK: - #4 setMultipleValues failure must not leave the store "updating"

    private func assertStoreRecoversAfterFailedBatch(_ store: VariableStoreProtocol) throws {
        try store.defineVariable(name: "a", definition: VariableDefinition(type: .number, initialValue: 1))
        try store.defineVariable(name: "double", definition: VariableDefinition(type: .number, computed: "{{a * 2}}"))
        XCTAssertThrowsError(try store.setMultipleValues(["a": 3, "missing": 1]))
        // Failed batch is atomic: nothing applied.
        XCTAssertEqual(store.getValue(name: "a") as? Int, 1)
        // Later single writes still recompute dependents.
        try store.setValue(name: "a", value: 10)
        XCTAssertEqual(store.getValue(name: "double") as? Int, 20)
    }

    func testSetMultipleValuesFailureDoesNotWedgeVariableStore() throws {
        try assertStoreRecoversAfterFailedBatch(VariableStore())
    }

    func testSetMultipleValuesFailureDoesNotWedgeScopedStore() throws {
        try assertStoreRecoversAfterFailedBatch(ScopedVariableStore(parent: VariableStore()))
    }

    func testSetMultipleValuesTypeMismatchStillRecomputesAndRecovers() throws {
        let store = VariableStore()
        try store.defineVariable(name: "a", definition: VariableDefinition(type: .number, initialValue: 1))
        try store.defineVariable(name: "double", definition: VariableDefinition(type: .number, computed: "{{a * 2}}"))
        XCTAssertThrowsError(try store.setMultipleValues(["a": "not a number"]))
        try store.setValue(name: "a", value: 4)
        XCTAssertEqual(store.getValue(name: "double") as? Int, 8)
    }

    // MARK: - #5 / #6 expressions

    private func eval(_ expression: String, _ vars: [String: (VariableType, Any)] = [:]) throws -> Any? {
        let store = VariableStore()
        for (name, (type, value)) in vars {
            try store.defineVariable(name: name, definition: VariableDefinition(type: type, initialValue: value))
        }
        let node = try ExpressionParser().parse(expression)
        return try ExpressionEvaluator().evaluate(node, context: VariableContext(store: store))
    }

    func testArrayLiteralKeepsNonLiteralElements() throws {
        let value = try eval("{{[1, x, 3]}}", ["x": (.number, 2)]) as? [Any]
        XCTAssertEqual(value?.count, 3)
        XCTAssertEqual(value?.compactMap { $0 as? Int }, [1, 2, 3])
        let nested = try eval("{{[x + 1, [x, 'a'], name]}}", ["x": (.number, 2), "name": (.string, "n")]) as? [Any]
        XCTAssertEqual(nested?.count, 3)
        XCTAssertEqual(nested?[0] as? Int, 3)
        XCTAssertEqual((nested?[1] as? [Any])?.count, 2)
        XCTAssertEqual(nested?[2] as? String, "n")
    }

    func testArrayLiteralDependenciesAreTracked() throws {
        let node = try ExpressionParser().parse("{{[1, x, y.z]}}")
        XCTAssertEqual(DependencyExtractor().extractDependencies(from: node), ["x", "y"])
    }

    func testComputedArrayLiteralRecomputes() throws {
        let store = VariableStore()
        try store.defineVariable(name: "x", definition: VariableDefinition(type: .number, initialValue: 2))
        try store.defineVariable(name: "list", definition: VariableDefinition(type: .array, computed: "{{[1, x]}}"))
        try store.setValue(name: "x", value: 7)
        XCTAssertEqual((store.getValue(name: "list") as? [Any])?.compactMap { $0 as? Int }, [1, 7])
    }

    func testToStringOfCollectionsIsJSON() throws {
        XCTAssertEqual(try eval("{{toString(list)}}", ["list": (.array, [1, "a", true])]) as? String, #"[1,"a",true]"#)
        XCTAssertEqual(try eval("{{toString(obj)}}", ["obj": (.object, ["b": 1, "a": "x"])]) as? String, #"{"a":"x","b":1}"#)
        XCTAssertEqual(try eval("{{toString([1, 2])}}") as? String, "[1,2]")
        XCTAssertEqual(try eval("{{toString(5)}}") as? String, "5")
        XCTAssertEqual(try eval("{{toString('s')}}") as? String, "s")
    }

    // MARK: - #8 stackView cornerRadius rounds and clips children

    func testStackViewCornerRadiusClipsChildren() throws {
        let harness = RenderHarness()
        try harness.render("""
        {
          "type": "stackView", "id": "card",
          "content": {
            "properties": { "axis": "vertical", "backgroundColor": "#1C1C1E", "cornerRadius": 16 },
            "layout": { "width": 320, "top": 0, "leading": 0 },
            "children": [
              { "type": "view", "id": "header",
                "content": { "properties": { "backgroundColor": "#2C2C2E" }, "layout": { "height": 88 } } }
            ]
          }
        }
        """)
        let stack = try XCTUnwrap(harness.find(CStackViewView.self))
        XCTAssertEqual(stack.contentView.layer.cornerRadius, 16)
        XCTAssertTrue(stack.contentView.layer.masksToBounds, "children must be clipped to the rounded bounds")
    }

    func testStackViewCornerRadiusWithoutBackgroundStillClips() throws {
        let harness = RenderHarness()
        try harness.render("""
        { "type": "stackView", "id": "card",
          "content": { "properties": { "cornerRadius": 12 }, "layout": { "width": 100, "top": 0, "leading": 0 },
            "children": [ { "type": "view", "id": "c", "content": { "properties": { "backgroundColor": "#FF0000" }, "layout": { "height": 40 } } } ] } }
        """)
        let stack = try XCTUnwrap(harness.find(CStackViewView.self))
        XCTAssertEqual(stack.contentView.layer.cornerRadius, 12)
        XCTAssertTrue(stack.contentView.layer.masksToBounds)
    }
}
