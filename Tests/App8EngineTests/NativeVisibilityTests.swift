//
//  NativeVisibilityTests.swift
//  App8EngineTests
//
//  `native` component visibility (DSL 0.6.1): `App8NativeContext.isVisible`
//  + `onVisibilityChange`, the `appear` / `disappear` actions, and the rules
//  — built is not shown, push / pop, modal, tabs, isHidden, background,
//  snapshots, cells, reserved event names.
//

import XCTest
import UIKit
@testable import App8Engine

@MainActor
final class NativeVisibilityTests: XCTestCase {

    private static let module = "testVisibilityProbe"

    /// Every context the factory handed out, with the changes it reported.
    @MainActor
    private final class Probe {
        var contexts: [App8NativeContext] = []
        var changes: [[Bool]] = []
        var initialValues: [Bool] = []

        func register() {
            App8.registerNativeComponent(NativeVisibilityTests.module) { [unowned self] context in
                let index = self.contexts.count
                self.contexts.append(context)
                self.changes.append([])
                self.initialValues.append(context.isVisible)
                context.onVisibilityChange = { [unowned self] visible in
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertEqual(context.isVisible, visible, "isVisible is updated before the callback")
                    self.changes[index].append(visible)
                }
                let view = UIView()
                view.backgroundColor = .red
                return view
            }
        }
    }

    private var probe = Probe()

    override func setUp() {
        super.setUp()
        probe = Probe()
        probe.register()
        NativeVisibility.setAppInForeground(true)
    }

    override func tearDown() {
        App8.unregisterNativeComponent(Self.module)
        NativeVisibility.setAppInForeground(true)
        super.tearDown()
    }

    // MARK: - Fixtures

    private static func screenJSON(id: String, extra: String = "") -> String {
        """
        {
            "id": "\(id)", "type": "screen",
            "content": {
                "variables": {
                    "appearCount": { "type": "number", "initialValue": 0 },
                    "disappearCount": { "type": "number", "initialValue": 0 },
                    "probeHidden": { "type": "boolean", "initialValue": false }
                },
                \(extra)
                "children": [
                    {
                        "id": "probe", "type": "native",
                        "content": {
                            "properties": { "module": "\(module)", "isHidden": "{{probeHidden}}" },
                            "layout": { "leading": 0, "trailing": 0, "top": 100, "height": 200 },
                            "actions": {
                                "appear": { "type": "incrementVariable", "variableName": "appearCount", "by": 1 },
                                "disappear": { "type": "incrementVariable", "variableName": "disappearCount", "by": 1 }
                            }
                        }
                    }
                ]
            }
        }
        """
    }

    private let service = App8Service(publicDataSource: StubVisibilityDataSource(), context: App8Context())
    private var windows: [UIWindow] = []

    private func renderScreen(_ id: String, extra: String = "") throws -> ScreenViewController {
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(Self.screenJSON(id: id, extra: extra).utf8))
        return try XCTUnwrap(service.renderScreen(component) as? ScreenViewController)
    }

    private func show(_ root: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = root
        window.makeKeyAndVisible()
        windows.append(window)
        addTeardownBlock { @MainActor in
            window.rootViewController = nil
            window.isHidden = true
        }
        return window
    }

    private func screenVariable(_ screenId: String, _ name: String) -> Double? {
        let vm = service.componentRegistry.viewModel(forId: screenId) as? CViewModel
        return (vm?.variableStore.getValue(name: name) as? NSNumber)?.doubleValue
            ?? vm?.variableStore.getValue(name: name) as? Double
    }

    private func setScreenVariable(_ screenId: String, _ name: String, _ value: Any) throws {
        let vm = try XCTUnwrap(service.componentRegistry.viewModel(forId: screenId) as? CViewModel)
        try vm.variableStore.setValue(name: name, value: value)
    }

    private func waitUntil(_ timeout: TimeInterval = 3, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func drain(_ seconds: TimeInterval = 0.15) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - Built is not shown

    func testRenderedScreenIsNotVisibleUntilItAppears() throws {
        let screen = try renderScreen("home")
        drain()
        XCTAssertEqual(probe.contexts.count, 1)
        XCTAssertEqual(probe.initialValues, [false], "starts not visible in the factory")
        XCTAssertFalse(probe.contexts[0].isVisible, "a built screen (view loaded, not shown) is not visible")
        XCTAssertEqual(probe.changes[0], [])

        let nav = UINavigationController(rootViewController: screen)
        _ = show(nav)
        waitUntil { probe.contexts[0].isVisible }
        XCTAssertEqual(probe.changes[0], [true], "true once, after the screen appeared")
        waitUntil { screenVariable("home", "appearCount") == 1 }
        XCTAssertEqual(screenVariable("home", "appearCount"), 1, "DSL `appear` ran")
        XCTAssertEqual(screenVariable("home", "disappearCount"), 0)
    }

    // MARK: - Push / pop

    func testPushOverAndPopBack() throws {
        let home = try renderScreen("home")
        let nav = UINavigationController(rootViewController: home)
        _ = show(nav)
        waitUntil { probe.contexts.first?.isVisible == true }

        let detail = try renderScreen("detail")
        nav.pushViewController(detail, animated: true)
        // false as the push starts, before it completes.
        XCTAssertEqual(probe.changes[0], [true, false], "pushed-over screen reports false when the transition starts")
        waitUntil { probe.contexts[1].isVisible }
        XCTAssertEqual(probe.changes[1], [true])

        nav.popViewController(animated: true)
        XCTAssertEqual(probe.changes[1], [true, false], "popped screen reports false at the start of the pop")
        waitUntil { probe.contexts[0].isVisible }
        XCTAssertEqual(probe.changes[0], [true, false, true])
        waitUntil { screenVariable("home", "appearCount") == 2 }
        XCTAssertEqual(screenVariable("home", "appearCount"), 2)
        XCTAssertEqual(screenVariable("home", "disappearCount"), 1)
    }

    // MARK: - Modal

    func testModalCoversTheScreenBelow() throws {
        let home = try renderScreen("home")
        let nav = UINavigationController(rootViewController: home)
        _ = show(nav)
        waitUntil { probe.contexts.first?.isVisible == true }

        for style in [UIModalPresentationStyle.pageSheet, .fullScreen] {
            let sheet = UINavigationController(rootViewController: try renderScreen("sheet\(style.rawValue)"))
            sheet.modalPresentationStyle = style
            let before = probe.changes[0].count
            nav.present(sheet, animated: true)
            XCTAssertEqual(probe.changes[0].count, before + 1, "covered as the presentation starts (\(style.rawValue))")
            XCTAssertEqual(probe.changes[0].last, false)
            let sheetIndex = probe.contexts.count - 1
            waitUntil { probe.contexts[sheetIndex].isVisible }
            XCTAssertTrue(probe.contexts[sheetIndex].isVisible)
            XCTAssertFalse(probe.contexts[0].isVisible, "still covered while the modal is up")

            nav.dismiss(animated: true)
            XCTAssertFalse(probe.contexts[sheetIndex].isVisible, "dismissed screen is false at the start")
            waitUntil { probe.contexts[0].isVisible }
            XCTAssertTrue(probe.contexts[0].isVisible, "uncovered after the dismissal completes (\(style.rawValue))")
        }
        XCTAssertEqual(probe.changes[0], [true, false, true, false, true], "never the same value twice")
    }

    func testAlertDoesNotCoverTheScreen() throws {
        let home = try renderScreen("home")
        let nav = UINavigationController(rootViewController: home)
        _ = show(nav)
        waitUntil { probe.contexts.first?.isVisible == true }
        let alert = UIAlertController(title: "A", message: nil, preferredStyle: .alert)
        nav.present(alert, animated: false)
        drain()
        XCTAssertTrue(probe.contexts[0].isVisible)
        XCTAssertFalse(NativeVisibility.isCovered(home))
        alert.dismiss(animated: false)
        drain()
        XCTAssertEqual(probe.changes[0], [true])
    }

    // MARK: - Tabs

    func testOnlyTheSelectedTabIsVisible() throws {
        let first = UINavigationController(rootViewController: try renderScreen("tabA"))
        let second = UINavigationController(rootViewController: try renderScreen("tabB"))
        let tabs = UITabBarController()
        tabs.viewControllers = [first, second]
        // Prebuilt tab root: view loaded, never shown.
        _ = second.topViewController?.view
        _ = show(tabs)
        waitUntil { probe.contexts[0].isVisible }
        drain()
        XCTAssertTrue(probe.contexts[0].isVisible)
        XCTAssertFalse(probe.contexts[1].isVisible, "a tab that is not selected is not visible")

        tabs.selectedIndex = 1
        waitUntil { probe.contexts[1].isVisible }
        XCTAssertFalse(probe.contexts[0].isVisible)
        XCTAssertTrue(probe.contexts[1].isVisible)
        XCTAssertEqual(probe.changes[0], [true, false])
        XCTAssertEqual(probe.changes[1], [true])
    }

    // MARK: - isHidden, background, removal

    func testIsHiddenBackgroundAndRemoval() throws {
        let home = try renderScreen("home")
        let nav = UINavigationController(rootViewController: home)
        let window = show(nav)
        waitUntil { probe.contexts.first?.isVisible == true }

        try setScreenVariable("home", "probeHidden", true)
        waitUntil { probe.contexts[0].isVisible == false }
        XCTAssertEqual(probe.changes[0], [true, false], "isHidden makes it not visible")
        try setScreenVariable("home", "probeHidden", false)
        waitUntil { probe.contexts[0].isVisible }
        XCTAssertEqual(probe.changes[0], [true, false, true])

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(probe.contexts[0].isVisible, "background applies at once")
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        XCTAssertTrue(probe.contexts[0].isVisible)
        XCTAssertEqual(probe.changes[0], [true, false, true, false, true])

        window.rootViewController = nil
        XCTAssertFalse(probe.contexts[0].isVisible, "false when the view leaves the window")
        XCTAssertEqual(probe.changes[0].last, false)
        XCTAssertEqual(screenVariable("home", "disappearCount"), 3)
    }

    // MARK: - Fallback

    func testFallbackRunsAppearAndDisappear() throws {
        App8.unregisterNativeComponent(Self.module)
        let home = try renderScreen("home")
        let nav = UINavigationController(rootViewController: home)
        _ = show(nav)
        waitUntil { screenVariable("home", "appearCount") == 1 }
        XCTAssertEqual(screenVariable("home", "appearCount"), 1, "fallback (none here) still has a visibility")
        nav.pushViewController(try renderScreen("detail"), animated: false)
        waitUntil { screenVariable("home", "disappearCount") == 1 }
        XCTAssertEqual(screenVariable("home", "disappearCount"), 1)
    }

    // MARK: - Reserved names

    func testModuleCannotEmitReservedNames() throws {
        let home = try renderScreen("home")
        drain()
        let context = try XCTUnwrap(probe.contexts.first)
        var busNames: [String] = []
        let subscription = service.context.eventBus.subscribe { event in busNames.append(event.name) }
        defer { subscription.cancel() }
        context.emit("appear")
        context.emit("disappear")
        drain()
        XCTAssertEqual(screenVariable("home", "appearCount"), 0, "a module can't run `appear`")
        XCTAssertEqual(screenVariable("home", "disappearCount"), 0)
        XCTAssertFalse(busNames.contains { $0.hasSuffix(".appear") || $0.hasSuffix(".disappear") })
        _ = home
    }

    // MARK: - Snapshot

    func testOffscreenRenderIsNeverVisible() throws {
        let home = try renderScreen("home")
        home.rendersOffscreen = true
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = home
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        drain(0.3)
        XCTAssertFalse(probe.contexts[0].isVisible, "snapshot windows are never visible")
        XCTAssertEqual(probe.changes[0], [])
        window.isHidden = true
        window.rootViewController = nil
    }
}

private final class StubVisibilityDataSource: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
}
