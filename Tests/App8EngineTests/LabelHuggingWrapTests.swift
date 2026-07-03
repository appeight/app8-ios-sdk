import XCTest
@testable import App8Engine

private final class HugStub: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data { Data() }
}

private extension UIView {
    func allLabels() -> [CLabelView] {
        var out: [CLabelView] = []
        if let s = self as? CLabelView { out.append(s) }
        for sub in subviews { out.append(contentsOf: sub.allLabels()) }
        return out
    }
}

/// A label must HUG its natural width when nothing content-independent constrains
/// it narrower — it must not be clamped to a content-driven ancestor (a stack that
/// hugs its children, or a horizontal scroll's content whose width IS the content).
/// Doing so closes a collapse feedback loop that renders text one glyph per line.
///
/// These guard the general class of the creator-carousel regression: the fix is in
/// `CLabelView.hasContentIndependentWidth`, which must reject `UIStackView`
/// sibling-chaining and `UIScrollView.contentLayoutGuide` edge pins.
@MainActor
final class LabelHuggingWrapTests: XCTestCase {

    private func render(_ json: String, width: CGFloat = 393) async throws -> UIViewController {
        let service = App8Service(publicDataSource: HugStub(), context: App8Context())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 852))
        window.makeKeyAndVisible()
        let component = try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: json.data(using: .utf8)!)
        let vc = await service.renderScreen(component, screenId: "s", params: nil)
        window.rootViewController = vc
        vc.view.frame = window.bounds
        try await Task.sleep(nanoseconds: 700_000_000)
        window.layoutIfNeeded()
        vc.view.layoutIfNeeded()
        objc_setAssociatedObject(vc, &Self.windowKey, window, .OBJC_ASSOCIATION_RETAIN)
        return vc
    }
    private static var windowKey: UInt8 = 0

    private func label(_ vc: UIViewController, text: String) throws -> UILabel {
        let v = try XCTUnwrap(
            vc.view.allLabels().first { ($0.intrinsicContentSource as? UILabel)?.text == text },
            "label \"\(text)\" should be in the tree"
        )
        return try XCTUnwrap(v.intrinsicContentSource as? UILabel)
    }

    /// The creator carousel: a horizontal scrollView → horizontal fill stack →
    /// vertical center cards, each `[avatar, caption[nameRow[name, ✔]]]`. The name
    /// must render on ONE line at its natural width, driving the card width — not
    /// collapse to one character per line.
    func testHorizontalCarouselNameHugsNotCollapse() async throws {
        func card(_ name: String) -> String {
            """
            { "id": "card_\(name)", "type": "stackView", "content": {
              "properties": { "axis": "vertical", "alignment": "center", "spacing": 8 },
              "children": [
                { "id": "avatar_\(name)", "type": "view", "content": {
                  "layout": { "constraints": [
                    { "type": "height", "constant": 100, "priority": "defaultLow" },
                    { "type": "height", "op": "<=", "constant": 100 },
                    { "type": "height", "op": ">=", "constant": 50 },
                    { "type": "width", "attribute": "height", "target": "self", "multiplier": 1 } ] },
                  "style": { "material": [ { "id": "a", "type": "fill", "content": { "solid": "#ccc" } } ] } } },
                { "id": "caption_\(name)", "type": "stackView", "content": {
                  "properties": { "axis": "vertical", "alignment": "center", "spacing": 4 },
                  "children": [
                    { "id": "nameRow_\(name)", "type": "stackView", "content": {
                      "properties": { "axis": "horizontal", "alignment": "center", "spacing": 2 },
                      "children": [
                        { "id": "name_\(name)", "type": "label", "content": {
                          "properties": { "text": "\(name)" },
                          "style": { "text": { "fontSize": 15, "fontWeight": "bold", "color": "#000", "numberOfLines": 0 } } } },
                        { "id": "chk_\(name)", "type": "icon", "content": {
                          "layout": { "height": 16, "width": 16 },
                          "properties": { "type": "symbol", "name": "checkmark.seal.fill" },
                          "style": { "color": "#0057FF", "symbolFontSize": 14 } } } ] } } ] } } ] } }
            """
        }
        let cards = ["Rusya", "kateryna", "Lola"].map(card).joined(separator: ",")
        let json = """
        { "type": "screen", "id": "s", "content": { "children": [
          { "id": "carousel", "type": "scrollView", "content": {
            "properties": { "direction": "horizontal", "showsIndicator": false },
            "layout": { "constraints": [
              { "type": "height", "constant": 160, "priority": "defaultLow" },
              { "type": "top", "target": "superview", "constant": 100 },
              { "type": "leading", "target": "superview" },
              { "type": "trailing", "target": "superview" } ] },
            "children": [
              { "id": "creatorRow", "type": "stackView", "content": {
                "properties": { "axis": "horizontal", "alignment": "fill", "spacing": 35 },
                "layout": { "constraints": [
                  { "type": "top", "target": "superview" }, { "type": "bottom", "target": "superview" },
                  { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" } ] },
                "children": [ \(cards) ] } } ] } } ] } }
        """
        let vc = try await render(json)
        let name = try label(vc, text: "Rusya")
        // "Rusya" at 15pt bold is ~45pt single-line; a per-glyph collapse falls
        // near a single character (~17pt) and grows tall.
        XCTAssertGreaterThan(name.bounds.width, 40,
            "name collapsed — bounds width \(name.bounds.width)pt is near a single glyph")
        XCTAssertLessThan(name.bounds.height, name.font.lineHeight * 1.5,
            "name should be a single line, got height \(name.bounds.height)pt")
    }

    /// A vertical carousel keeps its width tied to the scroll's FRAME (via
    /// `width == frameLayoutGuide.width`), so a genuinely long multi-line label
    /// there must still WRAP within the frame — the fix must not turn every scroll
    /// into "never wrap".
    func testVerticalScrollLongLabelStillWraps() async throws {
        let long = "Everything is handled securely by Stripe so your bank details never touch our servers."
        let json = """
        { "type": "screen", "id": "s", "content": { "children": [
          { "id": "vscroll", "type": "scrollView", "content": {
            "properties": { "direction": "vertical" },
            "layout": { "constraints": [
              { "type": "top", "target": "superview" }, { "type": "bottom", "target": "superview" },
              { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" } ] },
            "children": [
              { "id": "col", "type": "stackView", "content": {
                "properties": { "axis": "vertical", "alignment": "center", "spacing": 10 },
                "layout": { "constraints": [
                  { "type": "top", "target": "superview" }, { "type": "bottom", "target": "superview" },
                  { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" } ] },
                "children": [
                  { "id": "body", "type": "label", "content": {
                    "properties": { "text": "\(long)" },
                    "style": { "text": { "fontSize": 15, "color": "#000", "numberOfLines": 0 } } } } ] } } ] } } ] } }
        """
        let vc = try await render(json)
        let body = try label(vc, text: long)
        XCTAssertLessThanOrEqual(body.bounds.width, 393,
            "long label must wrap within the scroll frame, not overflow (\(body.bounds.width)pt)")
        XCTAssertGreaterThanOrEqual(body.bounds.height, body.font.lineHeight * 1.5,
            "long label should wrap to ≥2 lines (height \(body.bounds.height)pt)")
    }
}
