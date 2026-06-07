//
//  ActionWriteCheckTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

private final class ActionWriteMockDataSource: App8DataSource, @unchecked Sendable {
    var screens: [String: Data] = [:]

    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }

    func getScreen(screenId: String) async throws -> Data {
        guard let data = screens[screenId] else {
            throw NSError(domain: "test", code: 404)
        }
        return data
    }
}

final class ActionWriteCheckTests: XCTestCase {

    private func findings(
        _ json: String
    ) -> (errors: [App8.ValidationError], warnings: [App8.ValidationWarning]) {
        ActionWriteCheck.findings(
            screenData: json.data(using: .utf8)!,
            screenId: "test-screen",
            templateResolver: nil
        )
    }

    // MARK: - ACT001: $-prefixed dotted write target (ERROR)

    func testACT001_firesForParentScopedDottedTarget() {
        let f = findings("""
        {
            "type": "screen", "id": "s",
            "content": {
                "variables": { "count": { "type": "number", "initialValue": 0 } },
                "children": [{
                    "type": "button", "id": "btn",
                    "content": {
                        "actions": {
                            "onTap": { "type": "updateVariable", "variableName": "$parent.count", "value": { "value": 1 } }
                        }
                    }
                }]
            }
        }
        """)
        XCTAssertEqual(f.errors.map(\.code), ["ACT001"], "Expected ACT001 error")
        XCTAssertTrue(f.warnings.isEmpty, "Dotted $-target is an error, not also a warning")
    }

    func testACT001_suggestsBareNameInContext() {
        let f = findings("""
        {
            "type": "screen", "id": "s",
            "content": {
                "children": [{
                    "type": "button", "id": "btn",
                    "content": {
                        "actions": {
                            "onTap": { "type": "updateVariable", "variableName": "$parent.user.name", "value": { "value": "x" } }
                        }
                    }
                }]
            }
        }
        """)
        XCTAssertEqual(f.errors.first?.code, "ACT001")
        XCTAssertEqual(f.errors.first?.context?["suggestedTarget"], "user.name")
        XCTAssertEqual(f.errors.first?.context?["target"], "$parent.user.name")
    }

    // MARK: - ACT002: undeclared write target (WARNING)

    func testACT002_firesForUndeclaredTarget() {
        let f = findings("""
        {
            "type": "screen", "id": "s",
            "content": {
                "variables": { "count": { "type": "number", "initialValue": 0 } },
                "actions": {
                    "onAppear": { "type": "updateVariable", "variableName": "missing", "value": { "value": 1 } }
                }
            }
        }
        """)
        XCTAssertEqual(f.warnings.map(\.code), ["ACT002"], "Expected ACT002 warning")
        XCTAssertEqual(f.warnings.first?.context?["target"], "missing")
    }

    func testACT002_noFireWhenDeclaredInSameNode() {
        let f = findings("""
        {
            "type": "screen", "id": "s",
            "content": {
                "variables": { "count": { "type": "number", "initialValue": 0 } },
                "actions": {
                    "onAppear": { "type": "updateVariable", "variableName": "count", "value": { "value": 1 } }
                }
            }
        }
        """)
        XCTAssertTrue(f.warnings.isEmpty, "Declared variable should not warn: \(f.warnings.map(\.code))")
        XCTAssertTrue(f.errors.isEmpty)
    }

    func testACT002_noFireForImplicitScopeNames() {
        // item / index / section / event are injected by the engine, never declared.
        let f = findings("""
        {
            "type": "screen", "id": "s",
            "content": {
                "children": [{
                    "type": "button", "id": "btn",
                    "content": {
                        "actions": {
                            "onTap": [
                                { "type": "updateVariable", "variableName": "item", "value": { "value": 1 } },
                                { "type": "updateVariable", "variableName": "event", "value": { "value": 1 } }
                            ]
                        }
                    }
                }]
            }
        }
        """)
        XCTAssertTrue(f.warnings.isEmpty, "Implicit names should not warn: \(f.warnings.map(\.code))")
    }

    // MARK: - Scope inheritance

    func testInheritedScope_childWriteToParentDeclaredVariableIsClean() {
        let f = findings("""
        {
            "type": "screen", "id": "s",
            "content": {
                "variables": { "count": { "type": "number", "initialValue": 0 } },
                "children": [{
                    "type": "view", "id": "wrap",
                    "content": {
                        "children": [{
                            "type": "button", "id": "btn",
                            "content": {
                                "actions": {
                                    "onTap": { "type": "updateVariable", "variableName": "count", "value": { "value": 1 } }
                                }
                            }
                        }]
                    }
                }]
            }
        }
        """)
        XCTAssertTrue(f.warnings.isEmpty, "Bare name resolves up the scope chain: \(f.warnings.map(\.code))")
        XCTAssertTrue(f.errors.isEmpty)
    }

    func testTemplateInstanceBindingExtendsScope() {
        // A node's `variables` (template-instance bindings) declare names too.
        let f = findings("""
        {
            "type": "screen", "id": "s",
            "content": {
                "children": [{
                    "type": "component", "id": "inst",
                    "variables": { "bound": 5 },
                    "content": {
                        "actions": {
                            "onTap": { "type": "updateVariable", "variableName": "bound", "value": { "value": 1 } }
                        }
                    }
                }]
            }
        }
        """)
        XCTAssertTrue(f.warnings.isEmpty, "Template-instance binding should be in scope: \(f.warnings.map(\.code))")
    }

    // MARK: - Action shapes

    func testUpdateMultipleVariables_checksEachKey() {
        let f = findings("""
        {
            "type": "screen", "id": "s",
            "content": {
                "variables": { "a": { "type": "number", "initialValue": 0 } },
                "actions": {
                    "onAppear": {
                        "type": "updateMultipleVariables",
                        "updates": { "a": 1, "b": 2 }
                    }
                }
            }
        }
        """)
        XCTAssertEqual(f.warnings.map(\.code), ["ACT002"], "Only undeclared 'b' should warn")
        XCTAssertEqual(f.warnings.first?.context?["target"], "b")
    }

    func testArrayOfActions_eachChecked() {
        let f = findings("""
        {
            "type": "screen", "id": "s",
            "content": {
                "actions": {
                    "onAppear": [
                        { "type": "updateVariable", "variableName": "x", "value": { "value": 1 } },
                        { "type": "updateVariable", "variableName": "y", "value": { "value": 2 } }
                    ]
                }
            }
        }
        """)
        XCTAssertEqual(Set(f.warnings.compactMap { $0.context?["target"] }), ["x", "y"])
    }

    func testOtherWriteTypes_areChecked() {
        for type in ["incrementVariable", "toggleArrayValue", "appendToArray"] {
            let f = findings("""
            {
                "type": "screen", "id": "s",
                "content": {
                    "actions": {
                        "onAppear": { "type": "\(type)", "variableName": "undeclared" }
                    }
                }
            }
            """)
            XCTAssertEqual(f.warnings.map(\.code), ["ACT002"], "\(type) should flag undeclared target")
        }
    }

    func testNonWriteActionType_ignored() {
        let f = findings("""
        {
            "type": "screen", "id": "s",
            "content": {
                "actions": {
                    "onTap": { "type": "navigate", "screenId": "other" }
                }
            }
        }
        """)
        XCTAssertTrue(f.errors.isEmpty && f.warnings.isEmpty, "navigate is not a write — should be ignored")
    }

    func testCleanScreen_noFindings() {
        let f = findings("""
        {
            "type": "screen", "id": "s",
            "content": {
                "variables": { "count": { "type": "number", "initialValue": 0 } },
                "actions": {
                    "onAppear": { "type": "updateVariable", "variableName": "count", "value": { "value": 1 } }
                }
            }
        }
        """)
        XCTAssertTrue(f.errors.isEmpty && f.warnings.isEmpty)
    }

    func testMalformedJSON_returnsEmpty() {
        let f = ActionWriteCheck.findings(
            screenData: Data("not json".utf8),
            screenId: nil,
            templateResolver: nil
        )
        XCTAssertTrue(f.errors.isEmpty && f.warnings.isEmpty)
    }

    // MARK: - Per-app run() over a data source

    func testRun_producesActionsSection() async {
        let ds = ActionWriteMockDataSource()
        ds.screens["test-screen"] = """
        {
            "type": "screen", "id": "test-screen",
            "content": {
                "actions": {
                    "onAppear": { "type": "updateVariable", "variableName": "$parent.x", "value": { "value": 1 } }
                }
            }
        }
        """.data(using: .utf8)!

        let section = await ActionWriteCheck.run(
            screenIds: ["test-screen"],
            dataSource: ds,
            templateResolver: nil
        )

        XCTAssertEqual(section.kind, .actions)
        XCTAssertEqual(section.errors.map(\.code), ["ACT001"])
        XCTAssertTrue(section.errors.first?.path?.contains("screens/test-screen") ?? false)
    }

    func testRun_cleanScreen_reportsAllResolve() async {
        let ds = ActionWriteMockDataSource()
        ds.screens["test-screen"] = """
        { "type": "screen", "id": "test-screen", "content": {} }
        """.data(using: .utf8)!

        let section = await ActionWriteCheck.run(
            screenIds: ["test-screen"],
            dataSource: ds,
            templateResolver: nil
        )
        XCTAssertTrue(section.errors.isEmpty && section.warnings.isEmpty)
        XCTAssertEqual(section.statusDetail, "all variable writes resolve")
    }
}
