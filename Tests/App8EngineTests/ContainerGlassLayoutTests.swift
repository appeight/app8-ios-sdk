import XCTest
@testable import App8Engine

private final class DiagStub: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data { Data() }
}

private extension UIView {
    func diagAll<T: UIView>(_ t: T.Type) -> [T] {
        var out: [T] = []
        if let s = self as? T { out.append(s) }
        for sub in subviews { out.append(contentsOf: sub.diagAll(t)) }
        return out
    }
}

@MainActor
final class ContainerGlassLayoutTests: XCTestCase {

    func testContainerGlassSizesHostedContent() async throws {
        let json = """
        {
          "type": "screen", "id": "s",
          "content": {
            "variables": {
              "dragY": { "type": "number", "initialValue": 100 },
              "brightness": { "type": "number", "computed": "{{ max(0, min(100, (200 - dragY) / 2)) }}" }
            },
            "children": [
            {
          "id": "capsule", "type": "view",
          "content": {
            "gestures": { "pan": { "locationY": "dragY" } },
            "style": { "material": [
              { "id": "g", "type": "visualEffect", "content": { "glass": "normal", "container": true } },
              { "id": "c", "type": "corner", "content": { "radius": "capsule" } }
            ] },
            "layout": { "constraints": [
              { "type": "centerX", "target": "superview" },
              { "type": "centerY", "target": "superview" },
              { "type": "width", "constant": 90 },
              { "type": "height", "constant": 200 }
            ] },
            "children": [
              { "id": "fill", "type": "view", "content": {
                "style": { "material": [ { "id": "f", "type": "fill", "content": { "solid": "#EAF4FFE6" } } ] },
                "layout": { "height": "{{ brightness * 2 }}", "constraints": [
                  { "type": "leading", "target": "superview" },
                  { "type": "trailing", "target": "superview" },
                  { "type": "bottom", "target": "superview" }
                ] }
              }},
              { "id": "sun", "type": "icon", "content": {
                "properties": { "type": "symbol", "name": "sun.max.fill", "tintColor": "#FFC400" },
                "style": { "symbolFontSize": 28 },
                "layout": { "constraints": [
                  { "type": "centerX", "target": "superview" },
                  { "type": "bottom", "target": "superview", "constant": -24 }
                ] }
              }}
            ]
          }
        }
            ]
          }
        }
        """
        let service = App8Service(publicDataSource: DiagStub(), context: App8Context())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.makeKeyAndVisible()

        let component = try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: json.data(using: .utf8)!)
        let vc = await service.renderScreen(component, screenId: "s", params: nil)
        window.rootViewController = vc
        vc.view.frame = window.bounds
        // Let async style/material sinks fire, then lay out.
        try await Task.sleep(nanoseconds: 600_000_000)
        window.layoutIfNeeded()
        vc.view.layoutIfNeeded()

        // Container-glass on iOS 26: the glass effect view must size to the
        // capsule (regression — it previously stayed 0×0 and collapsed all
        // hosted content), and the reparented fill must fill the capsule width.
        if #available(iOS 26.0, *) {
            let effects = vc.view.diagAll(UIVisualEffectView.self)
            let glass = try XCTUnwrap(effects.first { $0.frame.width > 0 || $0.frame.height > 0 },
                                      "glass effect view should be sized, not 0×0")
            XCTAssertEqual(glass.bounds.size, CGSize(width: 90, height: 200))
            // Fill + icon are hosted inside the glass content view.
            XCTAssertTrue(glass.contentView.diagAll(CIconView.self).count == 1,
                          "icon should be hosted inside the glass contentView")
            let fills = glass.contentView.diagAll(CView.self)
            let fill = try XCTUnwrap(fills.first, "fill should be hosted inside the glass contentView")
            XCTAssertEqual(fill.bounds.width, 90, "fill should span the capsule width")
            XCTAssertEqual(fill.bounds.height, 100, accuracy: 0.5, "fill height = brightness(50) * 2")
        }
    }
}
