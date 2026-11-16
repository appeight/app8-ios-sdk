//
//  BottomBarTests.swift
//  App8EngineTests
//
//  `screen.content.bottomBar` (DSL 0.6.1): decoding, layout above the bottom
//  safe area (and the tab bar), height added to the safe area, hidden with
//  animation, custom backgrounds, the iOS 26 scroll-edge effect.
//

import XCTest
import UIKit
@testable import App8Engine

@MainActor
final class BottomBarTests: XCTestCase {

    private let service = App8Service(publicDataSource: StubBottomBarDataSource(), context: App8Context())

    // MARK: - Fixtures

    private static let buttonBar = """
    {
        "id": "barActions", "type": "stackView",
        "content": {
            "properties": { "axis": "horizontal", "spacing": 12, "distribution": "fillEqually" },
            "layout": { "top": 40, "width": 100, "height": 50 },
            "children": [
                { "id": "saveButton", "type": "button", "content": { "properties": { "text": "Save" } } },
                { "id": "playButton", "type": "button", "content": { "properties": { "text": "Play" } } }
            ]
        }
    }
    """

    private static func screenJSON(bottomBar: String) -> String {
        """
        {
            "id": "clip", "type": "screen",
            "content": {
                "variables": { "barHidden": { "type": "boolean", "initialValue": false } },
                "bottomBar": \(bottomBar),
                "children": [
                    {
                        "id": "list", "type": "scrollView",
                        "content": {
                            "properties": { "direction": "vertical" },
                            "layout": { "leading": 0, "trailing": 0, "top": 0, "bottom": 0 },
                            "children": [
                                { "id": "tall", "type": "view", "content": { "layout": { "leading": 0, "trailing": 0, "top": 0, "bottom": 0, "height": 2000 } } }
                            ]
                        }
                    }
                ]
            }
        }
        """
    }

    private func render(bottomBar: String) throws -> ScreenViewController {
        let json = Self.screenJSON(bottomBar: bottomBar)
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(json.utf8))
        return try XCTUnwrap(service.renderScreen(component) as? ScreenViewController)
    }

    private func show(_ root: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = root
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in
            window.rootViewController = nil
            window.isHidden = true
        }
        settle(window)
        return window
    }

    private func settle(_ window: UIWindow, _ seconds: TimeInterval = 0.3) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
        window.layoutIfNeeded()
    }

    private func setVariable(_ name: String, _ value: Any) throws {
        let vm = try XCTUnwrap(service.componentRegistry.viewModel(forId: "clip") as? CViewModel)
        try vm.variableStore.setValue(name: name, value: value)
    }

    // MARK: - Decoding

    func testDecodingPinsTheComponentAndKeepsItsHeight() throws {
        let json = """
        { "component": \(Self.buttonBar), "insets": { "top": 20 }, "edgeEffect": "sideways", "hidden": "{{barHidden}}",
          "style": { "background": { "id": "barFill", "type": "fill", "content": { "solid": "#FFFFFF" } } } }
        """
        let bar = try JSONDecoder().decode(DSL.Model.BottomBar.self, from: Data(json.utf8))
        XCTAssertEqual(bar.edgeEffect, .soft, "unknown edge effect is soft")
        XCTAssertEqual(bar.hidden, "{{barHidden}}")
        XCTAssertEqual(bar.insets?.top, 20)
        guard case .style = bar.style?.background else { return XCTFail("fill background") }
        let screenBar = ScreenBottomBar(config: bar)
        XCTAssertEqual(screenBar.insets, UIEdgeInsets(top: 20, left: 16, bottom: 8, right: 16), "missing edges keep defaults")
        XCTAssertFalse(screenBar.usesSystemBackground)

        let layout = try XCTUnwrap(bar.component?.asEntity()?.content.layout)
        XCTAssertNil(layout.width, "layout keys other than height are ignored")
        XCTAssertNotNil(layout.height)

        let system = try JSONDecoder().decode(DSL.Model.BottomBar.self, from: Data(#"{ "component": \#(Self.buttonBar), "style": { "background": "system" } }"#.utf8))
        XCTAssertTrue(ScreenBottomBar(config: system).usesSystemBackground)
        XCTAssertEqual(ScreenBottomBar(config: system).insets, ScreenBottomBar.defaultInsets)
        XCTAssertEqual(ScreenBottomBar.defaultInsets, UIEdgeInsets(top: 12, left: 16, bottom: 8, right: 16))
    }

    // MARK: - Layout

    func testBarSitsAboveTheSafeAreaAndAddsItsHeight() throws {
        let screen = try render(bottomBar: #"{ "component": \#(Self.buttonBar) }"#)
        let nav = UINavigationController(rootViewController: screen)
        let window = show(nav)
        let bar = try XCTUnwrap(screen.bottomBar)
        let view = screen.view!

        let base = window.safeAreaInsets.bottom
        let slot = bar.contentSlot.convert(bar.contentSlot.bounds, to: view)
        XCTAssertEqual(slot.height, 50, accuracy: 0.5, "component keeps its own height")
        XCTAssertEqual(slot.maxY, view.bounds.maxY - base - 8, accuracy: 0.5, "8pt above the bottom safe area")
        XCTAssertEqual(slot.minX, 16, accuracy: 0.5)
        XCTAssertEqual(slot.maxX, view.bounds.maxX - 16, accuracy: 0.5)
        let container = bar.containerView.convert(bar.containerView.bounds, to: view)
        XCTAssertEqual(container.maxY, view.bounds.maxY, accuracy: 0.5, "the bar reaches the screen's bottom edge")
        XCTAssertEqual(container.minY, slot.minY - 12, accuracy: 0.5)

        // Height added to the bottom safe area → the scroll view's inset.
        XCTAssertEqual(bar.safeAreaContribution, 50 + 12 + 8, accuracy: 0.5)
        XCTAssertEqual(view.safeAreaInsets.bottom, base + 70, accuracy: 0.5)
        let scroll = try XCTUnwrap(ScreenViewController.firstVerticalScrollView(in: screen.rootContainerView))
        XCTAssertEqual(scroll.adjustedContentInset.bottom, base + 70, accuracy: 0.5, "scroll content clears the bar")
        XCTAssertTrue(view.subviews.last === bar.containerView, "the bar draws above the children")
        XCTAssertTrue(bar.edgeScrollView === scroll)

        if #available(iOS 26.0, *) {
            XCTAssertNil(bar.backgroundView, "iOS 26 system bar has no fill")
            let interaction = try XCTUnwrap(bar.scrollEdgeInteraction as? UIScrollEdgeElementContainerInteraction)
            XCTAssertTrue(interaction.scrollView === scroll)
            XCTAssertEqual(interaction.edge, .bottom)
            XCTAssertEqual(scroll.bottomEdgeEffect.style, .soft)
        }
    }

    func testScreenAdditionalSafeAreaAddsOnTopWithoutMovingTheBar() throws {
        let json = Self.screenJSON(bottomBar: #"{ "component": \#(Self.buttonBar), "edgeEffect": "hard" }"#)
            .replacingOccurrences(of: #""bottomBar""#, with: #""additionalSafeAreaInsets": { "bottom": 30 }, "bottomBar""#)
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(json.utf8))
        let screen = try XCTUnwrap(service.renderScreen(component) as? ScreenViewController)
        let window = show(UINavigationController(rootViewController: screen))
        let bar = try XCTUnwrap(screen.bottomBar)
        let base = window.safeAreaInsets.bottom
        let slot = bar.contentSlot.convert(bar.contentSlot.bounds, to: screen.view)
        XCTAssertEqual(slot.maxY, screen.view.bounds.maxY - base - 8, accuracy: 0.5)
        XCTAssertEqual(screen.view.safeAreaInsets.bottom, base + 70 + 30, accuracy: 0.5)
        if #available(iOS 26.0, *) {
            XCTAssertEqual(bar.edgeScrollView?.bottomEdgeEffect.style, .hard)
        }
    }

    func testBarSitsAboveTheTabBar() throws {
        let screen = try render(bottomBar: #"{ "component": \#(Self.buttonBar) }"#)
        let tabs = UITabBarController()
        let nav = UINavigationController(rootViewController: screen)
        nav.tabBarItem = UITabBarItem(title: "A", image: UIImage(systemName: "star"), selectedImage: nil)
        tabs.viewControllers = [nav]
        let window = show(tabs)
        let bar = try XCTUnwrap(screen.bottomBar)
        let tabBar = tabs.tabBar.convert(tabs.tabBar.bounds, to: window)
        let slot = bar.contentSlot.convert(bar.contentSlot.bounds, to: window)
        XCTAssertLessThanOrEqual(slot.maxY, tabBar.minY - 8 + 0.5, "above the tab bar")
        XCTAssertEqual(bar.baseBottomInset, window.bounds.maxY - tabBar.minY, accuracy: 1.5)
    }

    // MARK: - Hidden

    func testHiddenExpressionSlidesTheBarAndDropsItsSpace() throws {
        let screen = try render(bottomBar: #"{ "component": \#(Self.buttonBar), "hidden": "{{barHidden}}" }"#)
        let window = show(UINavigationController(rootViewController: screen))
        let bar = try XCTUnwrap(screen.bottomBar)
        let base = window.safeAreaInsets.bottom
        XCTAssertFalse(bar.isHidden)
        XCTAssertEqual(screen.view.safeAreaInsets.bottom, base + 70, accuracy: 0.5)

        try setVariable("barHidden", true)
        settle(window, 0.6)
        XCTAssertTrue(bar.isHidden)
        XCTAssertEqual(bar.safeAreaContribution, 0)
        XCTAssertEqual(screen.view.safeAreaInsets.bottom, base, accuracy: 0.5, "the safe area shrinks back")
        XCTAssertEqual(bar.containerView.alpha, 0)
        XCTAssertEqual(bar.containerView.transform.ty, bar.containerView.bounds.height, accuracy: 0.5, "slid down by its height")
        XCTAssertFalse(bar.containerView.isUserInteractionEnabled)

        try setVariable("barHidden", false)
        settle(window, 0.6)
        XCTAssertFalse(bar.isHidden)
        XCTAssertEqual(bar.containerView.alpha, 1)
        XCTAssertEqual(bar.containerView.transform, .identity)
        XCTAssertEqual(screen.view.safeAreaInsets.bottom, base + 70, accuracy: 0.5)
    }

    func testHidingKeepsAKeyboardInset() throws {
        let screen = try render(bottomBar: #"{ "component": \#(Self.buttonBar), "hidden": "{{barHidden}}" }"#)
        let window = show(UINavigationController(rootViewController: screen))
        let bar = try XCTUnwrap(screen.bottomBar)
        // The keyboard binding adds its inset on top of the bar's height.
        let keyboard: CGFloat = 250
        screen.additionalSafeAreaInsets.bottom += keyboard
        settle(window, 0.1)
        let keyboardBar = bar.containerView.convert(bar.containerView.bounds, to: screen.view)
        XCTAssertEqual(keyboardBar.maxY, screen.view.bounds.maxY, accuracy: 0.5, "the keyboard does not move the bar")

        try setVariable("barHidden", true)
        settle(window, 0.6)
        XCTAssertEqual(screen.additionalSafeAreaInsets.bottom, keyboard, accuracy: 0.5, "only the bar's height is removed")
        try setVariable("barHidden", false)
        settle(window, 0.6)
        XCTAssertEqual(screen.additionalSafeAreaInsets.bottom, keyboard + 70, accuracy: 0.5)
    }

    func testBarThatStartsHiddenTakesNoSpace() throws {
        let screen = try render(bottomBar: #"{ "component": \#(Self.buttonBar), "hidden": true }"#)
        let window = show(UINavigationController(rootViewController: screen))
        let bar = try XCTUnwrap(screen.bottomBar)
        XCTAssertTrue(bar.isHidden)
        XCTAssertEqual(bar.containerView.alpha, 0)
        XCTAssertEqual(screen.view.safeAreaInsets.bottom, window.safeAreaInsets.bottom, accuracy: 0.5)
        XCTAssertEqual(bar.contentSlot.bounds.height, 50, accuracy: 0.5, "laid out")
    }

    // MARK: - Backgrounds

    func testFillBackgroundReplacesTheSystemTreatment() throws {
        let screen = try render(bottomBar: """
        { "component": \(Self.buttonBar),
          "style": { "background": { "id": "barFill", "type": "fill", "content": { "solid": "#FF0000" } } } }
        """)
        _ = show(UINavigationController(rootViewController: screen))
        let bar = try XCTUnwrap(screen.bottomBar)
        XCTAssertTrue(bar.backgroundView is MaterialView, "fill drawn by a material view")
        XCTAssertNil(bar.scrollEdgeInteraction, "no scroll-edge effect with a custom background")
    }

    func testMaterialBackground() throws {
        let screen = try render(bottomBar: """
        { "component": \(Self.buttonBar),
          "style": { "background": { "id": "barMaterial", "type": "material", "content": [
              { "id": "barMaterialFill", "type": "fill", "content": { "solid": "#FFFFFF" } }
          ] } } }
        """)
        _ = show(UINavigationController(rootViewController: screen))
        XCTAssertTrue(screen.bottomBar?.backgroundView is MaterialView)
    }

    // MARK: - Buttons run in the screen's scope

    func testBarComponentReadsScreenVariables() throws {
        let bar = """
        { "component": { "id": "barLabel", "type": "label", "content": { "properties": { "text": "{{barHidden ? 'hidden' : 'shown'}}" } } } }
        """
        let screen = try render(bottomBar: bar)
        let window = show(UINavigationController(rootViewController: screen))
        func labelText() -> String? {
            func find(_ v: UIView) -> UILabel? { (v as? UILabel) ?? v.subviews.lazy.compactMap(find).first }
            return find(screen.bottomBar!.contentSlot)?.text
        }
        XCTAssertEqual(labelText(), "shown")
        XCTAssertGreaterThan(screen.bottomBar!.contentSlot.bounds.height, 0, "fitting height")
        _ = window
    }
}

private final class StubBottomBarDataSource: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
}
