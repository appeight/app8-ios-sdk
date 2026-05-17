//
//  CTableViewScreenshotTests.swift
//  App8EngineTests
//
//  Structural render tests for the tableView DSL component.
//  Visual screenshot tests live in App8Examples/App8ExamplesUITests (TableViewDemo).
//

import XCTest
@testable import App8Engine

// MARK: - Minimal DataSource

private final class StubDataSource: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data { Data() }
}

// MARK: - Helper to locate UITableView inside CTableViewView

private extension UIView {
    func firstDescendant<T: UIView>(ofType type: T.Type) -> T? {
        if let match = self as? T { return match }
        for sub in subviews {
            if let found = sub.firstDescendant(ofType: type) { return found }
        }
        return nil
    }

    func allDescendants<T: UIView>(ofType type: T.Type) -> [T] {
        var results: [T] = []
        if let match = self as? T { results.append(match) }
        for sub in subviews { results += sub.allDescendants(ofType: type) }
        return results
    }
}

// MARK: - JSON fixtures

private let threeSection390JSON = """
{
    "type": "tableView",
    "id": "tv",
    "content": {
        "properties": { "tableStyle": "insetGrouped", "separatorInset": 64, "showsIndicator": false },
        "style": {},
        "layout": {
            "constraints": [
                { "type": "top",      "target": "superview" },
                { "type": "leading",  "target": "superview" },
                { "type": "trailing", "target": "superview" },
                { "type": "bottom",   "target": "superview" }
            ]
        },
        "sections": [
            {
                "id": "profileSection",
                "rows": [
                    {
                        "id": "profileRow",
                        "height": 72,
                        "children": [
                            {
                                "id": "profileName",
                                "type": "label",
                                "content": {
                                    "properties": { "text": "Alex Johnson" },
                                    "style": { "text": { "fontSize": 17, "fontWeight": "semibold", "color": "#FFFFFF" } },
                                    "layout": {
                                        "constraints": [
                                            { "type": "leading", "target": "superview", "constant": 16 },
                                            { "type": "centerY", "target": "superview", "constant": -9 }
                                        ]
                                    }
                                }
                            },
                            {
                                "id": "profileSubtitle",
                                "type": "label",
                                "content": {
                                    "properties": { "text": "View profile" },
                                    "style": { "text": { "fontSize": 14, "color": "#8E8E93" } },
                                    "layout": {
                                        "constraints": [
                                            { "type": "leading", "target": "superview", "constant": 16 },
                                            { "type": "centerY", "target": "superview", "constant": 11 }
                                        ]
                                    }
                                }
                            },
                            {
                                "id": "profileChevron",
                                "type": "icon",
                                "content": {
                                    "properties": { "type": "symbol", "name": "chevron.right" },
                                    "style": { "symbolFontSize": 13, "color": "#8E8E93" },
                                    "layout": {
                                        "constraints": [
                                            { "type": "trailing", "target": "superview", "constant": -16 },
                                            { "type": "centerY",  "target": "superview" }
                                        ]
                                    }
                                }
                            }
                        ]
                    }
                ]
            },
            {
                "id": "preferencesSection",
                "header": "Preferences",
                "rows": [
                    {
                        "id": "notificationsRow",
                        "height": 54,
                        "children": [
                            {
                                "id": "notifLabel",
                                "type": "label",
                                "content": {
                                    "properties": { "text": "Notifications" },
                                    "style": { "text": { "fontSize": 17, "color": "#FFFFFF" } },
                                    "layout": {
                                        "constraints": [
                                            { "type": "leading", "target": "superview", "constant": 16 },
                                            { "type": "centerY", "target": "superview" }
                                        ]
                                    }
                                }
                            }
                        ]
                    },
                    {
                        "id": "appearanceRow",
                        "height": 54,
                        "children": [
                            {
                                "id": "appearLabel",
                                "type": "label",
                                "content": {
                                    "properties": { "text": "Appearance" },
                                    "style": { "text": { "fontSize": 17, "color": "#FFFFFF" } },
                                    "layout": {
                                        "constraints": [
                                            { "type": "leading", "target": "superview", "constant": 16 },
                                            { "type": "centerY", "target": "superview" }
                                        ]
                                    }
                                }
                            }
                        ]
                    }
                ]
            },
            {
                "id": "footerSection",
                "rows": [
                    {
                        "id": "footerRow",
                        "height": 110,
                        "clearBackground": true,
                        "children": [
                            {
                                "id": "footerLogo",
                                "type": "label",
                                "content": {
                                    "properties": { "text": "Footer⁺" },
                                    "style": { "text": { "fontSize": 20, "fontWeight": "semibold", "color": "#FFFFFF", "alignment": 1 } },
                                    "layout": {
                                        "constraints": [
                                            { "type": "centerX", "target": "superview" },
                                            { "type": "centerY", "target": "superview", "constant": -18 }
                                        ]
                                    }
                                }
                            },
                            {
                                "id": "footerVersion",
                                "type": "label",
                                "content": {
                                    "properties": { "text": "Version 1.0.0 (1)" },
                                    "style": { "text": { "fontSize": 13, "color": "#8E8E93", "alignment": 1 } },
                                    "layout": {
                                        "constraints": [
                                            { "type": "centerX", "target": "superview" },
                                            { "type": "top", "target": "footerLogo", "attribute": "bottom", "constant": 6 }
                                        ]
                                    }
                                }
                            }
                        ]
                    }
                ]
            }
        ]
    }
}
"""

@MainActor
final class CTableViewScreenshotTests: XCTestCase {

    private var service: App8Service!
    private var window: UIWindow!
    private let renderSize = CGSize(width: 390, height: 844)

    override func setUp() {
        super.setUp()
        service = App8Service(publicDataSource: StubDataSource(), context: App8Context())
        window = UIWindow(frame: CGRect(origin: .zero, size: renderSize))
        window.makeKeyAndVisible()
    }

    override func tearDown() {
        window = nil
        service = nil
        super.tearDown()
    }

    private func render(_ json: String) throws -> (superview: UIView, tableViewView: CTableViewView) {
        let data = json.data(using: .utf8)!
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: data)

        let superview = UIView(frame: CGRect(origin: .zero, size: renderSize))
        superview.backgroundColor = .black
        window.addSubview(superview)

        service.renderComponent(component, superview: superview)
        superview.layoutIfNeeded()

        guard let tv = superview.firstDescendant(ofType: CTableViewView.self) else {
            XCTFail("CTableViewView not found after renderComponent")
            throw RenderError.viewNotFound
        }
        return (superview, tv)
    }

    private enum RenderError: Error { case viewNotFound }

    func testRenderProducesTableViewView() throws {
        let (_, tvView) = try render(threeSection390JSON)
        XCTAssertNotNil(tvView)
    }

    func testRenderedTableViewHasCorrectSectionCount() throws {
        let (_, tvView) = try render(threeSection390JSON)
        let tableView = tvView.firstDescendant(ofType: UITableView.self)
        XCTAssertNotNil(tableView)
        XCTAssertEqual(tableView?.numberOfSections, 3)
    }

    func testRenderedTableViewProfileSectionHasOneRow() throws {
        let (_, tvView) = try render(threeSection390JSON)
        let tableView = tvView.firstDescendant(ofType: UITableView.self)
        XCTAssertEqual(tableView?.numberOfRows(inSection: 0), 1, "Profile section should have 1 row")
    }

    func testRenderedTableViewPreferencesSectionHasTwoRows() throws {
        let (_, tvView) = try render(threeSection390JSON)
        let tableView = tvView.firstDescendant(ofType: UITableView.self)
        XCTAssertEqual(tableView?.numberOfRows(inSection: 1), 2, "Preferences section should have 2 rows")
    }

    func testRenderedTableViewFooterSectionHasOneRow() throws {
        let (_, tvView) = try render(threeSection390JSON)
        let tableView = tvView.firstDescendant(ofType: UITableView.self)
        XCTAssertEqual(tableView?.numberOfRows(inSection: 2), 1, "Footer section should have 1 row")
    }

    func testEmptyTableViewRenders() throws {
        let json = """
        {
            "type": "tableView", "id": "empty-tv",
            "content": {
                "properties": {},
                "style": {},
                "layout": {
                    "constraints": [
                        { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
                        { "type": "trailing", "target": "superview" }, { "type": "bottom", "target": "superview" }
                    ]
                },
                "sections": []
            }
        }
        """
        let (_, tvView) = try render(json)
        let tableView = tvView.firstDescendant(ofType: UITableView.self)
        XCTAssertEqual(tableView?.numberOfSections, 0)
    }

    func testPlainStyleTableViewRenders() throws {
        let json = """
        {
            "type": "tableView", "id": "plain-tv",
            "content": {
                "properties": { "tableStyle": "plain" },
                "style": {},
                "layout": {
                    "constraints": [
                        { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
                        { "type": "trailing", "target": "superview" }, { "type": "bottom", "target": "superview" }
                    ]
                },
                "sections": [
                    { "id": "s", "header": "Plain Section", "rows": [
                        { "id": "r", "height": 50, "children": [] }
                    ]}
                ]
            }
        }
        """
        let (_, tvView) = try render(json)
        let tableView = tvView.firstDescendant(ofType: UITableView.self)
        XCTAssertEqual(tableView?.numberOfSections, 1)
        XCTAssertEqual(tableView?.numberOfRows(inSection: 0), 1)
    }

    func testSingleSignOutRowWithoutIconRenders() throws {
        let json = """
        {
            "type": "tableView", "id": "signout-tv",
            "content": {
                "properties": { "tableStyle": "insetGrouped" },
                "style": {},
                "layout": {
                    "constraints": [
                        { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
                        { "type": "trailing", "target": "superview" }, { "type": "bottom", "target": "superview" }
                    ]
                },
                "sections": [
                    { "id": "signOut", "rows": [
                        {
                            "id": "signOutRow", "height": 54,
                            "children": [
                                {
                                    "id": "signOutLabel", "type": "label",
                                    "content": {
                                        "properties": { "text": "Sign Out" },
                                        "style": { "text": { "fontSize": 17, "color": "#FF3B30", "alignment": 1 } },
                                        "layout": {
                                            "constraints": [
                                                { "type": "centerX", "target": "superview" },
                                                { "type": "centerY", "target": "superview" }
                                            ]
                                        }
                                    }
                                }
                            ]
                        }
                    ]}
                ]
            }
        }
        """
        let (_, tvView) = try render(json)
        let tableView = tvView.firstDescendant(ofType: UITableView.self)
        XCTAssertEqual(tableView?.numberOfRows(inSection: 0), 1)
    }

}
