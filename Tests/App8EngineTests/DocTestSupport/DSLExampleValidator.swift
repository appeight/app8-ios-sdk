import Foundation
@testable import App8Engine

/// Validates extracted JSON examples by attempting to decode them as DSL types
struct DSLExampleValidator {

    enum ValidationResult {
        case success(decodedAs: String)
        case skipped(reason: String)
        case failed(error: Error)
    }

    /// Validate a single extracted example
    static func validate(_ example: ExtractedExample) -> ValidationResult {
        if case .skip(let reason) = example.annotation {
            return .skipped(reason: "@dsl-skip: \(reason)")
        }

        if example.json.contains("...") {
            return .skipped(reason: "contains placeholder '...'")
        }

        let trimmedJson = example.json.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedJson == "{ }" || trimmedJson == "{}" {
            return .skipped(reason: "empty object placeholder")
        }

        if trimmedJson.contains("[ ]") {
            return .skipped(reason: "contains empty array placeholder '[ ]'")
        }

        guard let jsonData = example.json.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return .skipped(reason: "not a valid JSON object")
        }

        if case .type(let typeName) = example.annotation {
            return validateWithType(typeName, data: jsonData, json: jsonObject)
        }

        return validateWithInferredType(data: jsonData, json: jsonObject)
    }

    // MARK: - Private

    private static func validateWithType(_ typeName: String, data: Data, json: [String: Any]) -> ValidationResult {
        let decoder = JSONDecoder()

        do {
            switch typeName {
            case "Component", "Component.Any":
                // Use lenient structural validation for doc examples
                // (doesn't require 'id' or all component-specific fields)
                return validateComponentStructure(json: json)

            case "App":
                _ = try decoder.decode(DSL.Model.App.self, from: data)
                return .success(decodedAs: "App")

            case "Layout":
                _ = try decoder.decode(DSL.Model.Layout.self, from: data)
                return .success(decodedAs: "Layout")

            case "Fill":
                _ = try decoder.decode(DSL.Model.Style.Fill.self, from: data)
                return .success(decodedAs: "Fill")

            case "Corner":
                _ = try decoder.decode(DSL.Model.Style.Corner.self, from: data)
                return .success(decodedAs: "Corner")

            case "Material":
                _ = try decoder.decode(DSL.Model.Style.Material.self, from: data)
                return .success(decodedAs: "Material")

            case "Shadow":
                _ = try decoder.decode([DSL.Model.Style.Shadow.Layer].self, from: data)
                return .success(decodedAs: "Shadow")

            case "TextModel":
                _ = try decoder.decode(DSL.Model.Style.TextModel.self, from: data)
                return .success(decodedAs: "TextModel")

            case "Constraint":
                _ = try decoder.decode(DSL.Model.Layout.Constraint.self, from: data)
                return .success(decodedAs: "Constraint")

            default:
                return .skipped(reason: "unknown type annotation '\(typeName)'")
            }
        } catch {
            return .failed(error: error)
        }
    }

    // Valid component types
    private static let componentTypes: Set<String> = [
        "view", "button", "label", "icon", "image", "textField", "textView",
        "collection", "scroll", "scrollView", "stack", "stackView", "spacer", "pager",
        "screen", "tabBarScreen", "map", "shape"
    ]

    // Valid action types — mirrors DSL.Model.Action.`Type`
    private static let actionTypes: Set<String> = [
        "navigation", "dismiss", "completeFlow", "selectTab",
        "updateVariable", "incrementVariable", "toggleArrayValue",
        "appendToArray", "updateMultipleVariables", "resetVariables",
        "setState", "focus", "focusNext", "focusPrevious",
        "dismissKeyboard", "executeFunction",
        "showAlert", "haptic", "openURL"
    ]

    private static func validateWithInferredType(data: Data, json: [String: Any]) -> ValidationResult {
        let decoder = JSONDecoder()

        // Pattern: Has "type" key → Could be Component or Action
        if let typeValue = json["type"] as? String {
            if actionTypes.contains(typeValue) {
                return validateActionStructure(json: json)
            } else if componentTypes.contains(typeValue) {
                return validateComponentStructure(json: json)
            } else {
                return .failed(error: ValidationError("Unknown type: '\(typeValue)'"))
            }
        }

        // Pattern: Has "title" + "navigation" → App
        if json["title"] != nil && json["navigation"] != nil {
            do {
                _ = try decoder.decode(DSL.Model.App.self, from: data)
                return .success(decodedAs: "App")
            } catch {
                return .failed(error: error)
            }
        }

        // Pattern: Has layout dimension keys → Layout
        let layoutKeys: Set<String> = ["width", "height", "leading", "trailing", "top", "bottom", "constraints", "ignoresSafeArea"]
        let jsonKeys = Set(json.keys)
        if !jsonKeys.intersection(layoutKeys).isEmpty && json["type"] == nil {
            if json["layout"] is [String: Any] {
                return .skipped(reason: "layout wrapper fragment, not standalone Layout")
            }

            do {
                _ = try decoder.decode(DSL.Model.Layout.self, from: data)
                return .success(decodedAs: "Layout")
            } catch {
                return .failed(error: error)
            }
        }

        // Pattern: Has "solid" or "gradient" → Fill
        if json["solid"] != nil || json["gradient"] != nil {
            do {
                _ = try decoder.decode(DSL.Model.Style.Fill.self, from: data)
                return .success(decodedAs: "Fill")
            } catch {
                return .failed(error: error)
            }
        }

        // Pattern: Has "radius" + optional "curve" → Corner
        if json["radius"] != nil && json["curve"] != nil {
            do {
                _ = try decoder.decode(DSL.Model.Style.Corner.self, from: data)
                return .success(decodedAs: "Corner")
            } catch {
                return .failed(error: error)
            }
        }

        // Pattern: Has "corner" key (wrapper) → Try Corner from content
        if let cornerObj = json["corner"] as? [String: Any],
           let cornerData = try? JSONSerialization.data(withJSONObject: cornerObj) {
            do {
                _ = try decoder.decode(DSL.Model.Style.Corner.self, from: cornerData)
                return .success(decodedAs: "Corner (from wrapper)")
            } catch {
                return .failed(error: error)
            }
        }

        // Pattern: Has "outline" key → Try Outline from content
        if let outlineObj = json["outline"] as? [String: Any],
           let outlineData = try? JSONSerialization.data(withJSONObject: outlineObj) {
            do {
                _ = try decoder.decode(DSL.Model.Style.Outline.self, from: outlineData)
                return .success(decodedAs: "Outline (from wrapper)")
            } catch {
                return .failed(error: error)
            }
        }

        // Pattern: Has "shadow" key with array → Shadow layers
        if let shadowArray = json["shadow"] as? [[String: Any]],
           let shadowData = try? JSONSerialization.data(withJSONObject: shadowArray) {
            do {
                _ = try decoder.decode([DSL.Model.Style.Shadow.Layer].self, from: shadowData)
                return .success(decodedAs: "Shadow (from wrapper)")
            } catch {
                return .failed(error: error)
            }
        }

        // Pattern: Has "material" key with array → Material
        if let materialArray = json["material"] as? [[String: Any]],
           let materialData = try? JSONSerialization.data(withJSONObject: materialArray) {
            do {
                _ = try decoder.decode(DSL.Model.Style.Material.self, from: materialData)
                return .success(decodedAs: "Material (from wrapper)")
            } catch {
                return .failed(error: error)
            }
        }

        // Pattern: Has "visualEffect" key → VisualEffect
        if let visualEffectObj = json["visualEffect"] as? [String: Any],
           let veData = try? JSONSerialization.data(withJSONObject: visualEffectObj) {
            do {
                _ = try decoder.decode(DSL.Model.Style.VisualEffect.self, from: veData)
                return .success(decodedAs: "VisualEffect (from wrapper)")
            } catch {
                return .failed(error: error)
            }
        }

        // Pattern: Has "text" key with text style properties → TextModel
        if let textObj = json["text"] as? [String: Any],
           textObj["fontSize"] != nil || textObj["fontWeight"] != nil,
           let textData = try? JSONSerialization.data(withJSONObject: textObj) {
            do {
                _ = try decoder.decode(DSL.Model.Style.TextModel.self, from: textData)
                return .success(decodedAs: "TextModel (from wrapper)")
            } catch {
                return .failed(error: error)
            }
        }

        // Pattern: Has "transform" key → Transform
        if let transformObj = json["transform"] as? [String: Any],
           let transformData = try? JSONSerialization.data(withJSONObject: transformObj) {
            do {
                _ = try decoder.decode(DSL.Model.Style.View.Transform.self, from: transformData)
                return .success(decodedAs: "Transform (from wrapper)")
            } catch {
                return .failed(error: error)
            }
        }

        // Pattern: Has "padding" key with EdgeInsets properties → EdgeInsets
        if let paddingObj = json["padding"] as? [String: Any],
           (paddingObj["top"] != nil || paddingObj["left"] != nil ||
            paddingObj["bottom"] != nil || paddingObj["right"] != nil) {
            // EdgeInsets is a simple struct, just validate it has numeric values
            return .success(decodedAs: "EdgeInsets (structure validated)")
        }

        // Pattern: Has "children" array → Component fragment (skip)
        if json["children"] != nil {
            return .skipped(reason: "children fragment without type")
        }

        // Pattern: Has "properties" key → Component content fragment (skip)
        if json["properties"] != nil {
            return .skipped(reason: "properties fragment without type")
        }

        // Pattern: Has "style" key → Style fragment (skip)
        if json["style"] != nil {
            return .skipped(reason: "style fragment (wrapper)")
        }

        // Pattern: Has "actions" key → Actions fragment (skip)
        if json["actions"] != nil {
            return .skipped(reason: "actions fragment (partial)")
        }

        // Pattern: Single constraint object with "target" → Constraint
        if json["target"] != nil && (json["constant"] != nil || json["attribute"] != nil) {
            do {
                _ = try decoder.decode(DSL.Model.Layout.Constraint.self, from: data)
                return .success(decodedAs: "Constraint")
            } catch {
                return .failed(error: error)
            }
        }

        // Pattern: Color string → skip (just a value example)
        if json.count == 1, let colorKey = json.keys.first,
           colorKey == "color" || colorKey == "tint" || colorKey == "tintColor" {
            return .skipped(reason: "color value example")
        }

        // Pattern: Simple key-value pairs that look like documentation examples
        if json.count <= 2 {
            return .skipped(reason: "simple key-value example, cannot infer type")
        }

        return .skipped(reason: "cannot infer DSL type from structure")
    }

    /// Lenient structural validation for component examples in documentation.
    /// Validates the JSON structure without requiring all fields (like 'id').
    private static func validateComponentStructure(json: [String: Any]) -> ValidationResult {
        guard let typeValue = json["type"] as? String else {
            return .failed(error: ValidationError("Component missing 'type' field"))
        }

        guard componentTypes.contains(typeValue) else {
            return .failed(error: ValidationError("Unknown component type: '\(typeValue)'"))
        }

        if let content = json["content"] as? [String: Any] {
            // Common content keys - not a strict allowlist since components
            // have type-specific keys (e.g., tabBarScreen has 'tabs')
            let validContentKeys: Set<String> = [
                // Common keys
                "properties", "style", "layout", "children", "variables",
                "actions", "triggers", "states", "defaultStateName", "template",
                // Screen-specific
                "navigationBar", "inputParameters", "onEvent",
                // TabBarScreen-specific
                "tabs", "initialTab", "tintColor", "unselectedColor",
                // Collection-specific
                "itemTemplate", "emptyState", "loadingState"
            ]

            let contentKeys = Set(content.keys)
            let unknownKeys = contentKeys.subtracting(validContentKeys)

            // Intentionally no-op: different component types have different
            // valid keys, so unknown keys are tolerated in structural validation.
            if !unknownKeys.isEmpty {
            }

            if let states = content["states"] as? [String: Any] {
                for (stateName, stateValue) in states {
                    guard stateValue is [String: Any] else {
                        return .failed(error: ValidationError("State '\(stateName)' is not an object"))
                    }
                }
            }

            if let triggers = content["triggers"] as? [String: Any] {
                let validTriggers: Set<String> = ["touchDown", "touchUp", "focus", "blur", "hover", "hoverEnd"]
                let triggerKeys = Set(triggers.keys)
                let unknownTriggers = triggerKeys.subtracting(validTriggers)

                if !unknownTriggers.isEmpty {
                    return .failed(error: ValidationError("Unknown triggers: \(unknownTriggers.sorted())"))
                }
            }
        }

        return .success(decodedAs: "Component (structural)")
    }

    /// Structural validation for action examples in documentation.
    private static func validateActionStructure(json: [String: Any]) -> ValidationResult {
        guard let actionType = json["type"] as? String else {
            return .failed(error: ValidationError("Action missing 'type' field"))
        }

        guard actionTypes.contains(actionType) else {
            return .failed(error: ValidationError("Unknown action type: '\(actionType)'"))
        }

        switch actionType {
        case "navigation":
            // A back navigation (`isBack`, optionally `toRoot`) carries no
            // `nextScreen` — it pops rather than navigating to a named screen.
            let isBack = (json["isBack"] as? Bool) == true
            if json["nextScreen"] == nil && !isBack {
                return .failed(error: ValidationError("navigation action missing 'nextScreen'"))
            }
        case "selectTab":
            if json["tabId"] == nil && json["tabIndex"] == nil {
                return .failed(error: ValidationError("selectTab action missing 'tabId' or 'tabIndex'"))
            }
        case "updateVariable", "incrementVariable", "toggleArrayValue":
            if json["variableName"] == nil {
                return .failed(error: ValidationError("\(actionType) action missing 'variableName'"))
            }
        case "updateMultipleVariables":
            if json["updates"] == nil {
                return .failed(error: ValidationError("updateMultipleVariables action missing 'updates'"))
            }
        case "setState":
            if json["stateName"] == nil {
                return .failed(error: ValidationError("setState action missing 'stateName'"))
            }
        case "focus":
            if json["target"] == nil {
                return .failed(error: ValidationError("focus action missing 'target'"))
            }
        case "executeFunction":
            if json["function"] == nil {
                return .failed(error: ValidationError("executeFunction action missing 'function'"))
            }
        case "completeFlow":
            if json["destination"] == nil {
                return .failed(error: ValidationError("completeFlow action missing 'destination'"))
            }
        default:
            // Actions like dismiss, focusNext, focusPrevious, dismissKeyboard have no required fields
            break
        }

        return .success(decodedAs: "Action (structural)")
    }

    struct ValidationError: Error, CustomStringConvertible {
        let message: String
        init(_ message: String) { self.message = message }
        var description: String { message }
    }
}
