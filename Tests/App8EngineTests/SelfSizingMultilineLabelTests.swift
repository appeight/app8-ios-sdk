import XCTest
@testable import App8Engine

private final class MultilineStub: App8DataSource, @unchecked Sendable {
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

/// A self-sizing row: a 72 pt thumbnail pinned top/leading (`bottom <=`
/// superview) beside a text stack (title + multi-line body) pinned
/// top/leading-to-thumbnail/trailing/bottom. The body wraps to three lines,
/// taller than the thumbnail, so the row must grow to the stack's full height
/// rather than stop at the thumbnail with the body squeezed to one line.
@MainActor
final class SelfSizingMultilineLabelTests: XCTestCase {

    private static let body = "A longer description that needs several lines at this width. It keeps going for a while so it wraps, and then it carries on for one more sentence to be sure."

    private func rowChildren(bottomPriority: String, thumbBottom: Bool) -> String {
        """
        { "id": "thumb", "type": "view", "content": {
            "layout": { "width": 72, "height": 72, "constraints": [
              { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" }\(thumbBottom ? #", { "type": "bottom", "target": "superview", "op": "<=" }"# : "") ] } } },
        { "id": "texts", "type": "stackView", "content": {
            "properties": { "axis": "vertical", "spacing": 0, "alignment": "fill" },
            "layout": { "constraints": [
              { "type": "top", "target": "superview", "constant": 2 },
              { "type": "leading", "target": "thumb", "attribute": "trailing", "constant": 16 },
              { "type": "trailing", "target": "superview" },
              { "type": "bottom", "target": "superview"\(bottomPriority) } ] },
            "children": [
              { "id": "title", "type": "label", "content": { "properties": { "text": "Row title" }, "style": { "text": { "fontSize": 17 } } } },
              { "id": "body", "type": "label", "content": { "properties": { "text": "BODY_TEXT" }, "style": { "text": { "fontSize": 15 } } } }
            ] } }
        """
    }

    private func collectionJSON(layout: String, bottomPriority: String, thumbBottom: Bool) -> String {
        let children = rowChildren(bottomPriority: bottomPriority, thumbBottom: thumbBottom)
            .replacingOccurrences(of: "BODY_TEXT", with: "{{item.t}}")
        return """
        {
          "type": "screen", "id": "s",
          "content": {
            "variables": { "rows": { "type": "array", "initialValue": [ { "t": "\(Self.body)" }, { "t": "\(Self.body)" } ] } },
            "children": [
              { "id": "list", "type": "collection",
                "content": {
                  "properties": { "data": "{{rows}}", "layout": \(layout) },
                  "layout": { "constraints": [
                    { "type": "top", "target": "superview", "constant": 100 },
                    { "type": "leading", "target": "superview", "constant": 20 },
                    { "type": "trailing", "target": "superview", "constant": -20 },
                    { "type": "height", "constant": 600 } ] },
                  "template": { "id": "row", "type": "view", "content": { "children": [ \(children) ] } }
                } }
            ]
          }
        }
        """
    }

    private func tableJSON() -> String {
        let children = rowChildren(bottomPriority: "", thumbBottom: true)
            .replacingOccurrences(of: "BODY_TEXT", with: Self.body)
        return """
        {
          "type": "screen", "id": "s",
          "content": {
            "children": [
              { "id": "table", "type": "tableView",
                "content": {
                  "properties": { "tableStyle": "plain" },
                  "style": {},
                  "layout": { "constraints": [
                    { "type": "top", "target": "superview", "constant": 100 },
                    { "type": "leading", "target": "superview", "constant": 20 },
                    { "type": "trailing", "target": "superview", "constant": -20 },
                    { "type": "height", "constant": 600 } ] },
                  "sections": [ { "id": "sec", "rows": [ { "id": "r0", "children": [ \(children) ] } ] } ]
                } }
            ]
          }
        }
        """
    }

    private struct Measurement { let label: CGFloat; let needed: CGFloat; let row: CGFloat }

    private func render<Cell: UIView>(_ json: String, cell: Cell.Type, contentOf: (Cell) -> UIView) async throws -> Measurement {
        let service = App8Service(publicDataSource: MultilineStub(), context: App8Context())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let component = try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: Data(json.utf8))
        let vc = await service.renderScreen(component, screenId: "s", params: nil)
        window.rootViewController = vc
        vc.view.frame = window.bounds
        try await Task.sleep(nanoseconds: 800_000_000)
        window.layoutIfNeeded()
        let row = try XCTUnwrap(vc.view.allOf(Cell.self).sorted { $0.frame.minY < $1.frame.minY }.first)
        let label = try XCTUnwrap(row.allOf(UILabel.self).first { $0.text?.hasPrefix("A longer") == true })
        let needed = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height
        return Measurement(label: label.bounds.height, needed: needed, row: contentOf(row).bounds.height)
    }

    private func assertFullText(_ m: Measurement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(m.label + 0.5, m.needed, "body label clipped (\(m.label) < \(m.needed))", file: file, line: line)
        XCTAssertGreaterThan(m.row, 72 + 10, "row stopped at the thumbnail height", file: file, line: line)
    }

    private static let vertical = #"{ "type": "vertical", "itemSpacing": 24, "scrollEnabled": false }"#

    func testVerticalCollectionRequiredBottomGrowsRow() async throws {
        let json = collectionJSON(layout: Self.vertical, bottomPriority: "", thumbBottom: true)
        assertFullText(try await render(json, cell: UICollectionViewCell.self) { $0 })
    }

    func testVerticalCollectionHighPriorityBottomGrowsRow() async throws {
        let json = collectionJSON(layout: Self.vertical, bottomPriority: #", "priority": 999"#, thumbBottom: true)
        assertFullText(try await render(json, cell: UICollectionViewCell.self) { $0 })
    }

    func testVerticalCollectionWithoutThumbnailBottomShowsFullText() async throws {
        let json = collectionJSON(layout: Self.vertical, bottomPriority: "", thumbBottom: false)
        let m = try await render(json, cell: UICollectionViewCell.self) { $0 }
        XCTAssertGreaterThanOrEqual(m.label + 0.5, m.needed)
    }

    func testGridCollectionGrowsRow() async throws {
        let grid = #"{ "type": "grid", "columns": 1, "estimatedItemHeight": 60, "lineSpacing": 24 }"#
        let json = collectionJSON(layout: grid, bottomPriority: "", thumbBottom: true)
        assertFullText(try await render(json, cell: UICollectionViewCell.self) { $0 })
    }

    func testTableRowGrows() async throws {
        assertFullText(try await render(tableJSON(), cell: UITableViewCell.self) { $0 })
    }
}
