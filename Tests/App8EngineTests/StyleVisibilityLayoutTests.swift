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

    func testComponentColorFieldsAcceptExpressions() throws {
        harness = RenderHarness()
        try harness.render("""
        {
            "id": "root", "type": "view",
            "content": {
                "variables": {
                    "on": { "type": "boolean", "initialValue": false },
                    "tone": { "type": "string", "initialValue": "nope" }
                },
                "layout": { "width": 390, "height": 844 },
                "children": [
                    { "id": "toggle", "type": "toggle",
                      "content": {
                        "style": { "onTintColor": "{{on ? '#FF0000' : '#00FF00'}}", "thumbTintColor": "{{tone}}" },
                        "layout": { "top": 0, "leading": 0 } } },
                    { "id": "slider", "type": "slider",
                      "content": {
                        "style": { "minimumTrackTintColor": "{{on ? '#112233' : '#445566'}}" },
                        "layout": { "top": 60, "leading": 0, "width": 200 } } },
                    { "id": "spinner", "type": "activityIndicator",
                      "content": {
                        "style": { "color": "{{on ? '#ABCDEF' : '#123456'}}" },
                        "layout": { "top": 120, "leading": 0 } } }
                ]
            }
        }
        """)
        drain(harness)
        let root = try XCTUnwrap(harness.viewModel("root", as: CViewModel.self))
        let toggle = try XCTUnwrap(harness.find(UISwitch.self, in: try XCTUnwrap(view("root.toggle"))))
        let slider = try XCTUnwrap(harness.find(UISlider.self, in: try XCTUnwrap(view("root.slider"))))
        let spinner = try XCTUnwrap(harness.find(UIActivityIndicatorView.self, in: try XCTUnwrap(view("root.spinner"))))
        XCTAssertEqual(toggle.onTintColor?.hexString, "#00FF00")
        XCTAssertEqual(slider.minimumTrackTintColor?.hexString, "#445566")
        XCTAssertEqual(spinner.color.hexString, "#123456")
        XCTAssertNil(toggle.thumbTintColor, "a non-hex result leaves the field unset")

        try root.variableStore.setValue(name: "on", value: true)
        try root.variableStore.setValue(name: "tone", value: "#0000FF")
        drain(harness)
        XCTAssertEqual(toggle.onTintColor?.hexString, "#FF0000")
        XCTAssertEqual(slider.minimumTrackTintColor?.hexString, "#112233")
        XCTAssertEqual(spinner.color.hexString, "#ABCDEF")
        XCTAssertEqual(toggle.thumbTintColor?.hexString, "#0000FF")
    }

    func testPageControlTintColorsAcceptExpressions() throws {
        harness = RenderHarness()
        try harness.render("""
        {
            "id": "root", "type": "view",
            "content": {
                "variables": {
                    "dark": { "type": "boolean", "initialValue": false },
                    "dot": { "type": "string", "initialValue": "nope" }
                },
                "layout": { "width": 390, "height": 844 },
                "children": [
                    { "id": "dots", "type": "pageControl",
                      "content": {
                        "properties": { "numberOfPages": "3", "currentPage": "0" },
                        "style": {
                            "currentPageIndicatorTintColor": "{{dark ? '#111111' : '#FF0000'}}",
                            "pageIndicatorTintColor": "{{dot}}"
                        },
                        "layout": { "top": 0, "centerX": 0 } } }
                ]
            }
        }
        """)
        drain(harness)
        let root = try XCTUnwrap(harness.viewModel("root", as: CViewModel.self))
        let dots = try XCTUnwrap(harness.find(MediaPageControl.self, in: try XCTUnwrap(view("root.dots"))))
        XCTAssertEqual(dots.currentPageIndicatorTintColor?.hexString, "#FF0000")
        XCTAssertNil(dots.pageIndicatorTintColor, "a non-hex result leaves the field unset")

        try root.variableStore.setValue(name: "dark", value: true)
        try root.variableStore.setValue(name: "dot", value: "#00FF00")
        drain(harness)
        XCTAssertEqual(dots.currentPageIndicatorTintColor?.hexString, "#111111")
        XCTAssertEqual(dots.pageIndicatorTintColor?.hexString, "#00FF00")
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

    func testNonScrollingCollectionInsideCellGrowsTheCell() throws {
        harness = RenderHarness()
        try harness.render("""
        {
            "id": "root", "type": "view",
            "content": {
                "variables": { "groups": { "type": "array", "initialValue": [
                    { "id": "g1", "rows": [ { "h": 40 }, { "h": 70 }, { "h": 30 } ] }
                ] } },
                "layout": { "width": 390, "height": 844 },
                "children": [
                    { "id": "outer", "type": "collection",
                      "content": {
                        "properties": { "data": "{{groups}}", "layout": { "type": "vertical" } },
                        "layout": { "leading": 0, "trailing": 0, "top": 0, "bottom": 0 },
                        "template": { "id": "card", "type": "view", "content": { "children": [
                          { "id": "inner", "type": "collection",
                            "content": {
                              "properties": { "data": "{{item.rows}}", "layout": { "type": "vertical", "itemSpacing": 10, "scrollEnabled": false } },
                              "layout": { "leading": 0, "trailing": 0, "top": 0, "bottom": 0 },
                              "template": { "type": "view", "content": { "layout": { "height": "{{item.h}}" } } } } }
                        ] } } } }
                ]
            }
        }
        """)
        for _ in 0..<8 { drain(harness) }
        let outerView = try XCTUnwrap(view("root.outer") as? CCollectionView)
        let outer = try XCTUnwrap(harness.find(UICollectionView.self, in: outerView))
        outer.layoutIfNeeded()
        let cell = try XCTUnwrap(outer.cellForItem(at: IndexPath(item: 0, section: 0)))
        XCTAssertEqual(cell.frame.height, 40 + 70 + 30 + 2 * 10, accuracy: 1, "the cell grows to the nested collection's content")
    }

    // MARK: Conformance follow-ups

    func testLiteralBooleanAndNumberPropertiesRender() throws {
        harness = RenderHarness()
        try harness.render("""
        {
            "id": "root", "type": "view",
            "content": {
                "layout": { "width": 390, "height": 844 },
                "children": [
                    { "id": "toggle", "type": "toggle", "content": { "properties": { "isOn": true }, "layout": { "top": 0, "leading": 0 } } },
                    { "id": "slider", "type": "slider", "content": { "properties": { "value": 0.6 }, "layout": { "top": 60, "leading": 0, "width": 200 } } },
                    { "id": "dots", "type": "pageControl", "content": { "properties": { "numberOfPages": 4, "currentPage": 2 }, "layout": { "top": 120, "leading": 0 } } },
                    { "id": "spinner", "type": "activityIndicator", "content": { "properties": { "isAnimating": true, "hidesWhenStopped": false }, "layout": { "top": 180, "leading": 0 } } }
                ]
            }
        }
        """)
        drain(harness)
        let toggle = try XCTUnwrap(harness.find(UISwitch.self, in: try XCTUnwrap(view("root.toggle"))))
        let slider = try XCTUnwrap(harness.find(UISlider.self, in: try XCTUnwrap(view("root.slider"))))
        let dots = try XCTUnwrap(harness.find(MediaPageControl.self, in: try XCTUnwrap(view("root.dots"))))
        let spinner = try XCTUnwrap(harness.find(UIActivityIndicatorView.self, in: try XCTUnwrap(view("root.spinner"))))
        XCTAssertTrue(toggle.isOn)
        XCTAssertEqual(slider.value, 0.6, accuracy: 0.001)
        XCTAssertEqual(dots.numberOfPages, 4)
        XCTAssertEqual(dots.currentPage, 2)
        XCTAssertTrue(spinner.isAnimating)
    }

    func testIconTintColorPropertyExpressionSurvivesStyleUpdates() throws {
        harness = RenderHarness()
        try harness.render("""
        {
            "id": "root", "type": "view",
            "content": {
                "variables": {
                    "tone": { "type": "string", "initialValue": "#38BDF8" },
                    "on": { "type": "boolean", "initialValue": false }
                },
                "layout": { "width": 390, "height": 844 },
                "children": [
                    { "id": "star", "type": "icon",
                      "content": {
                        "properties": { "type": "symbol", "name": "star.fill", "tintColor": "{{tone}}" },
                        "style": { "symbolFontSize": 28, "color": "{{on ? '#111111' : '#222222'}}" },
                        "layout": { "top": 0, "leading": 0, "height": 32 } } }
                ]
            }
        }
        """)
        drain(harness)
        let root = try XCTUnwrap(harness.viewModel("root", as: CViewModel.self))
        let image = try XCTUnwrap(harness.find(UIImageView.self, in: try XCTUnwrap(view("root.star"))))
        XCTAssertEqual(image.tintColor.hexString, "#38BDF8")
        // A style re-emit (its color expression changes) keeps the property tint.
        try root.variableStore.setValue(name: "on", value: true)
        drain(harness)
        XCTAssertEqual(image.tintColor.hexString, "#38BDF8")
        try root.variableStore.setValue(name: "tone", value: "#FF0000")
        drain(harness)
        XCTAssertEqual(image.tintColor.hexString, "#FF0000")
    }

    func testIsHiddenExpressionOnImageAndStateOverrideOnView() throws {
        harness = RenderHarness()
        try harness.render("""
        {
            "id": "root", "type": "view",
            "content": {
                "variables": { "hide": { "type": "boolean", "initialValue": true } },
                "layout": { "width": 390, "height": 844 },
                "children": [
                    { "id": "stack", "type": "stackView",
                      "content": {
                        "properties": { "axis": "vertical", "spacing": 0 },
                        "layout": { "top": 0, "leading": 0, "trailing": 0 },
                        "children": [
                          { "id": "head", "type": "view", "content": { "layout": { "height": 50 } } },
                          { "id": "bar", "type": "image", "content": { "properties": { "isHidden": "{{hide}}" }, "layout": { "height": 30 } } },
                          { "id": "chip", "type": "view",
                            "content": {
                              "layout": { "height": 20 },
                              "states": { "gone": { "properties": { "isHidden": true } }, "shown": { "properties": { "isHidden": false } } },
                              "defaultStateName": "{{hide ? 'gone' : 'shown'}}" } },
                          { "id": "label", "type": "label",
                            "content": {
                              "properties": { "text": "x" },
                              "layout": { "height": 10 },
                              "states": { "gone": { "properties": { "isHidden": true } }, "shown": {} },
                              "defaultStateName": "{{hide ? 'gone' : 'shown'}}" } }
                        ] } }
                ]
            }
        }
        """)
        drain(harness)
        let root = try XCTUnwrap(harness.viewModel("root", as: CViewModel.self))
        let bar = try XCTUnwrap(view("root.stack.bar"))
        let chip = try XCTUnwrap(view("root.stack.chip"))
        let label = try XCTUnwrap(view("root.stack.label"))
        XCTAssertTrue(bar.isHidden, "image isHidden expression")
        XCTAssertTrue(chip.isHidden, "view hidden by a state override")
        XCTAssertTrue(label.isHidden, "a state with only isHidden in its properties")

        try root.variableStore.setValue(name: "hide", value: false)
        drain(harness)
        XCTAssertFalse(bar.isHidden)
        XCTAssertFalse(chip.isHidden)
        XCTAssertFalse(label.isHidden, "a state without isHidden keeps the base value")
    }
}
