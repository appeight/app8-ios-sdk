//
//  UniversalPropsTests.swift
//  App8Engine
//
//  Covers the universal, expression-reactive props (`interaction` + `accessibility`)
//  on every component's content, plus the per-component additions (ScrollView
//  behavior, Label text decoration).
//

import XCTest
import UIKit
@testable import App8Engine

private final class UniversalPropsStubDataSource: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data { Data() }
}

@MainActor
final class UniversalPropsTests: XCTestCase {

    private var service: App8Service!
    private var window: UIWindow!
    private let renderSize = CGSize(width: 390, height: 844)

    override func setUp() {
        super.setUp()
        service = App8Service(publicDataSource: UniversalPropsStubDataSource(), context: App8Context())
        window = UIWindow(frame: CGRect(origin: .zero, size: renderSize))
        window.makeKeyAndVisible()
    }

    override func tearDown() {
        window = nil
        service = nil
        super.tearDown()
    }

    @discardableResult
    private func render(_ json: String) throws -> App8Service.RenderResult {
        let data = json.data(using: .utf8)!
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: data)
        let superview = UIView(frame: CGRect(origin: .zero, size: renderSize))
        window.addSubview(superview)
        let result = service.renderComponent(component, superview: superview)
        superview.layoutIfNeeded()
        return result
    }

    /// Spin the main run loop briefly so a `.receive(on: .main)` sink can deliver.
    private func pumpMainLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    // MARK: - Decoding

    func testInteractionDecodesLiteralAndExpression() throws {
        let json = """
        { "enabled": "{{tapsOn}}", "clipsToBounds": "true", "zIndex": "2" }
        """
        let interaction = try JSONDecoder().decode(DSL.Model.Interaction.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(interaction.enabled, "{{tapsOn}}")
        XCTAssertEqual(interaction.clipsToBounds, "true")
        XCTAssertEqual(interaction.zIndex, "2")
        XCTAssertTrue(interaction.hasBindings)
    }

    func testAccessibilityDecodesFieldsAndTraits() throws {
        let json = """
        {
            "label": "Profile photo",
            "hint": "Double tap to change",
            "value": "{{userName}}",
            "traits": ["button", "image"],
            "isElement": "true"
        }
        """
        let a11y = try JSONDecoder().decode(DSL.Model.Accessibility.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(a11y.label, "Profile photo")
        XCTAssertEqual(a11y.value, "{{userName}}")
        XCTAssertEqual(a11y.traits, [.button, .image])
        let combined = a11y.combinedTraits
        XCTAssertNotNil(combined)
        XCTAssertTrue(combined!.contains(.button))
        XCTAssertTrue(combined!.contains(.image))
    }

    func testContentDecodesUniversalBlocks() throws {
        // The universal blocks live on `Content`, available to every component type.
        let json = """
        {
            "interaction": { "enabled": "false" },
            "accessibility": { "label": "Card" },
            "properties": {}
        }
        """
        let content = try JSONDecoder().decode(DSL.Model.Component.View.C.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(content.interaction?.enabled, "false")
        XCTAssertEqual(content.accessibility?.label, "Card")
    }

    func testContentWithoutUniversalBlocksDecodesNil() throws {
        let json = """
        { "properties": {} }
        """
        let content = try JSONDecoder().decode(DSL.Model.Component.View.C.self, from: json.data(using: .utf8)!)
        XCTAssertNil(content.interaction)
        XCTAssertNil(content.accessibility)
    }

    // MARK: - Render application

    func testInteractionEnabledForceEnablesPassiveView() throws {
        // A plain `view` is non-interactive by default; an explicit override flips it.
        let result = try render("""
        {
            "type": "view", "id": "passive",
            "content": { "interaction": { "enabled": "true" }, "properties": {} }
        }
        """)
        XCTAssertTrue(result.view.isUserInteractionEnabled)
    }

    func testClipsToBoundsAndZIndexApply() throws {
        let result = try render("""
        {
            "type": "view", "id": "clipped",
            "content": { "interaction": { "clipsToBounds": "true", "zIndex": "5" }, "properties": {} }
        }
        """)
        XCTAssertTrue(result.view.clipsToBounds)
        XCTAssertEqual(result.view.layer.zPosition, 5)
    }

    func testAccessibilityLabelHintAndTraitsApply() throws {
        let result = try render("""
        {
            "type": "view", "id": "a11y",
            "content": {
                "accessibility": { "label": "Hello", "hint": "A hint", "traits": ["button"] },
                "properties": {}
            }
        }
        """)
        XCTAssertEqual(result.view.accessibilityLabel, "Hello")
        XCTAssertEqual(result.view.accessibilityHint, "A hint")
        XCTAssertTrue(result.view.isAccessibilityElement)
        XCTAssertTrue(result.view.accessibilityTraits.contains(.button))
    }

    // MARK: - Reactive

    func testInteractionEnabledReactsToVariableChange() throws {
        let result = try render("""
        {
            "type": "view", "id": "reactive",
            "content": {
                "variables": { "enabled": { "type": "boolean", "initialValue": true } },
                "interaction": { "enabled": "{{enabled}}" },
                "properties": {}
            }
        }
        """)
        pumpMainLoop()
        XCTAssertTrue(result.view.isUserInteractionEnabled, "should reflect initial value true")

        let store = try XCTUnwrap(result.viewModel?.variableStore)
        try store.setValue(name: "enabled", value: false)
        pumpMainLoop()
        XCTAssertFalse(result.view.isUserInteractionEnabled, "should flip when variable changes")
    }

    // MARK: - ScrollView behavior props

    func testScrollViewBehaviorPropsDecode() throws {
        let json = """
        {
            "direction": "horizontal",
            "bounces": false,
            "pagingEnabled": true,
            "keyboardDismissMode": "onDrag",
            "decelerationRate": "fast"
        }
        """
        let props = try JSONDecoder().decode(DSL.Model.Component.ScrollView.Properties.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(props.bounces, false)
        XCTAssertEqual(props.pagingEnabled, true)
        XCTAssertEqual(props.keyboardDismissMode?.ui, .onDrag)
        XCTAssertEqual(props.decelerationRate?.ui, .fast)
    }

    func testScrollViewPagingAppliesToScrollView() throws {
        let result = try render("""
        {
            "type": "scrollView", "id": "scroller",
            "content": { "properties": { "direction": "horizontal", "pagingEnabled": true, "bounces": false } }
        }
        """)
        let scrollView = try XCTUnwrap(findView(ofType: UIScrollView.self, in: result.view))
        XCTAssertTrue(scrollView.isPagingEnabled)
        XCTAssertFalse(scrollView.bounces)
    }

    // MARK: - Label text decoration

    func testTextModelDecorationDecodes() throws {
        let json = """
        { "fontSize": 16, "lineBreakMode": "truncateMiddle", "underline": true, "strikethrough": true }
        """
        let model = try JSONDecoder().decode(DSL.Model.Style.TextModel.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(model.lineBreakMode?.ui, .byTruncatingMiddle)
        XCTAssertEqual(model.underline, true)
        XCTAssertEqual(model.strikethrough, true)
    }

    // MARK: - Helpers

    private func findView<T: UIView>(ofType type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        for sub in view.subviews {
            if let found = findView(ofType: type, in: sub) { return found }
        }
        return nil
    }
}
