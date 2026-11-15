//
//  NativeComponentTests.swift
//  App8EngineTests
//
//  DSL `native` component: decoding, fallback rendering, host factory,
//  module events → actions (`{{event.x}}`) + event bus, props updates.
//

import XCTest
import UIKit
@testable import App8Engine

@MainActor
final class NativeComponentTests: XCTestCase {

    private let module = "testSignaturePad"

    override func tearDown() {
        App8.unregisterNativeComponent(module)
        super.tearDown()
    }

    /// A `view` holding variables + one `native` child, so actions have
    /// screen-like variables to write to.
    private func screenJSON(nativeContent: String) -> String {
        """
        {
            "id": "root", "type": "view",
            "content": {
                "variables": {
                    "tint": { "type": "string", "initialValue": "#9BFFE3" },
                    "signatureId": { "type": "string", "initialValue": "" },
                    "status": { "type": "string", "initialValue": "idle" }
                },
                "layout": { "width": 390, "height": 844 },
                "children": [
                    { "id": "pad", "type": "native", "content": \(nativeContent) }
                ]
            }
        }
        """
    }

    private let fullContent = """
    {
        "properties": {
            "module": "testSignaturePad",
            "props": { "tint": "{{tint}}", "colors": ["black", "blue"], "count": 2, "label": "Sign {{status}}" }
        },
        "layout": { "leading": 0, "trailing": 0, "top": 0, "bottom": 0 },
        "actions": {
            "completed": [
                { "type": "updateVariable", "variableName": "signatureId", "value": "{{event.signature.id}}" },
                { "type": "updateVariable", "variableName": "status", "value": "done" }
            ],
            "cancelled": { "type": "updateVariable", "variableName": "status", "value": "cancelled" }
        },
        "fallback": {
            "id": "padFallback", "type": "view",
            "content": {
                "layout": { "leading": 0, "trailing": 0, "top": 0, "bottom": 0 },
                "children": [
                    { "id": "fallbackLabel", "type": "label", "content": { "properties": { "text": "Not available" }, "layout": { "centerX": 0, "centerY": 0 } } }
                ]
            }
        }
    }
    """

    private func findView(withIdentifier id: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == id { return view }
        for sub in view.subviews {
            if let found = findView(withIdentifier: id, in: sub) { return found }
        }
        return nil
    }

    private func containsRedView(_ view: UIView) -> Bool {
        if view.backgroundColor == .red { return true }
        return view.subviews.contains { containsRedView($0) }
    }

    // MARK: - Decoding

    func testDecodesModulePropsActionsAndFallback() throws {
        let json = "{ \"id\": \"pad\", \"type\": \"native\", \"content\": \(fullContent) }"
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(json.utf8))
        let entity: DSL.Model.Component.Native.Entity = try XCTUnwrap(component.asConcreteEntity())

        XCTAssertEqual(entity.content.properties.module, "testSignaturePad")
        XCTAssertEqual(entity.content.properties.props?["tint"], .string("{{tint}}"))
        XCTAssertEqual(entity.content.properties.props?["colors"], .array([.string("black"), .string("blue")]))
        XCTAssertEqual(entity.content.eventActions["completed"]?.count, 2)
        XCTAssertEqual(entity.content.eventActions["cancelled"]?.count, 1, "single-object action form decodes")
        XCTAssertEqual(entity.content.fallback?.id, "padFallback")
        XCTAssertNotNil(component.extractContent()?.layout)
    }

    func testDecodesMinimalNative() throws {
        let json = #"{ "id": "n", "type": "native", "content": { "properties": { "module": "x" } } }"#
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(json.utf8))
        let entity: DSL.Model.Component.Native.Entity = try XCTUnwrap(component.asConcreteEntity())
        XCTAssertNil(entity.content.properties.props)
        XCTAssertTrue(entity.content.eventActions.isEmpty)
        XCTAssertNil(entity.content.fallback)
    }

    func testOtherUnknownTypesStayCustom() throws {
        let pointer = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(#"{ "id": "c", "type": "myWidget" }"#.utf8))
        guard case .custom("myWidget") = pointer.type else { return XCTFail("expected .custom") }
        XCTAssertThrowsError(try JSONDecoder().decode(
            DSL.Model.Component.Any.self,
            from: Data(#"{ "id": "c", "type": "myWidget", "content": {} }"#.utf8)
        ))
    }

    // MARK: - Fallback

    func testUnregisteredModuleRendersFallback() throws {
        let harness = RenderHarness()
        try harness.render(screenJSON(nativeContent: fullContent))

        let nativeView = try XCTUnwrap(harness.find(CNativeView.self))
        XCTAssertNil(nativeView.hostedView)
        let fallback = try XCTUnwrap(findView(withIdentifier: "padFallback", in: nativeView))
        XCTAssertEqual(fallback.frame.size, CGSize(width: 390, height: 844), "fallback fills the native component")
        XCTAssertNotNil(findView(withIdentifier: "fallbackLabel", in: nativeView))
        XCTAssertFalse(containsRedView(harness.superview))
    }

    func testUnregisteredModuleWithoutFallbackRendersEmptyView() throws {
        let harness = RenderHarness()
        let content = #"{ "properties": { "module": "testSignaturePad" }, "layout": { "width": 100, "height": 100 } }"#
        try harness.render(screenJSON(nativeContent: content))

        let nativeView = try XCTUnwrap(harness.find(CNativeView.self))
        XCTAssertTrue(nativeView.contentView.subviews.isEmpty)
        XCTAssertEqual(nativeView.frame.size, CGSize(width: 100, height: 100))
        XCTAssertFalse(containsRedView(harness.superview), "no red error view")
    }

    // MARK: - Host factory

    func testRegisteredFactoryRendersHostViewWithResolvedProps() throws {
        var received: App8NativeContext?
        let hosted = UIView()
        App8.registerNativeComponent(module) { context in
            received = context
            return hosted
        }

        let harness = RenderHarness()
        try harness.render(screenJSON(nativeContent: fullContent))

        let nativeView = try XCTUnwrap(harness.find(CNativeView.self))
        XCTAssertTrue(nativeView.hostedView === hosted)
        XCTAssertNil(findView(withIdentifier: "padFallback", in: nativeView), "fallback is not rendered")
        XCTAssertEqual(hosted.frame.size, CGSize(width: 390, height: 844))

        let context = try XCTUnwrap(received)
        XCTAssertEqual(context.module, module)
        XCTAssertEqual(context.props["tint"] as? String, "#9BFFE3")
        XCTAssertEqual(context.props["colors"] as? [String], ["black", "blue"])
        XCTAssertEqual(context.props["count"] as? Double, 2)
        XCTAssertEqual(context.props["label"] as? String, "Sign idle")
        XCTAssertEqual(context.screenId, "root")
    }

    // MARK: - Events

    func testEmitRunsEventActionsWithEventInScopeAndForwardsToBus() throws {
        var received: App8NativeContext?
        App8.registerNativeComponent(module) { context in
            received = context
            return UIView()
        }
        let harness = RenderHarness()
        var busEvents: [App8Event] = []
        let subscription = harness.service.context.eventBus.subscribe { busEvents.append($0) }
        defer { subscription.cancel() }

        try harness.render(screenJSON(nativeContent: fullContent))
        let context = try XCTUnwrap(received)

        context.emit("completed", ["signature": ["id": "sig-42", "strokes": 3]])

        let root = try XCTUnwrap(harness.viewModel("root", as: CViewModel.self))
        XCTAssertEqual(root.variableStore.getValue(name: "signatureId") as? String, "sig-42")
        XCTAssertEqual(root.variableStore.getValue(name: "status") as? String, "done")

        XCTAssertEqual(busEvents.map(\.name), ["native.testSignaturePad.completed"])
        let event = try XCTUnwrap(busEvents.first)
        XCTAssertEqual(event.componentId, "pad")
        XCTAssertEqual(event.componentType, "native")
        XCTAssertEqual((event.payload["signature"] as? [String: Any])?["id"] as? String, "sig-42")

        // An event without actions still reaches the bus.
        context.emit("progress", ["step": 1])
        XCTAssertEqual(busEvents.map(\.name), ["native.testSignaturePad.completed", "native.testSignaturePad.progress"])

        context.emit("cancelled")
        XCTAssertEqual(root.variableStore.getValue(name: "status") as? String, "cancelled")
    }

    func testEmitActionInsideNativeEventSeesEvent() throws {
        var received: App8NativeContext?
        App8.registerNativeComponent(module) { context in
            received = context
            return UIView()
        }
        let content = """
        {
            "properties": { "module": "testSignaturePad" },
            "layout": { "width": 10, "height": 10 },
            "actions": {
                "failed": { "type": "emit", "name": "signature.failed", "payload": { "reason": "{{event.reason}}" } }
            }
        }
        """
        let harness = RenderHarness()
        var busEvents: [App8Event] = []
        let subscription = harness.service.context.eventBus.subscribe { busEvents.append($0) }
        defer { subscription.cancel() }
        try harness.render(screenJSON(nativeContent: content))

        try XCTUnwrap(received).emit("failed", ["reason": "permission_denied"])

        XCTAssertEqual(busEvents.map(\.name), ["native.testSignaturePad.failed", "signature.failed"])
        XCTAssertEqual(busEvents.last?.payload["reason"] as? String, "permission_denied")
    }

    // MARK: - Props updates

    func testPropsChangePushedWhenVariablesChange() throws {
        var received: App8NativeContext?
        var updates: [[String: Any]] = []
        App8.registerNativeComponent(module) { context in
            received = context
            context.onPropsChange = { updates.append($0) }
            return UIView()
        }
        let harness = RenderHarness()
        try harness.render(screenJSON(nativeContent: fullContent))
        let context = try XCTUnwrap(received)

        let root = try XCTUnwrap(harness.viewModel("root", as: CViewModel.self))
        try root.variableStore.setValue(name: "tint", value: "#2D4D3A")
        harness.drain()

        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.last?["tint"] as? String, "#2D4D3A")
        XCTAssertEqual(context.props["tint"] as? String, "#2D4D3A")

        // A change the props do not read sends nothing.
        try root.variableStore.setValue(name: "signatureId", value: "x")
        harness.drain()
        XCTAssertEqual(updates.count, 1)
    }
}
