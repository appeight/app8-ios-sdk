//
//  FirstRenderWrapTests.swift
//  App8EngineTests
//

import XCTest
import UIKit
@testable import App8Engine

/// A screen is built before it has a size (pushed right after `renderScreen`).
/// Multi-line labels whose text is set during the build must still wrap at the
/// width they get once laid out.
@MainActor
final class FirstRenderWrapTests: XCTestCase {

    func testWrappingLabelBuiltBeforeSizeWrapsAtLaidOutWidth() throws {
        let service = App8Service(publicDataSource: WrapStubDataSource(), context: App8Context())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.makeKeyAndVisible()
        let json = """
        {
          "type": "scrollView", "id": "scroll",
          "content": {
            "layout": { "constraints": [ { "type": "edges", "target": "superview" } ] },
            "children": [
              { "type": "stackView", "id": "stack",
                "content": {
                  "properties": { "axis": "vertical", "spacing": 8 },
                  "layout": { "constraints": [ { "type": "edges", "target": "superview" }, { "type": "width", "target": "superview" } ] },
                  "children": [
                    { "type": "view", "id": "row",
                      "content": {
                        "children": [
                          { "type": "label", "id": "title",
                            "content": {
                              "properties": { "text": "Sample Item A with a title long enough to wrap", "numberOfLines": 0 },
                              "style": { "text": { "fontSize": 22 } },
                              "layout": { "constraints": [ { "type": "top", "target": "superview" }, { "type": "bottom", "target": "superview" }, { "type": "leading", "target": "superview", "constant": 16 }, { "type": "trailing", "target": "superview", "constant": -60 } ] }
                            } }
                        ]
                      } }
                  ]
                } }
            ]
          }
        }
        """
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: Data(json.utf8))
        let root = UIView(frame: .zero)
        service.renderComponent(component, superview: root)
        window.addSubview(root)
        root.frame = window.bounds
        for _ in 0..<4 { root.setNeedsLayout(); root.layoutIfNeeded() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        for _ in 0..<4 { root.layoutIfNeeded() }
        let label = try XCTUnwrap(allLabels(in: root).first { $0.text?.hasPrefix("Sample Item A") == true || $0.attributedText?.string.hasPrefix("Sample Item A") == true })
        XCTAssertLessThan(label.bounds.height, 100, "two or three lines, not one word per line")
        XCTAssertGreaterThan(label.bounds.width, 200)
    }

    private func allLabels(in view: UIView) -> [UILabel] {
        ((view as? UILabel).map { [$0] } ?? []) + view.subviews.flatMap(allLabels(in:))
    }
}
private final class WrapStubDataSource: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data { Data() }
}
