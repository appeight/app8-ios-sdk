import XCTest
import UIKit
@testable import App8Engine

/// `navigationBar.search` as a button that opens a search screen, the search
/// screen's field (autoFocus, onCancel, hidesBackButton), the focused field
/// staying inside the bar, and the tab bar following an interactive pop.
@MainActor
final class SearchNavigationTests: XCTestCase {
    typealias DS = SearchFillsBarTests.BundleDataSource

    private static let rightActions: [[String: Any]] = [["icon": "bell", "action": ["type": "navigation", "nextScreen": "home"]]]

    private func bundle(homeNav: [String: Any], extraScreens: [String: Any] = [:]) -> [String: Any] {
        var screens: [String: Any] = [
            "tabs": ["type": "tabBarScreen", "id": "tabs", "content": [
                "tabs": [["id": "home", "label": "Home", "icon": "magnifyingglass", "screen": "home"],
                         ["id": "inbox", "label": "Inbox", "icon": "tray", "screen": "home"]],
                "initialTab": "home"] as [String: Any]],
            "home": ["type": "screen", "id": "home", "content": [
                "navigationBar": homeNav,
                "variables": ["q": ["type": "string", "initialValue": ""], "tapped": ["type": "boolean", "initialValue": false]],
                "children": [] as [Any]
            ] as [String: Any]]
        ]
        extraScreens.forEach { screens[$0.key] = $0.value }
        return ["bundle": [
            "app": ["title": "T", "navigation": ["startFlow": "f", "flows": [["id": "f", "startScreen": "tabs"]]]],
            "styles": [], "components": [], "screens": screens
        ] as [String: Any]]
    }

    private var window: UIWindow!
    private var instance: App8.Instance!

    override func tearDown() async throws {
        window?.rootViewController = nil
        window = nil
        instance = nil
    }

    private func start(_ env: [String: Any]) async throws -> ScreenViewController {
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.makeKeyAndVisible()
        instance = App8.instance(dataSource: try DS(envelope: env))
        window.rootViewController = try await instance.startApp()
        window.layoutIfNeeded()
        for _ in 0..<8 { try await Task.sleep(nanoseconds: 100_000_000) }
        return try XCTUnwrap(all(window).compactMap { $0.next as? ScreenViewController }.first)
    }

    private func all(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(all) }

    private func render(_ json: String) async throws -> ScreenViewController {
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(json.utf8))
        let service = try XCTUnwrap((instance as? A8)?.appService)
        let vc = await service.renderScreen(component, screenId: component.id)
        return try XCTUnwrap(vc as? ScreenViewController)
    }

    private func settle(_ nav: UINavigationController, on top: UIViewController) async throws {
        for _ in 0..<60 where nav.topViewController !== top || nav.transitionCoordinator != nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    // MARK: - Button mode

    /// `mode: "button"`: the system field never takes focus; the tap runs `onTap`.
    func testButtonModeRunsOnTapInsteadOfFocusing() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("iOS 26 bar") }
        let home = try await start(bundle(homeNav: ["search": [
            "placeholder": "Search", "placement": "integrated", "fillsBar": true, "mode": "button",
            "onTap": ["type": "updateVariable", "variableName": "tapped", "value": true]
        ]]))
        let controller = try XCTUnwrap(home.navigationItem.searchController)
        let field = controller.searchBar.searchTextField
        XCTAssertFalse(field.becomeFirstResponder(), "a button field must not start editing")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(field.isFirstResponder)
        XCTAssertEqual(home.screenVariableStore?.getValue(name: "tapped") as? Bool, true, "onTap ran")
    }

    // MARK: - Focused field inside the bar

    /// Focusing a fillsBar field beside a trailing item: every frame of the
    /// focus animation keeps the field inside the screen, it settles at the
    /// leading margin, and unfocused it ends before the item instead of
    /// pushing the row past the leading edge.
    func testFocusedFieldStaysInsideTheBar() async throws {
        guard #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iOS 26 iPhone layout") }
        let home = try await start(bundle(homeNav: [
            "search": ["placeholder": "Search", "bindVariable": "q", "placement": "integrated", "fillsBar": true],
            "rightActions": Self.rightActions
        ]))
        let controller = try XCTUnwrap(home.navigationItem.searchController)
        let field = controller.searchBar.searchTextField
        let bar = try XCTUnwrap(home.navigationController?.navigationBar)
        /// On screen, as drawn mid-animation (presentation layers up to the window).
        func fieldFrame() -> CGRect? {
            guard let host = field.window else { return nil }
            var rect = (field.layer.presentation() ?? field.layer).bounds
            var layer: CALayer? = field.layer
            while let l = layer, l !== host.layer {
                let p = l.presentation() ?? l
                rect = p.convert(rect, to: p.superlayer)
                layer = l.superlayer
            }
            return rect
        }
        func barButtons() -> [CGRect] {
            all(bar).filter { String(describing: type(of: $0)) == "_UIButtonBarButton" && !$0.isHidden && $0.alpha > 0.01 }
                .map { $0.convert($0.bounds, to: window) }
        }

        // UIKit lays the trailing items out before the integrated field: [item][field].
        let idle = try XCTUnwrap(fieldFrame(), "the field collapsed into a search button")
        XCTAssertLessThanOrEqual(idle.maxX, window.bounds.width - 15.5, "unfocused field \(idle)")
        for button in barButtons() {
            XCTAssertGreaterThanOrEqual(button.minX, 0, "trailing item pushed off screen: \(button)")
            XCTAssertLessThanOrEqual(button.maxX, idle.minX, "trailing item \(button) overlaps the field \(idle)")
        }

        controller.isActive = true
        var samples: [CGRect] = []
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 30_000_000)
            if let f = fieldFrame() { samples.append(f) }
        }
        try await Task.sleep(nanoseconds: 400_000_000)
        // The reported bug: the focused field slid out past the leading edge.
        for f in samples {
            XCTAssertGreaterThanOrEqual(f.minX, -0.5, "field slid past the leading edge: \(f)")
        }
        if let focused = fieldFrame() {
            XCTAssertGreaterThanOrEqual(focused.minX, 15.5, "focused field \(focused)")
            XCTAssertLessThanOrEqual(focused.maxX, window.bounds.width - 15.5, "focused field \(focused)")
        }

        controller.isActive = false
        try await Task.sleep(nanoseconds: 700_000_000)
        let after = try XCTUnwrap(fieldFrame(), "the field collapsed after cancel")
        XCTAssertEqual(after.minX, idle.minX, accuracy: 0.5, "field after cancel \(after) vs \(idle)")
        for button in barButtons() {
            XCTAssertGreaterThanOrEqual(button.minX, 0, "trailing item pushed off screen: \(button)")
        }
    }

    // MARK: - Search screen

    /// A pushed search screen: back button hidden, field focused once the push
    /// lands, at the same place as the first screen's button field; the ✕
    /// runs `onCancel` (here: back).
    func testSearchScreenFocusesInPlaceAndCancelPops() async throws {
        guard #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iOS 26 iPhone layout") }
        let home = try await start(bundle(homeNav: [
            "search": ["placeholder": "Search", "placement": "integrated", "fillsBar": true, "mode": "button",
                       "onTap": ["type": "navigation", "nextScreen": "search"]],
            "rightActions": Self.rightActions
        ]))
        let nav = try XCTUnwrap(home.navigationController)
        let homeField = try XCTUnwrap(home.navigationItem.searchController).searchBar.searchTextField
        let homeFrame = homeField.convert(homeField.bounds, to: window)

        let search = try await render(##"""
        {"type":"screen","id":"search","content":{"navigationBar":{"hidesBackButton":true,
          "search":{"placeholder":"Search","bindVariable":"query","placement":"integrated","fillsBar":true,"autoFocus":true,
                    "onCancel":{"type":"navigation","isBack":true}},
          "rightActions":[{"icon":"bell","action":{"type":"navigation","nextScreen":"home"}}]},
          "variables":{"query":{"type":"string","initialValue":""}},"children":[]}}
        """##)
        XCTAssertTrue(search.navigationItem.hidesBackButton)
        nav.pushViewController(search, animated: true)
        try await settle(nav, on: search)
        try await Task.sleep(nanoseconds: 600_000_000)
        let controller = try XCTUnwrap(search.navigationItem.searchController)
        XCTAssertTrue(controller.isActive, "autoFocus activates the field")

        // Unfocused, the search screen's field sits exactly where the button was.
        controller.isActive = false
        try await Task.sleep(nanoseconds: 700_000_000)
        let field = controller.searchBar.searchTextField
        let searchFrame = field.convert(field.bounds, to: window)
        XCTAssertEqual(searchFrame.minX, homeFrame.minX, accuracy: 0.5)
        XCTAssertEqual(searchFrame.minY, homeFrame.minY, accuracy: 0.5)
        XCTAssertEqual(searchFrame.width, homeFrame.width, accuracy: 0.5)

        // The ✕ (UIKit calls the delegate) runs onCancel: a back navigation request.
        final class Pops: @unchecked Sendable { var count = 0 }
        let pops = Pops()
        let token = NotificationCenter.default.addObserver(forName: .app8NavigationRequest, object: nil, queue: nil) { note in
            if let request = note.object as? NavigationRequest, case .pop = request.type { pops.count += 1 }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        search.searchBarCancelButtonClicked(controller.searchBar)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(pops.count, 1, "onCancel asks to go back once")
    }

    /// A write to `bindVariable` from elsewhere (a recent search tapped) shows in the field.
    func testBoundVariableWritesReachTheField() async throws {
        let home = try await start(bundle(homeNav: ["search": ["placeholder": "Search", "bindVariable": "q"]]))
        let controller = try XCTUnwrap(home.navigationItem.searchController)
        try home.screenVariableStore?.setValue(name: "q", value: "blue")
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(controller.searchBar.text, "blue")
    }

    // MARK: - Tab bar during pop

    /// Popping back to a screen with the tab bar: the bar starts below the
    /// bottom edge and slides up with the transition (UIKit on iOS 26 shows it
    /// at once), then rests where it was.
    func testTabBarSlidesInWithThePop() async throws {
        let home = try await start(bundle(homeNav: ["title": "Home"]))
        let nav = try XCTUnwrap(home.navigationController)
        let tabBar = try XCTUnwrap(home.tabBarController?.tabBar)
        let resting = tabBar.frame
        let detail = try await render(##"{"type":"screen","id":"detail","content":{"hidesTabBar":true,"navigationBar":{"title":"Detail"},"children":[]}}"##)
        nav.pushViewController(detail, animated: true)
        try await settle(nav, on: detail)

        nav.popViewController(animated: true)
        var offsets: [CGFloat] = []
        for _ in 0..<14 {
            offsets.append((tabBar.layer.presentation() ?? tabBar.layer).frame.minY - resting.minY)
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        try await settle(nav, on: home)
        // The transition starts on the next run loop.
        offsets = Array(offsets.drop { $0 == 0 })
        let first = try XCTUnwrap(offsets.first)
        XCTAssertGreaterThan(first, resting.height * 0.5, "the bar starts below its resting place: \(offsets)")
        for (a, b) in zip(offsets, offsets.dropFirst()) {
            XCTAssertLessThanOrEqual(b, a + 0.5, "the bar only moves up: \(offsets)")
        }
        XCTAssertEqual(tabBar.transform, .identity)
        XCTAssertEqual(tabBar.frame, resting)
        XCTAssertFalse(tabBar.isHidden)
    }

    /// Pushing and popping a screen that keeps the tab bar never moves it.
    func testTabBarStillForScreensThatKeepIt() async throws {
        let home = try await start(bundle(homeNav: ["title": "Home"]))
        let nav = try XCTUnwrap(home.navigationController)
        let tabBar = try XCTUnwrap(home.tabBarController?.tabBar)
        let detail = try await render(##"{"type":"screen","id":"detail","content":{"navigationBar":{"title":"Detail"},"children":[]}}"##)
        nav.pushViewController(detail, animated: true)
        try await settle(nav, on: detail)
        nav.popViewController(animated: true)
        for _ in 0..<8 {
            XCTAssertEqual(tabBar.transform, .identity)
            try await Task.sleep(nanoseconds: 40_000_000)
        }
    }
}
