import XCTest
@testable import App8Engine

private final class BadgeStub: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data { Data() }
}

private extension UIView {
    func allOf<T: UIView>(_ t: T.Type) -> [T] {
        var out: [T] = []
        if let s = self as? T { out.append(s) }
        for sub in subviews { out.append(contentsOf: sub.allOf(t)) }
        return out
    }
}

@MainActor
final class BadgeCollapseReproTests: XCTestCase {

    // Reproduces PlanCard "BEST VALUE" badge: a label with no numberOfLines
    // (defaults to 0) inside a CONTENT-HUGGING container (leading+top only, no
    // width/trailing), inside a wide card. The badge view sizes to the label,
    // so it is NOT a wrap boundary — but availableWrapWidth() reads its narrow
    // bounds and collapses the label to ~one char per line.
    func testBadgeLabelStaysSingleLine() async throws {
        let badge = "BEST VALUE"
        let json = """
        {
          "type": "screen", "id": "s",
          "content": {
            "children": [
              {
                "id": "card", "type": "view",
                "content": {
                  "style": { "material": [ { "id": "f", "type": "fill", "content": { "solid": "#222222" } } ] },
                  "layout": { "constraints": [
                    { "type": "leading", "target": "superview", "constant": 20 },
                    { "type": "trailing", "target": "superview", "constant": -20 },
                    { "type": "top", "target": "superview", "constant": 100 },
                    { "type": "height", "constant": 200 }
                  ] },
                  "children": [
                    {
                      "id": "badge", "type": "view",
                      "content": {
                        "style": { "material": [ { "id": "bf", "type": "fill", "content": { "solid": "#FFFFFF1F" } } ] },
                        "layout": { "constraints": [
                          { "type": "leading", "target": "superview", "constant": 21 },
                          { "type": "top", "target": "superview", "constant": 22 }
                        ] },
                        "children": [
                          {
                            "id": "badgeLabel", "type": "label",
                            "content": {
                              "properties": { "text": "\(badge)" },
                              "style": { "text": { "fontSize": 15, "alignment": 0 } },
                              "layout": { "constraints": [
                                { "type": "leading", "target": "superview", "constant": 12 },
                                { "type": "trailing", "target": "superview", "constant": -12 },
                                { "type": "top", "target": "superview", "constant": 6 },
                                { "type": "bottom", "target": "superview", "constant": -6 }
                              ] }
                            }
                          }
                        ]
                      }
                    }
                  ]
                }
              }
            ]
          }
        }
        """

        let service = App8Service(publicDataSource: BadgeStub(), context: App8Context())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.makeKeyAndVisible()
        let component = try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: json.data(using: .utf8)!)
        let vc = await service.renderScreen(component, screenId: "s", params: nil)
        window.rootViewController = vc
        vc.view.frame = window.bounds
        try await Task.sleep(nanoseconds: 600_000_000)
        window.layoutIfNeeded()
        vc.view.layoutIfNeeded()

        let labelView = try XCTUnwrap(vc.view.allOf(CLabelView.self).first { ($0.intrinsicContentSource as? UILabel)?.text == badge })
        let label = try XCTUnwrap(labelView.intrinsicContentSource as? UILabel)
        let lineH = label.font.lineHeight
        let lines = label.bounds.height / lineH
        print("BADGE w=\(label.bounds.width) h=\(label.bounds.height) lineH=\(lineH) lines~=\(lines) pMLW=\(label.preferredMaxLayoutWidth)")

        // "BEST VALUE" at 15pt is ~80pt wide and must stay on ONE line.
        XCTAssertLessThanOrEqual(lines, 1.5, "badge collapsed to \(lines) lines (one-char-per-line bug)")
        XCTAssertGreaterThan(label.bounds.width, 50, "badge label width collapsed to \(label.bounds.width)pt")
    }
}
