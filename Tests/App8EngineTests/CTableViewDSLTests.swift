//
//  CTableViewDSLTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

private func decodeTableView(_ json: String) throws -> DSL.Model.Component.ConcreteEntity<DSL.Model.Component.TableView.Content> {
    let data = json.data(using: .utf8)!
    let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: data)
    guard let entity: DSL.Model.Component.ConcreteEntity<DSL.Model.Component.TableView.Content> = component.asConcreteEntity() else {
        XCTFail("Expected ConcreteEntity<TableView.Content>")
        throw TestError.castFailed
    }
    return entity
}

private enum TestError: Error { case castFailed }

/// Minimal valid tableView JSON with no sections.
private func tableViewJSON(
    properties: String = "{}",
    sections: String = "[]",
    extra: String = ""
) -> String {
    """
    {
        "type": "tableView",
        "id": "test-table",
        "content": {
            "properties": \(properties),
            "style": {},
            "layout": {},
            "sections": \(sections)
            \(extra.isEmpty ? "" : ", \(extra)")
        }
    }
    """
}

@MainActor
final class CTableViewDSLTests: XCTestCase {

    // MARK: - CType recognition

    func testTableViewCTypeDecodesAsKey() throws {
        let entity = try decodeTableView(tableViewJSON())
        XCTAssertTrue(entity.type.isOneOf(.tableView))
    }

    func testTableViewDecodesAsConcreteEntity() throws {
        let data = tableViewJSON().data(using: .utf8)!
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: data)
        XCTAssertNotNil(component.asConcreteEntity() as DSL.Model.Component.ConcreteEntity<DSL.Model.Component.TableView.Content>?)
        XCTAssertNil(component.asPointer())
    }

    func testTableViewPointerDecodesWithoutContent() throws {
        let json = """
        { "type": "tableView", "id": "ptr-table" }
        """
        let data = json.data(using: .utf8)!
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: data)
        XCTAssertNotNil(component.asPointer())
        XCTAssertEqual(component.id, "ptr-table")
    }

    // MARK: - Properties

    func testDefaultPropertiesAreNilWhenAbsent() throws {
        let entity = try decodeTableView(tableViewJSON())
        let props = entity.content.properties
        XCTAssertNil(props.tableStyle)
        XCTAssertNil(props.showsIndicator)
        XCTAssertNil(props.separatorInset)
    }

    func testTableStyleInsetGrouped() throws {
        let entity = try decodeTableView(tableViewJSON(properties: #"{ "tableStyle": "insetGrouped" }"#))
        XCTAssertEqual(entity.content.properties.tableStyle, .insetGrouped)
    }

    func testTableStyleGrouped() throws {
        let entity = try decodeTableView(tableViewJSON(properties: #"{ "tableStyle": "grouped" }"#))
        XCTAssertEqual(entity.content.properties.tableStyle, .grouped)
    }

    func testTableStylePlain() throws {
        let entity = try decodeTableView(tableViewJSON(properties: #"{ "tableStyle": "plain" }"#))
        XCTAssertEqual(entity.content.properties.tableStyle, .plain)
    }

    func testTableStyleUnknownFallsBackToInsetGrouped() throws {
        let entity = try decodeTableView(tableViewJSON(properties: #"{ "tableStyle": "carousel" }"#))
        XCTAssertEqual(entity.content.properties.tableStyle, .insetGrouped)
    }

    func testShowsIndicatorDecodes() throws {
        let entity = try decodeTableView(tableViewJSON(properties: #"{ "showsIndicator": false }"#))
        XCTAssertEqual(entity.content.properties.showsIndicator, false)
    }

    func testSeparatorInsetDecodes() throws {
        let entity = try decodeTableView(tableViewJSON(properties: #"{ "separatorInset": 64 }"#))
        XCTAssertEqual(entity.content.properties.separatorInset, 64)
    }

    func testAllPropertiesDecodeTogether() throws {
        let entity = try decodeTableView(tableViewJSON(properties: """
        {
            "tableStyle": "plain",
            "showsIndicator": true,
            "separatorInset": 16
        }
        """))
        let props = entity.content.properties
        XCTAssertEqual(props.tableStyle, .plain)
        XCTAssertEqual(props.showsIndicator, true)
        XCTAssertEqual(props.separatorInset, 16)
    }

    // MARK: - Sections

    func testEmptySectionsArray() throws {
        let entity = try decodeTableView(tableViewJSON(sections: "[]"))
        XCTAssertTrue(entity.content.sections.isEmpty)
    }

    func testSingleSectionWithHeader() throws {
        let entity = try decodeTableView(tableViewJSON(sections: """
        [
            { "id": "sec1", "header": "Account", "rows": [] }
        ]
        """))
        XCTAssertEqual(entity.content.sections.count, 1)
        XCTAssertEqual(entity.content.sections[0].id, "sec1")
        XCTAssertEqual(entity.content.sections[0].header, "Account")
        XCTAssertNil(entity.content.sections[0].footer)
    }

    func testSectionWithFooter() throws {
        let entity = try decodeTableView(tableViewJSON(sections: """
        [
            { "id": "sec1", "footer": "Version 1.0", "rows": [] }
        ]
        """))
        XCTAssertNil(entity.content.sections[0].header)
        XCTAssertEqual(entity.content.sections[0].footer, "Version 1.0")
    }

    func testMultipleSections() throws {
        let entity = try decodeTableView(tableViewJSON(sections: """
        [
            { "id": "s1", "header": "First",  "rows": [] },
            { "id": "s2", "header": "Second", "rows": [] },
            { "id": "s3", "rows": [] }
        ]
        """))
        XCTAssertEqual(entity.content.sections.count, 3)
        XCTAssertEqual(entity.content.sections[1].header, "Second")
        XCTAssertNil(entity.content.sections[2].header)
    }

    func testMalformedSectionSkippedBySafeArray() throws {
        // Second section is missing required "id" — SafeArrayDecodable should skip it.
        let entity = try decodeTableView(tableViewJSON(sections: """
        [
            { "id": "good", "rows": [] },
            { "BROKEN": true },
            { "id": "also-good", "rows": [] }
        ]
        """))
        XCTAssertEqual(entity.content.sections.count, 2)
        XCTAssertEqual(entity.content.sections[0].id, "good")
        XCTAssertEqual(entity.content.sections[1].id, "also-good")
    }

    // MARK: - Rows

    func testRowDecodesWithHeight() throws {
        let entity = try decodeTableView(tableViewJSON(sections: """
        [
            {
                "id": "sec",
                "rows": [
                    { "id": "row1", "height": 72, "children": [] }
                ]
            }
        ]
        """))
        let row = entity.content.sections[0].rows[0]
        XCTAssertEqual(row.id, "row1")
        XCTAssertEqual(row.height, 72)
    }

    func testRowHeightIsNilWhenAbsent() throws {
        let entity = try decodeTableView(tableViewJSON(sections: """
        [{ "id": "sec", "rows": [{ "id": "r", "children": [] }] }]
        """))
        XCTAssertNil(entity.content.sections[0].rows[0].height)
    }

    func testRowClearBackgroundDefaultsToNil() throws {
        let entity = try decodeTableView(tableViewJSON(sections: """
        [{ "id": "sec", "rows": [{ "id": "r", "children": [] }] }]
        """))
        XCTAssertNil(entity.content.sections[0].rows[0].clearBackground)
    }

    func testRowClearBackgroundTrue() throws {
        let entity = try decodeTableView(tableViewJSON(sections: """
        [
            {
                "id": "sec",
                "rows": [
                    { "id": "footerRow", "height": 110, "clearBackground": true, "children": [] }
                ]
            }
        ]
        """))
        XCTAssertEqual(entity.content.sections[0].rows[0].clearBackground, true)
    }

    func testRowClearBackgroundFalse() throws {
        let entity = try decodeTableView(tableViewJSON(sections: """
        [
            {
                "id": "sec",
                "rows": [
                    { "id": "r", "clearBackground": false, "children": [] }
                ]
            }
        ]
        """))
        XCTAssertEqual(entity.content.sections[0].rows[0].clearBackground, false)
    }

    func testRowTapActionDecodes() throws {
        let entity = try decodeTableView(tableViewJSON(sections: """
        [
            {
                "id": "sec",
                "rows": [
                    {
                        "id": "r",
                        "children": [],
                        "actions": {
                            "tap": { "type": "navigation", "nextScreen": "detail-screen", "presentation": "push" }
                        }
                    }
                ]
            }
        ]
        """))
        let actions = entity.content.sections[0].rows[0].actions
        XCTAssertNotNil(actions?[.tap])
    }

    func testRowActionsNilWhenAbsent() throws {
        let entity = try decodeTableView(tableViewJSON(sections: """
        [{ "id": "sec", "rows": [{ "id": "r", "children": [] }] }]
        """))
        XCTAssertNil(entity.content.sections[0].rows[0].actions)
    }

    func testMalformedRowSkippedByByeSafeArray() throws {
        let entity = try decodeTableView(tableViewJSON(sections: """
        [
            {
                "id": "sec",
                "rows": [
                    { "id": "good-row", "children": [] },
                    { "BROKEN": true },
                    { "id": "another-good", "children": [] }
                ]
            }
        ]
        """))
        let rows = entity.content.sections[0].rows
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].id, "good-row")
        XCTAssertEqual(rows[1].id, "another-good")
    }

    // MARK: - Row children (DSL components)

    func testRowChildLabelDecodes() throws {
        let entity = try decodeTableView(tableViewJSON(sections: """
        [
            {
                "id": "sec",
                "rows": [
                    {
                        "id": "row",
                        "children": [
                            {
                                "id": "myLabel",
                                "type": "label",
                                "content": {
                                    "properties": { "text": "Hello" },
                                    "style": {},
                                    "layout": {}
                                }
                            }
                        ]
                    }
                ]
            }
        ]
        """))
        let children = entity.content.sections[0].rows[0].children
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children[0].id, "myLabel")
        XCTAssertTrue(children[0].type.isOneOf(.label))
    }

    func testRowChildIconDecodes() throws {
        let entity = try decodeTableView(tableViewJSON(sections: """
        [
            {
                "id": "sec",
                "rows": [
                    {
                        "id": "row",
                        "children": [
                            {
                                "id": "chevron",
                                "type": "icon",
                                "content": {
                                    "properties": { "type": "symbol", "name": "chevron.right" },
                                    "style": {},
                                    "layout": {}
                                }
                            }
                        ]
                    }
                ]
            }
        ]
        """))
        let child = entity.content.sections[0].rows[0].children[0]
        XCTAssertTrue(child.type.isOneOf(.icon))
        XCTAssertEqual(child.id, "chevron")
    }

    func testRowMultipleChildrenDecode() throws {
        let entity = try decodeTableView(tableViewJSON(sections: """
        [
            {
                "id": "sec",
                "rows": [
                    {
                        "id": "row",
                        "children": [
                            { "id": "iconBg", "type": "view", "content": { "style": {}, "layout": {} } },
                            { "id": "rowLabel", "type": "label", "content": { "properties": { "text": "Item" }, "style": {}, "layout": {} } },
                            { "id": "rowChevron", "type": "icon", "content": { "properties": { "type": "symbol", "name": "chevron.right" }, "style": {}, "layout": {} } }
                        ]
                    }
                ]
            }
        ]
        """))
        XCTAssertEqual(entity.content.sections[0].rows[0].children.count, 3)
    }

    // MARK: - Standard EntityContent fields

    func testStandardChildrenAreEmptyByDefault() throws {
        // TableView has a `children` field required by EntityContent — always empty for tableView
        let entity = try decodeTableView(tableViewJSON())
        XCTAssertTrue(entity.content.children.isEmpty)
    }

    func testLayoutDecodes() throws {
        let entity = try decodeTableView(tableViewJSON(extra: """
        "layout": {
            "constraints": [
                { "type": "top",    "target": "superview" },
                { "type": "bottom", "target": "superview" }
            ]
        }
        """))
        XCTAssertNotNil(entity.content.layout)
    }

    // MARK: - Full settings-style example

    func testFullSettingsStyleTableDecodes() throws {
        let json = tableViewJSON(
            properties: #"{ "tableStyle": "insetGrouped", "separatorInset": 64, "showsIndicator": false }"#,
            sections: """
            [
                {
                    "id": "profileSection",
                    "rows": [
                        {
                            "id": "profileRow",
                            "height": 72,
                            "children": [
                                { "id": "profileName", "type": "label", "content": { "properties": { "text": "Alex Johnson" }, "style": {}, "layout": {} } }
                            ]
                        }
                    ]
                },
                {
                    "id": "accountSection",
                    "header": "Account",
                    "rows": [
                        { "id": "notificationsRow", "height": 54, "children": [] },
                        { "id": "privacyRow",       "height": 54, "children": [] }
                    ]
                },
                {
                    "id": "footerSection",
                    "rows": [
                        { "id": "footerRow", "height": 110, "clearBackground": true, "children": [] }
                    ]
                }
            ]
            """
        )

        let entity = try decodeTableView(json)
        let content = entity.content

        XCTAssertEqual(content.properties.tableStyle, .insetGrouped)
        XCTAssertEqual(content.properties.separatorInset, 64)
        XCTAssertEqual(content.properties.showsIndicator, false)

        XCTAssertEqual(content.sections.count, 3)

        // Profile section
        let profile = content.sections[0]
        XCTAssertNil(profile.header)
        XCTAssertEqual(profile.rows.count, 1)
        XCTAssertEqual(profile.rows[0].height, 72)
        XCTAssertEqual(profile.rows[0].children.count, 1)

        // Account section
        let account = content.sections[1]
        XCTAssertEqual(account.header, "Account")
        XCTAssertEqual(account.rows.count, 2)
        XCTAssertNil(account.rows[0].clearBackground)

        // Footer section
        let footer = content.sections[2]
        XCTAssertEqual(footer.rows[0].clearBackground, true)
        XCTAssertEqual(footer.rows[0].height, 110)
    }
}
