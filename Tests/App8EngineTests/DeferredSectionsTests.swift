//
//  DeferredSectionsTests.swift
//  App8EngineTests
//

import XCTest
import UIKit
@testable import App8Engine

/// DSL "Deferred sections": `defer` on a stack child.
@MainActor
final class DeferredSectionsTests: XCTestCase {

    private var service: App8Service!
    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        service = App8Service(publicDataSource: DeferStubDataSource(), context: App8Context())
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.makeKeyAndVisible()
    }

    override func tearDown() {
        window = nil
        service = nil
        super.tearDown()
    }

    private let json = """
    {
      "type": "stackView", "id": "stack",
      "content": {
        "properties": { "axis": "vertical", "spacing": 8 },
        "layout": { "constraints": [ { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" } ] },
        "children": [
          { "type": "label", "id": "first", "content": { "properties": { "text": "Section A" } } },
          { "type": "view", "id": "later", "defer": { "placeholder": "shimmer", "estimatedHeight": 120 },
            "content": { "layout": { "height": 80 }, "children": [
              { "type": "stackView", "id": "inner", "content": { "properties": { "axis": "vertical" },
                "layout": { "constraints": [ { "type": "edges", "target": "superview" } ] },
                "children": [
                  { "type": "label", "id": "nested", "defer": { "estimatedHeight": 10 }, "content": { "properties": { "text": "Section B" } } }
                ] } }
            ] } },
          { "type": "label", "id": "last", "defer": { "placeholder": "none", "estimatedHeight": 30 }, "content": { "properties": { "text": "Section C" } } }
        ]
      }
    }
    """

    private func build(inScreen: Bool) throws -> UIView {
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(json.utf8))
        let root = UIView(frame: .zero)
        if inScreen {
            _ = DeferredBuildQueue.shared.buildingScreen { service.renderComponent(component, superview: root) }
        } else {
            _ = service.renderComponent(component, superview: root)
        }
        return root
    }

    private func texts(in view: UIView) -> [String] {
        ((view as? UILabel)?.text.map { [$0] } ?? []) + view.subviews.flatMap(texts(in:))
    }

    private func placeholders(in view: UIView) -> [DeferredPlaceholderView] {
        ((view as? DeferredPlaceholderView).map { [$0] } ?? []) + view.subviews.flatMap(placeholders(in:))
    }

    func testDecodesDefer() throws {
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(json.utf8))
        let stack: DSL.Model.Component.ConcreteEntity<DSL.Model.Component.StackView.C> = try XCTUnwrap(component.asConcreteEntity())
        let children = stack.content.children
        XCTAssertNil(children[0].deferral)
        XCTAssertEqual(children[1].deferral, DSL.Model.Component.Any.Deferral(placeholder: .shimmer, estimatedHeight: 120, estimatedWidth: nil))
        XCTAssertEqual(children[2].deferral?.placeholder, DSL.Model.Component.Any.Deferral.Placeholder.none)
    }

    func testScreenBuildShowsPlaceholdersThenBuildsInOrderOnceInWindow() throws {
        let root = try build(inScreen: true)
        XCTAssertEqual(texts(in: root), ["Section A"], "deferred children are not built with the screen")
        XCTAssertEqual(placeholders(in: root).count, 2)

        // Not in a window yet: nothing is built.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(texts(in: root), ["Section A"])

        window.addSubview(root)
        root.frame = window.bounds
        root.layoutIfNeeded()
        let deadline = Date().addingTimeInterval(2)
        while texts(in: root).count < 3, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(texts(in: root), ["Section A", "Section B", "Section C"], "built in order; nested defer ignored")
        XCTAssertTrue(placeholders(in: root).isEmpty)
    }

    func testOutsideScreenBuildEverythingAtOnce() throws {
        let root = try build(inScreen: false)
        XCTAssertEqual(texts(in: root), ["Section A", "Section B", "Section C"])
        XCTAssertTrue(placeholders(in: root).isEmpty)
    }
}
private final class DeferStubDataSource: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data { Data() }
}
