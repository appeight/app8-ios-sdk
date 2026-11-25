import XCTest
import UIKit
@testable import App8Engine

/// styles.md: `style.alpha` is a number or an expression (since 0.7.17). Before, an
/// expression failed the style's decoding: a component in a list lost the field, and a
/// bottom bar's component failed the whole screen, which then never opened (the error was
/// logged only in debug). A mistyped style field is now ignored with a warning everywhere.
@MainActor
final class StyleAlphaExpressionTests: XCTestCase {
    private typealias DS = SearchFillsBarTests.BundleDataSource

    // MARK: - Decoding

    private func labelStyle(_ alpha: String) throws -> DSL.Model.Style.Label {
        try JSONDecoder().decode(DSL.Model.Style.Label.self, from: Data(#"{ "alpha": \#(alpha) }"#.utf8))
    }

    func testAlphaDecodesNumbersExpressionsAndIgnoresAnythingElse() throws {
        XCTAssertEqual(try labelStyle("0.4").alpha, 0.4)
        XCTAssertEqual(try labelStyle(#""0.4""#).alpha, 0.4, "a number in a string")
        let expr = try labelStyle(#""{{ready ? 1 : 0.35}}""#)
        XCTAssertNil(expr.alpha)
        XCTAssertEqual(expr.alphaSlot.expression, "{{ready ? 1 : 0.35}}")
        XCTAssertNil(try labelStyle("[1]").alpha, "never fails the style")
        XCTAssertNil(try JSONDecoder().decode(DSL.Model.Style.View.self, from: Data("{}".utf8)).alpha)
    }

    // MARK: - Rendering

    private static func bundle() -> [String: Any] {
        ["bundle": [
            "app": ["title": "T", "navigation": ["startFlow": "f", "flows": [["id": "f", "startScreen": "home"]]]],
            "styles": [], "components": [],
            "screens": [
                "home": ["type": "screen", "id": "home", "content": [
                    "variables": ["ready": ["type": "boolean", "initialValue": false]],
                    "navigationBar": ["title": "Home", "rightActions": [
                        ["label": "Ready", "action": ["type": "updateVariable", "variableName": "ready", "value": "{{!ready}}"]],
                        ["label": "Open", "action": ["type": "navigation", "nextScreen": "sheet", "presentation": "push"]],
                    ]],
                    "children": [
                        ["id": "next", "type": "label", "content": [
                            "properties": ["text": "Next"],
                            "style": ["alpha": "{{ready ? 1 : 0.35}}"],
                            "layout": ["constraints": [["type": "top", "target": "safeArea"], ["type": "leading", "target": "superview"]]]
                        ] as [String: Any]]
                    ]
                ] as [String: Any]],
                // The shape of the screen that never opened: a bottom bar whose component has an alpha
                // expression, plus a mistyped style field (`transform` must be an object).
                "sheet": ["type": "screen", "id": "sheet", "content": [
                    "variables": ["pick": ["type": "array", "initialValue": [] as [Any]]],
                    "bottomBar": ["component": ["id": "save", "type": "view", "content": [
                        "style": ["alpha": "{{length(pick) > 0 ? 1 : 0.35}}", "transform": 5],
                        "layout": ["height": 48]
                    ] as [String: Any]]],
                    "children": [] as [Any]
                ] as [String: Any]]
            ] as [String: Any]
        ] as [String: Any]]
    }

    private func views(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(views) }

    private func settle() async throws {
        for _ in 0..<5 { try await Task.sleep(nanoseconds: 100_000_000) }
    }

    func testStyleAlphaExpressionFollowsItsVariable() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.makeKeyAndVisible()
        defer { window.rootViewController = nil }
        let instance = App8.instance(dataSource: try DS(envelope: Self.bundle()))
        window.rootViewController = try await instance.startApp()
        window.layoutIfNeeded()
        try await settle()
        let next = try XCTUnwrap(views(window).first { $0.accessibilityIdentifier == "next" })
        XCTAssertEqual(next.alpha, 0.35, accuracy: 0.001)

        let home = try XCTUnwrap(views(window).compactMap { $0.next as? ScreenViewController }.first { $0.screenId == "home" })
        let items = Array(try XCTUnwrap(home.navigationItem.rightBarButtonItems).reversed())
        items[0].primaryAction?.performWithSender(nil, target: nil)
        try await settle()
        XCTAssertEqual(next.alpha, 1, accuracy: 0.001, "re-evaluated when `ready` changes")
    }

    func testScreenWithAlphaExpressionAndMistypedStyleInItsBottomBarOpens() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.makeKeyAndVisible()
        defer { window.rootViewController = nil }
        let instance = App8.instance(dataSource: try DS(envelope: Self.bundle()))
        window.rootViewController = try await instance.startApp()
        window.layoutIfNeeded()
        try await settle()
        let home = try XCTUnwrap(views(window).compactMap { $0.next as? ScreenViewController }.first { $0.screenId == "home" })
        let items = Array(try XCTUnwrap(home.navigationItem.rightBarButtonItems).reversed())
        items[1].primaryAction?.performWithSender(nil, target: nil)
        for _ in 0..<20 where !(home.navigationController?.viewControllers.contains { ($0 as? ScreenViewController)?.screenId == "sheet" } ?? false) {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let stack = home.navigationController?.viewControllers.compactMap { ($0 as? ScreenViewController)?.screenId } ?? []
        XCTAssertEqual(stack, ["home", "sheet"], "the screen opens")
        window.layoutIfNeeded()
        try await settle()
        let save = try XCTUnwrap(views(window).first { $0.accessibilityIdentifier == "save" }, "the bottom bar's component renders")
        XCTAssertEqual(save.alpha, 0.35, accuracy: 0.001)
    }

    func testScreenDecodeFailureIsDescribedWithItsPath() {
        let error = DecodingError.typeMismatch(Double.self, .init(
            codingPath: [AnyCodingKeyForTest("content"), AnyCodingKeyForTest("style"), AnyCodingKeyForTest("alpha")],
            debugDescription: "Expected to decode Double but found a string instead."))
        let text = App8.Error.screenDecodeFailed(id: "detail", underlying: error).localizedDescription
        XCTAssertTrue(text.contains("'detail'"), text)
        XCTAssertTrue(text.contains("at content.style.alpha"), text)
    }
}

private struct AnyCodingKeyForTest: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
