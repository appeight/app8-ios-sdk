import XCTest
@testable import App8Engine

private final class WrapStub: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data { Data() }
}

private extension UIView {
    func wrapAll<T: UIView>(_ t: T.Type) -> [T] {
        var out: [T] = []
        if let s = self as? T { out.append(s) }
        for sub in subviews { out.append(contentsOf: sub.wrapAll(t)) }
        return out
    }
}

@MainActor
final class LabelWrapLayoutTests: XCTestCase {

    /// Regression: a multi-line (`numberOfLines: 0`) label inside CENTER-aligned
    /// stacks — the layout the seed "hello world" screen uses — must wrap within
    /// the device width instead of sizing to its full single-line width and
    /// overflowing the screen (which renders as one truncated line). Center
    /// alignment doesn't pin a child's cross-axis width, so the label could grow
    /// past its container; `CLabelView` must clamp the wrap width to the bounded
    /// ancestor. See `CLabelView.availableWrapWidth()`.
    func testMultilineLabelWrapsWithinCenterAlignedContainer() async throws {
        // Long enough that it cannot fit on one line at ~329pt (393 − 2×32).
        let subtitle = "Build with the agent, upload your assets, or scan an existing app."
        let json = """
        {
          "type": "screen", "id": "s",
          "content": {
            "style": { "material": [ { "id": "bg", "type": "fill", "content": { "solid": "#000000" } } ] },
            "children": [
              {
                "id": "bottom", "type": "stackView",
                "content": {
                  "properties": { "axis": "vertical", "spacing": 28, "alignment": "center" },
                  "layout": { "constraints": [
                    { "type": "centerX", "target": "superview" },
                    { "type": "leading", "target": "superview", "constant": 32 },
                    { "type": "trailing", "target": "superview", "constant": -32 },
                    { "type": "bottom", "target": "safeArea", "constant": -40 }
                  ] },
                  "children": [
                    {
                      "id": "text", "type": "stackView",
                      "content": {
                        "properties": { "axis": "vertical", "spacing": 10, "alignment": "center" },
                        "children": [
                          {
                            "id": "seedSubtitle", "type": "label",
                            "content": {
                              "properties": { "text": "\(subtitle)" },
                              "style": { "text": { "fontSize": 15, "fontWeight": "regular", "color": "#C5CAD3", "alignment": 1, "numberOfLines": 0 } }
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

        let deviceWidth: CGFloat = 393
        let service = App8Service(publicDataSource: WrapStub(), context: App8Context())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: deviceWidth, height: 852))
        window.makeKeyAndVisible()

        let component = try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: json.data(using: .utf8)!)
        let vc = await service.renderScreen(component, screenId: "s", params: nil)
        window.rootViewController = vc
        vc.view.frame = window.bounds
        try await Task.sleep(nanoseconds: 600_000_000)
        window.layoutIfNeeded()
        vc.view.layoutIfNeeded()

        let labelViews = vc.view.wrapAll(CLabelView.self)
        let subtitleView = try XCTUnwrap(
            labelViews.first { v in
                let l = v.intrinsicContentSource as? UILabel
                return (l?.text == subtitle) || (l?.attributedText?.string == subtitle)
            },
            "seed subtitle label should be in the rendered tree"
        )
        let label = try XCTUnwrap(subtitleView.intrinsicContentSource as? UILabel)

        // 1) It must not overflow the device — a one-line truncated render would
        //    size the label to its full single-line width (well over 329pt).
        XCTAssertLessThanOrEqual(
            label.bounds.width, deviceWidth,
            "subtitle must wrap within the screen, not overflow on a single line (got \(label.bounds.width)pt)"
        )

        // 2) It must actually wrap to at least two lines.
        let lineHeight = label.font.lineHeight
        XCTAssertGreaterThanOrEqual(
            label.bounds.height, lineHeight * 1.5,
            "subtitle should wrap to ≥2 lines (height \(label.bounds.height)pt vs line \(lineHeight)pt)"
        )

        // 3) preferredMaxLayoutWidth must have settled to the bounded width, not
        //    the full display width (the old `UIScreen.main` seed / overflow bug).
        XCTAssertLessThanOrEqual(
            label.preferredMaxLayoutWidth, deviceWidth,
            "preferredMaxLayoutWidth should clamp to the bounded ancestor"
        )
    }
}
