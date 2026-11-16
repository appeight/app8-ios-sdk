import XCTest
@testable import App8Engine

private final class ShadowFillStub: App8DataSource, @unchecked Sendable {
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

/// A material whose shadow is listed after a translucent fill (corner, fill,
/// shadow) must show the fill: the shadow is cast behind the shape and never
/// paints the shape in the shadow color. Before the fix the non-hollow shadow
/// layer had an opaque `backgroundColor` of the shadow color and sat above the
/// fill, so a white capsule with a soft black shadow rendered solid black.
@MainActor
final class MaterialShadowFillTests: XCTestCase {

    private func capsuleJSON(fill: String, shadowFirst: Bool) -> String {
        let fillLayer = ##"{ "id": "f", "type": "fill", "content": { "solid": "\##(fill)" } }"##
        let shadowLayer = ##"{ "id": "s", "type": "shadow", "content": { "layers": [ { "color": "#000000", "opacity": 0.08, "radius": 10, "offset": { "x": 0, "y": 4 } } ] } }"##
        let corner = ##"{ "id": "c", "type": "corner", "content": { "radius": "capsule" } }"##
        let layers = shadowFirst ? [corner, shadowLayer, fillLayer] : [corner, fillLayer, shadowLayer]
        return """
        {
          "type": "screen", "id": "s",
          "content": {
            "style": { "material": [ { "id": "bg", "type": "fill", "content": { "solid": "#808080" } } ] },
            "children": [
              {
                "id": "capsule", "type": "view",
                "content": {
                  "style": { "material": [ \(layers.joined(separator: ", ")) ] },
                  "layout": { "constraints": [
                    { "type": "centerX", "target": "superview" },
                    { "type": "top", "target": "superview", "constant": 200 }
                  ] },
                  "children": [
                    {
                      "id": "capsuleLabel", "type": "label",
                      "content": {
                        "properties": { "text": "Label" },
                        "style": { "text": { "fontSize": 15, "color": "#1A1A1A" } },
                        "layout": { "constraints": [
                          { "type": "leading", "target": "superview", "constant": 40 },
                          { "type": "trailing", "target": "superview", "constant": -40 },
                          { "type": "top", "target": "superview", "constant": 14 },
                          { "type": "bottom", "target": "superview", "constant": -14 }
                        ] }
                      }
                    }
                  ]
                }
              }
            ]
          }
        }
        """
    }

    private func render(_ json: String) async throws -> (root: UIView, capsule: UIView) {
        let service = App8Service(publicDataSource: ShadowFillStub(), context: App8Context())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.makeKeyAndVisible()
        let component = try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: Data(json.utf8))
        let vc = await service.renderScreen(component, screenId: "s", params: nil)
        window.rootViewController = vc
        vc.view.frame = window.bounds
        try await Task.sleep(nanoseconds: 600_000_000)
        window.layoutIfNeeded()
        vc.view.layoutIfNeeded()
        objc_setAssociatedObject(vc.view, "test.window", window, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(vc.view, "test.service", service, .OBJC_ASSOCIATION_RETAIN)
        let capsule = try XCTUnwrap(vc.view.allOf(UIView.self).first { $0.accessibilityIdentifier?.hasSuffix("capsule") == true })
        return (vc.view, capsule)
    }

    /// RGB of `point` (in `view` coordinates) as rendered.
    private func pixel(of view: UIView, at point: CGPoint) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
        let cg = image.cgImage!
        var px = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: -point.x, y: -(CGFloat(cg.height) - point.y - 1), width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (CGFloat(px[0]) / 255, CGFloat(px[1]) / 255, CGFloat(px[2]) / 255)
    }

    private func assertFillShows(shadowFirst: Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let (root, capsule) = try await render(capsuleJSON(fill: "#FFFFFFF2", shadowFirst: shadowFirst))
        XCTAssertGreaterThan(capsule.bounds.width, 40, file: file, line: line)

        // The shadow layer paints nothing itself and sits under the fill.
        let material = try XCTUnwrap(capsule.allOf(MaterialView.self).first, file: file, line: line)
        let sublayers = material.layer.sublayers ?? []
        let shadow = try XCTUnwrap(sublayers.first { $0 is DSL.Model.Style.Shadow.MaterialLayer }, file: file, line: line)
        XCTAssertNil(shadow.backgroundColor, "shadow layer must not paint the shape", file: file, line: line)
        for other in sublayers where !(other is DSL.Model.Style.Shadow.MaterialLayer) {
            XCTAssertLessThan(shadow.zPosition, other.zPosition, "shadow stacks under the fill", file: file, line: line)
        }

        // A point inside the capsule, left of the label text: ~95% white over grey.
        let inside = capsule.convert(CGPoint(x: capsule.bounds.height / 2 + 4, y: 6), to: root)
        let c = pixel(of: root, at: inside)
        XCTAssertGreaterThan(min(c.r, c.g, c.b), 0.9, "capsule should be near white, got \(c)", file: file, line: line)
    }

    func testTranslucentFillWithShadowAfterItRendersFill() async throws {
        try await assertFillShows(shadowFirst: false)
    }

    func testTranslucentFillWithShadowBeforeItRendersFill() async throws {
        try await assertFillShows(shadowFirst: true)
    }
}
