//
//  CollectionExamplesTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

@MainActor
final class CollectionExamplesTests: XCTestCase {

    // MARK: - SectionDefinition Parsing

    func testSectionDefinitionMinimalDecode() throws {
        let json = #"{"key":"settings","data":"{{settingsItems}}"}"#.data(using: .utf8)!
        let def = try JSONDecoder().decode(DSL.Model.Component.Collection.SectionDefinition.self, from: json)
        XCTAssertEqual(def.key, "settings")
        XCTAssertEqual(def.data, "{{settingsItems}}")
    }

    func testSectionDefinitionWithTemplate() throws {
        let json = #"{"key":"header","data":"{{profileData}}","templateName":"profileHeader"}"#.data(using: .utf8)!
        let def = try JSONDecoder().decode(DSL.Model.Component.Collection.SectionDefinition.self, from: json)
        XCTAssertEqual(def.key, "header")
        XCTAssertEqual(def.templateName, "profileHeader")
        XCTAssertNil(def.templateKey)
    }

    func testSectionDefinitionWithTemplateKey() throws {
        let json = #"{"key":"feed","data":"{{items}}","templateKey":"item.type"}"#.data(using: .utf8)!
        let def = try JSONDecoder().decode(DSL.Model.Component.Collection.SectionDefinition.self, from: json)
        XCTAssertEqual(def.templateKey, "item.type")
        XCTAssertNil(def.templateName)
    }

    func testSectionDefinitionOptionalFieldsDefaultNil() throws {
        let json = #"{"key":"k","data":"{{v}}"}"#.data(using: .utf8)!
        let def = try JSONDecoder().decode(DSL.Model.Component.Collection.SectionDefinition.self, from: json)
        XCTAssertNil(def.templateName)
        XCTAssertNil(def.templateKey)
    }

    // MARK: - Collection.Properties Parsing

    func testCollectionPropertiesWithSectionsArray() throws {
        let json = """
        {
            "layout": {"type": "vertical"},
            "sectionDefinitions": [
                {"key": "header",   "data": "{{profileData}}",   "templateName": "profileHeader"},
                {"key": "settings", "data": "{{settingsItems}}", "templateName": "settingsRow"},
                {"key": "support",  "data": "{{supportItems}}",  "templateName": "settingsRow"}
            ]
        }
        """.data(using: .utf8)!
        let props = try JSONDecoder().decode(DSL.Model.Component.Collection.Properties.self, from: json)
        XCTAssertEqual(props.sectionDefinitions?.count, 3)
        XCTAssertEqual(props.sectionDefinitions?[0].key, "header")
        XCTAssertEqual(props.sectionDefinitions?[1].key, "settings")
        XCTAssertEqual(props.sectionDefinitions?[2].key, "support")
        XCTAssertEqual(props.sectionDefinitions?[0].templateName, "profileHeader")
        XCTAssertEqual(props.sectionDefinitions?[1].templateName, "settingsRow")
        XCTAssertNil(props.data)
        XCTAssertNil(props.groupBy)
    }

    func testCollectionPropertiesWithGroupByAndTemplateKey() throws {
        let json = """
        {
            "data": "{{listings}}",
            "groupBy": "{{item.sectionTitle}}",
            "templateKey": "item.isFeatured",
            "layout": {"type": "vertical"}
        }
        """.data(using: .utf8)!
        let props = try JSONDecoder().decode(DSL.Model.Component.Collection.Properties.self, from: json)
        XCTAssertEqual(props.data, "{{listings}}")
        XCTAssertEqual(props.groupBy, "{{item.sectionTitle}}")
        XCTAssertEqual(props.templateKey, "item.isFeatured")
        XCTAssertNil(props.sectionDefinitions)
    }

    func testCollectionPropertiesWithSingleDataBinding() throws {
        let json = """
        {
            "data": "{{listings}}",
            "templateKey": "item.isFeatured",
            "layout": {"type": "vertical", "itemSpacing": 16, "estimatedItemHeight": 260}
        }
        """.data(using: .utf8)!
        let props = try JSONDecoder().decode(DSL.Model.Component.Collection.Properties.self, from: json)
        XCTAssertEqual(props.data, "{{listings}}")
        XCTAssertEqual(props.templateKey, "item.isFeatured")
        XCTAssertNil(props.sectionDefinitions)
        XCTAssertNil(props.groupBy)
    }

    // MARK: - Swipe Actions Parsing

    func testSwipeActionsTrailingDecodes() throws {
        let json = """
        {
            "layout": {"type": "vertical"},
            "data": "{{items}}",
            "swipeActions": {
                "trailing": [
                    {
                        "title": "Delete",
                        "systemImage": "trash",
                        "backgroundColor": "#FF3B30",
                        "style": "destructive",
                        "action": { "type": "toggleArrayValue", "variableName": "items", "value": "{{item.id}}" }
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        let props = try JSONDecoder().decode(DSL.Model.Component.Collection.Properties.self, from: json)
        XCTAssertNotNil(props.swipeActions)
        XCTAssertEqual(props.swipeActions?.trailing?.count, 1)
        XCTAssertNil(props.swipeActions?.leading)
        let swipe = props.swipeActions?.trailing?[0]
        XCTAssertEqual(swipe?.title, "Delete")
        XCTAssertEqual(swipe?.systemImage, "trash")
        XCTAssertEqual(swipe?.backgroundColor, "#FF3B30")
        XCTAssertEqual(swipe?.style, .destructive)
        XCTAssertEqual(swipe?.action?.type, .toggleArrayValue)
        XCTAssertEqual(swipe?.action?.variableName, "items")
    }

    func testSwipeActionsLeadingAndTrailing() throws {
        let json = """
        {
            "layout": {"type": "vertical"},
            "data": "{{items}}",
            "swipeActions": {
                "leading": [
                    { "title": "Archive", "systemImage": "archivebox", "backgroundColor": "#FF9500",
                      "action": { "type": "updateVariable", "variableName": "archivedId", "value": "{{item.id}}" } }
                ],
                "trailing": [
                    { "title": "Delete", "systemImage": "trash", "style": "destructive",
                      "action": { "type": "toggleArrayValue", "variableName": "items", "value": "{{item.id}}" } }
                ],
                "allowFullSwipe": false
            }
        }
        """.data(using: .utf8)!
        let props = try JSONDecoder().decode(DSL.Model.Component.Collection.Properties.self, from: json)
        XCTAssertEqual(props.swipeActions?.leading?.count, 1)
        XCTAssertEqual(props.swipeActions?.trailing?.count, 1)
        XCTAssertEqual(props.swipeActions?.allowFullSwipe, false)
        XCTAssertEqual(props.swipeActions?.leading?[0].title, "Archive")
        XCTAssertEqual(props.swipeActions?.leading?[0].style, nil) // default normal
        XCTAssertEqual(props.swipeActions?.trailing?[0].style, .destructive)
    }

    func testSwipeActionsAbsentWhenNotDefined() throws {
        let json = """
        { "layout": {"type": "vertical"}, "data": "{{items}}" }
        """.data(using: .utf8)!
        let props = try JSONDecoder().decode(DSL.Model.Component.Collection.Properties.self, from: json)
        XCTAssertNil(props.swipeActions)
    }

    func testSwipeActionsMultipleTrailingActions() throws {
        let json = """
        {
            "layout": {"type": "vertical"},
            "data": "{{items}}",
            "swipeActions": {
                "trailing": [
                    { "title": "Delete", "style": "destructive", "action": { "type": "toggleArrayValue", "variableName": "items", "value": "{{item.id}}" } },
                    { "title": "Flag", "backgroundColor": "#FFCC00", "action": { "type": "updateVariable", "variableName": "flaggedId", "value": "{{item.id}}" } }
                ]
            }
        }
        """.data(using: .utf8)!
        let props = try JSONDecoder().decode(DSL.Model.Component.Collection.Properties.self, from: json)
        XCTAssertEqual(props.swipeActions?.trailing?.count, 2)
        XCTAssertEqual(props.swipeActions?.trailing?[0].title, "Delete")
        XCTAssertEqual(props.swipeActions?.trailing?[1].title, "Flag")
    }

    // MARK: - Inline Array VariableDefinition

    func testVariableDefinitionWithInitialValueArray() throws {
        let json = """
        {
            "type": "array",
            "initialValue": [
                {"icon": "bell.fill", "title": "Notifications"},
                {"icon": "lock.fill", "title": "Privacy"}
            ]
        }
        """.data(using: .utf8)!
        let varDef = try JSONDecoder().decode(VariableDefinition.self, from: json)
        XCTAssertEqual(varDef.type, .array)
        let items = varDef.rawInitialValue as? [[String: Any]]
        XCTAssertNotNil(items)
        XCTAssertEqual(items?.count, 2)
    }

    func testInitialValueArrayContents() throws {
        let json = """
        {
            "type": "array",
            "initialValue": [
                {"icon": "bell.fill", "title": "Notifications"},
                {"icon": "lock.fill", "title": "Privacy"},
                {"icon": "eye.fill", "title": "Appearance"},
                {"icon": "iphone", "title": "Device"}
            ]
        }
        """.data(using: .utf8)!
        let varDef = try JSONDecoder().decode(VariableDefinition.self, from: json)
        let items = varDef.rawInitialValue as? [[String: Any]]
        XCTAssertEqual(items?.count, 4)
        XCTAssertEqual(items?[0]["icon"] as? String, "bell.fill")
        XCTAssertEqual(items?[0]["title"] as? String, "Notifications")
        XCTAssertEqual(items?[3]["title"] as? String, "Device")
    }

    func testVariableDefinitionWithSourceHasNoInitialValue() throws {
        let json = #"{"type":"array","source":"datasources/profile"}"#.data(using: .utf8)!
        let varDef = try JSONDecoder().decode(VariableDefinition.self, from: json)
        XCTAssertNil(varDef.rawInitialValue)
        XCTAssertEqual(varDef.source, "datasources/profile")
    }

    // MARK: - DatasourceResolver with example data

    func testProfileDataDatasourceResolves() async throws {
        let mockDataSource = MockDataSource()
        mockDataSource.datasources["datasources/profile"] = """
        [{"name":"Alex Johnson","handle":"@alexj","avatarColor":"#3A86FF","bio":"iOS Developer · San Francisco, CA"}]
        """.data(using: .utf8)!

        let variables: [String: VariableDefinition] = [
            "profileData": VariableDefinition(type: .array, source: "datasources/profile")
        ]
        let resolved = try await DatasourceResolver.resolveDatasources(
            screenId: "profile-settings-screen",
            variables: variables,
            dataSource: mockDataSource
        )

        let items = resolved["profileData"]?.rawInitialValue as? [[String: Any]]
        XCTAssertEqual(items?.count, 1)
        XCTAssertEqual(items?[0]["name"] as? String, "Alex Johnson")
        XCTAssertEqual(items?[0]["handle"] as? String, "@alexj")
    }

    func testPropertyListingsDatasourceResolves() async throws {
        let mockDataSource = MockDataSource()
        mockDataSource.datasources["datasources/property-listings"] = """
        {
            "data": [
                {"id": "1", "title": "Beachfront Villa",  "isFeatured": true},
                {"id": "2", "title": "City Studio",        "isFeatured": false},
                {"id": "3", "title": "Mountain Chalet",    "isFeatured": false},
                {"id": "4", "title": "Lakeside Retreat",   "isFeatured": true},
                {"id": "5", "title": "Forest Cabin",       "isFeatured": false},
                {"id": "6", "title": "Desert Hideaway",    "isFeatured": false},
                {"id": "7", "title": "Coastal Cottage",    "isFeatured": false},
                {"id": "8", "title": "Historic Loft",      "isFeatured": false}
            ]
        }
        """.data(using: .utf8)!

        let variables: [String: VariableDefinition] = [
            "listings": VariableDefinition(type: .array, source: "datasources/property-listings")
        ]
        let resolved = try await DatasourceResolver.resolveDatasources(
            screenId: "property-feed-home-screen",
            variables: variables,
            dataSource: mockDataSource
        )

        let items = resolved["listings"]?.rawInitialValue as? [[String: Any]]
        XCTAssertEqual(items?.count, 8)
        XCTAssertEqual(items?[0]["title"] as? String, "Beachfront Villa")
        XCTAssertEqual(items?[0]["isFeatured"] as? Bool, true)
    }

    func testInlineArrayVariablesPassThroughUnchanged() async throws {
        let mockDataSource = MockDataSource()

        let variables: [String: VariableDefinition] = [
            "settingsItems": VariableDefinition(
                type: .array,
                initialValue: [
                    ["icon": "bell.fill", "title": "Notifications"],
                    ["icon": "lock.fill", "title": "Privacy"]
                ]
            )
        ]
        let resolved = try await DatasourceResolver.resolveDatasources(
            screenId: "profile-settings-screen",
            variables: variables,
            dataSource: mockDataSource
        )

        let items = resolved["settingsItems"]?.rawInitialValue as? [[String: Any]]
        XCTAssertEqual(items?.count, 2)
        XCTAssertEqual(items?[0]["title"] as? String, "Notifications")
        XCTAssertNil(resolved["settingsItems"]?.source)
    }
}
