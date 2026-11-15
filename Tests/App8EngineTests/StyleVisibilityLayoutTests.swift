//
//  StyleVisibilityLayoutTests.swift
//  App8EngineTests
//
//  Color expressions in style color fields, `properties.isHidden` on every
//  component type, analytics on native events, and collections that size to
//  their content inside a vertical scroll view.
//

import XCTest
@testable import App8Engine

@MainActor
final class StyleVisibilityLayoutTests: XCTestCase {

    private var harness: RenderHarness!

    /// The rendered view at a component path (`root.stack.remove`).
    private func view(_ path: String) -> UIView? {
        harness.service.componentRegistry.viewRegistry.view(forId: path)
    }

    private func drain(_ harness: RenderHarness?) {
        guard let harness else { return }
        harness.drain(0.1)
        harness.superview.layoutIfNeeded()
    }

    // MARK: S1 color expressions

    func testTextColorExpressionResolvesAndFollowsVariables() throws {
        harness = RenderHarness()
        try harness.render("""
        {
            "id": "root", "type": "view",
            "content": {
                "variables": { "selected": { "type": "boolean", "initialValue": false } },
                "layout": { "width": 390, "height": 844 },
                "children": [
                    { "id": "title", "type": "label",
                      "content": {
                        "properties": { "text": "Hi" },
                        "style": { "text": { "fontSize": 17, "color": "{{selected ? '#FFFFFF' : '#0D1311'}}" } },
                        "layout": { "top": 0, "leading": 0 } } }
                ]
            }
        }
        """)
        let root = try XCTUnwrap(harness.viewModel("root", as: CViewModel.self))
        let label = try XCTUnwrap(harness.viewModel("root.title", as: CLabelViewModel.self))
        XCTAssertEqual(label.currentStyle?.text?.color?.ui.hexString, "#0D1311")

        var emitted: [String?] = []
        let sub = label.style.sink { emitted.append($0?.text?.color?.ui.hexString) }
        defer { sub.cancel() }
        try root.variableStore.setValue(name: "selected", value: true)
        XCTAssertEqual(emitted.last ?? nil, "#FFFFFF")
        XCTAssertEqual(label.currentStyle?.text?.color?.ui.hexString, "#FFFFFF")
    }

    func testInvalidColorExpressionLeavesFieldUnset() throws {
        harness = RenderHarness()
        try harness.render("""
        {
            "id": "root", "type": "view",
            "content": {
                "variables": { "tone": { "type": "string", "initialValue": "not a color" } },
                "layout": { "width": 390, "height": 844 },
                "children": [
                    { "id": "title", "type": "label",
                      "content": { "properties": { "text": "Hi" }, "style": { "text": { "fontSize": 17, "color": "{{tone}}" } },
                                   "layout": { "top": 0, "leading": 0 } } }
                ]
            }
        }
        """)
        let label = try XCTUnwrap(harness.viewModel("root.title", as: CLabelViewModel.self))
        XCTAssertNil(label.currentStyle?.text?.color)
    }

    // MARK: S2 isHidden on every component

    func testIsHiddenOnButtonImageAndCollectionCollapsesStack() throws {
        harness = RenderHarness()
        try harness.render("""
        {
            "id": "root", "type": "view",
            "content": {
                "variables": { "showExtras": { "type": "boolean", "initialValue": false } },
                "layout": { "width": 390, "height": 844 },
                "children": [
                    { "id": "stack", "type": "stackView",
                      "content": {
                        "properties": { "axis": "vertical", "spacing": 10 },
                        "layout": { "top": 0, "leading": 0, "trailing": 0 },
                        "children": [
                          { "id": "head", "type": "view", "content": { "layout": { "height": 50 } } },
                          { "id": "remove", "type": "button",
                            "content": { "properties": { "text": "Remove", "isHidden": "{{!showExtras}}" }, "layout": { "height": 44 } } },
                          { "id": "photo", "type": "image",
                            "content": { "properties": { "type": "none", "isHidden": true }, "layout": { "height": 80 } } },
                          { "id": "list", "type": "collection",
                            "content": { "properties": { "data": "{{[]}}", "isHidden": "{{!showExtras}}" }, "layout": { "height": 60 },
                                         "template": { "type": "label", "content": { "properties": { "text": "x" } } } } }
                        ] } }
                ]
            }
        }
        """)
        drain(harness)
        let root = try XCTUnwrap(harness.viewModel("root", as: CViewModel.self))
        let stack = try XCTUnwrap(view("root.stack"))
        let button = try XCTUnwrap(view("root.stack.remove"))
        let image = try XCTUnwrap(view("root.stack.photo"))
        let list = try XCTUnwrap(view("root.stack.list"))

        XCTAssertTrue(button.isHidden)
        XCTAssertTrue(image.isHidden, "a literal boolean hides too")
        XCTAssertTrue(list.isHidden)
        XCTAssertEqual(stack.frame.height, 50, accuracy: 0.5, "hidden children take no space")

        try root.variableStore.setValue(name: "showExtras", value: true)
        drain(harness)
        XCTAssertFalse(button.isHidden)
        XCTAssertFalse(list.isHidden)
        XCTAssertTrue(image.isHidden)
        XCTAssertEqual(stack.frame.height, 50 + 10 + 44 + 10 + 60, accuracy: 0.5)
    }

    // MARK: A7 analytics on native events

    func testNativeEventFiresAnalyticsBindingWithEventInScope() throws {
        let module = "testAnalyticsPad"
        var received: App8NativeContext?
        App8.registerNativeComponent(module) { context in
            received = context
            return UIView()
        }
        defer { App8.unregisterNativeComponent(module) }

        harness = RenderHarness()
        var events: [App8AnalyticsEvent] = []
        let subscription = harness.service.context.analyticsBus.subscribe { events.append($0) }
        defer { subscription.cancel() }

        try harness.render("""
        {
            "id": "root", "type": "view",
            "content": {
                "layout": { "width": 390, "height": 844 },
                "children": [
                    { "id": "pad", "type": "native",
                      "content": {
                        "properties": { "module": "testAnalyticsPad" },
                        "layout": { "width": 10, "height": 10 },
                        "analytics": {
                          "completed": { "name": "padCompleted", "properties": { "stroke_count": "{{event.strokeCount}}" } },
                          "cancelled": "padCancelled"
                        } } }
                ]
            }
        }
        """)
        let context = try XCTUnwrap(received)
        context.emit("completed", ["strokeCount": 7])
        context.emit("cancelled", [:])
        context.emit("progress", [:])

        let authored = events.filter { $0.name.hasPrefix("app8.pad") }
        XCTAssertEqual(authored.map(\.name), ["app8.padCompleted", "app8.padCancelled"])
        let first = try XCTUnwrap(authored.first)
        XCTAssertEqual(first.componentId, "pad")
        XCTAssertEqual(first.componentType, "native")
        XCTAssertEqual(first.properties["stroke_count"] as? Int, 7)
    }

    // MARK: L1 collections inside a vertical scroll view size to content

    func testCollectionInsideScrollViewSizesToContent() throws {
        harness = RenderHarness()
        try harness.render("""
        {
            "id": "root", "type": "view",
            "content": {
                "variables": { "rows": { "type": "array", "initialValue": [ { "h": 40 }, { "h": 70 }, { "h": 30 } ] } },
                "layout": { "width": 390, "height": 844 },
                "children": [
                    { "id": "scroll", "type": "scrollView",
                      "content": {
                        "layout": { "leading": 0, "trailing": 0, "top": 0, "bottom": 0 },
                        "children": [
                          { "id": "stack", "type": "stackView",
                            "content": {
                              "properties": { "axis": "vertical", "spacing": 0 },
                              "layout": { "leading": 0, "trailing": 0, "top": 0, "bottom": 0 },
                              "children": [
                                { "id": "list", "type": "collection",
                                  "content": {
                                    "properties": { "data": "{{rows}}", "layout": { "type": "vertical", "itemSpacing": 10 } },
                                    "template": { "type": "view", "content": { "layout": { "height": "{{item.h}}" } } } } }
                              ] } }
                        ] } }
                ]
            }
        }
        """)
        for _ in 0..<5 { drain(harness) }
        let list = try XCTUnwrap(view("root.scroll.stack.list") as? CCollectionView)
        let inner = try XCTUnwrap(harness.find(UICollectionView.self, in: list))
        XCTAssertFalse(inner.isScrollEnabled, "the outer scroll view scrolls instead")
        XCTAssertEqual(list.frame.height, 40 + 70 + 30 + 2 * 10, accuracy: 1)
    }
}
