//
//  TemplatePreprocessorTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

@MainActor
final class TemplatePreprocessorTests: XCTestCase {

    /// Builds a TemplatePreprocessor with a single template named "ValueDisplay"
    /// that exposes a `value` string variable and renders it in a label.
    private func makePreprocessor() -> TemplatePreprocessor {
        let templateJSON = """
        {
            "id": "ValueDisplay",
            "type": "view",
            "content": {
                "variables": {
                    "value": { "type": "string", "initialValue": "" }
                },
                "children": [
                    {
                        "id": "lbl",
                        "type": "label",
                        "content": {
                            "properties": { "text": "{{value}}" }
                        }
                    }
                ]
            }
        }
        """
        let template = try! JSONDecoder().decode(
            DSL.Model.Component.Template.self,
            from: templateJSON.data(using: .utf8)!
        )
        var resolver = TemplateResolver(templates: [template])
        resolver.resolveAllTemplates()
        return TemplatePreprocessor(resolver: resolver)
    }

    /// Preprocesses a screen JSON string and returns the decoded output as a JSONValue.
    private func preprocess(_ screenJSON: String) -> JSONValue? {
        let preprocessor = makePreprocessor()
        guard let data = screenJSON.data(using: .utf8),
              let result = preprocessor.preprocess(data) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: result)
    }

    /// Extracts the variable definition object for `name` from the preprocessed
    /// first child's content.variables.
    /// Path: result.content.children[0].content.variables.<name>
    private func extractVar(named name: String, from result: JSONValue) -> [String: JSONValue]? {
        guard case .object(let root) = result,
              case .object(let screenContent) = root["content"],
              case .array(let children) = screenContent["children"],
              case .object(let child) = children.first,
              case .object(let content) = child["content"],
              case .object(let variables) = content["variables"],
              case .object(let varDef) = variables[name] else { return nil }
        return varDef
    }

    // MARK: - normalizeVariables: shorthand routing

    func testPlainStringBecomesInitialValue() {
        let screen = """
        {
            "id": "s", "type": "screen",
            "content": {
                "children": [{
                    "id": "c", "type": "view",
                    "variables": { "value": "Hello" },
                    "templateId": "ValueDisplay"
                }]
            }
        }
        """
        let result = preprocess(screen)!
        let varDef = extractVar(named: "value", from: result)!

        XCTAssertEqual(varDef["initialValue"], .string("Hello"))
        XCTAssertNil(varDef["computed"])
    }

    func testBareExpressionBecomesComputed() {
        let screen = """
        {
            "id": "s", "type": "screen",
            "content": {
                "children": [{
                    "id": "c", "type": "view",
                    "variables": { "value": "{{count}}" },
                    "templateId": "ValueDisplay"
                }]
            }
        }
        """
        let result = preprocess(screen)!
        let varDef = extractVar(named: "value", from: result)!

        XCTAssertEqual(varDef["computed"], .string("{{count}}"))
        XCTAssertNil(varDef["initialValue"])
    }

    func testInterpolatedStringWithPrefixBecomesComputed() {
        // "Count: {{count}}" has text outside braces — compiled to a + concatenation node.
        let screen = """
        {
            "id": "s", "type": "screen",
            "content": {
                "children": [{
                    "id": "c", "type": "view",
                    "variables": { "value": "Count: {{count}}" },
                    "templateId": "ValueDisplay"
                }]
            }
        }
        """
        let result = preprocess(screen)!
        let varDef = extractVar(named: "value", from: result)!

        XCTAssertEqual(varDef["computed"], .string("Count: {{count}}"))
        XCTAssertNil(varDef["initialValue"])
    }

    func testCompoundExpressionBecomesComputed() {
        // "{{a}} / {{b}}" has multiple expressions — compiled to a + concatenation chain.
        let screen = """
        {
            "id": "s", "type": "screen",
            "content": {
                "children": [{
                    "id": "c", "type": "view",
                    "variables": { "value": "{{a.x}} / {{b.y}}" },
                    "templateId": "ValueDisplay"
                }]
            }
        }
        """
        let result = preprocess(screen)!
        let varDef = extractVar(named: "value", from: result)!

        XCTAssertEqual(varDef["computed"], .string("{{a.x}} / {{b.y}}"))
        XCTAssertNil(varDef["initialValue"])
    }

    func testFullObjectFormPassesThroughUnchanged() {
        // When the caller already provides a full VariableDefinition object, it must not be modified.
        let screen = """
        {
            "id": "s", "type": "screen",
            "content": {
                "children": [{
                    "id": "c", "type": "view",
                    "variables": { "value": { "type": "string", "computed": "{{x}}" } },
                    "templateId": "ValueDisplay"
                }]
            }
        }
        """
        let result = preprocess(screen)!
        let varDef = extractVar(named: "value", from: result)!

        XCTAssertEqual(varDef["computed"], .string("{{x}}"))
        XCTAssertNil(varDef["initialValue"])
    }

    // MARK: - End-to-end: computed variable evaluates against parent scope

    func testExpressionVarEvaluatesFromParentScope() throws {
        // Screen store has `count = 3`. Template instance passes `"value": "{{count}}"`.
        // After preprocess the variable definition has `computed: "{{count}}"`.
        // When the ScopedVariableStore (component scope) resolves `value`,
        // it must evaluate `count` from the parent (screen) scope → "3".

        let screenStore = ScopedVariableStore(parent: VariableStore())
        try screenStore.defineVariables([
            "count": VariableDefinition(type: .number, initialValue: 3)
        ])

        let screen = """
        {
            "id": "s", "type": "screen",
            "content": {
                "children": [{
                    "id": "c", "type": "view",
                    "variables": { "value": "{{count}}" },
                    "templateId": "ValueDisplay"
                }]
            }
        }
        """
        let result = preprocess(screen)!
        let varDef = extractVar(named: "value", from: result)!
        XCTAssertEqual(varDef["computed"], .string("{{count}}"),
                       "Precondition: variable must be stored as computed")

        // Simulate what CBaseViewModel does: define variables into a component-scoped store
        let componentStore = ScopedVariableStore(parent: screenStore)
        let definition = VariableDefinition(type: .string, computed: "{{count}}")
        try componentStore.defineVariable(name: "value", definition: definition)

        // The component store should resolve `value` by evaluating `{{count}}` in parent scope
        let resolved = componentStore.getValue(name: "value")
        XCTAssertEqual(resolved as? Int, 3)
    }
}
