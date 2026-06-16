//
//  NewPropertyDecodingTests.swift
//  App8Engine
//

import Foundation
import Testing
@testable import App8Engine

// MARK: - ScrollView scrollThreshold

@Test
func scrollViewPropertiesDecodeWithThreshold() throws {
    let json = """
    { "direction": "vertical", "scrollThreshold": 120 }
    """
    let data = json.data(using: .utf8)!
    let props = try JSONDecoder().decode(DSL.Model.Component.ScrollView.Properties.self, from: data)
    #expect(props.scrollThreshold == 120)
    #expect(props.direction == .vertical)
}

@Test
func scrollViewPropertiesDecodeWithFractionalThreshold() throws {
    let json = """
    { "scrollThreshold": 44.5 }
    """
    let data = json.data(using: .utf8)!
    let props = try JSONDecoder().decode(DSL.Model.Component.ScrollView.Properties.self, from: data)
    #expect(props.scrollThreshold == 44.5)
}

@Test
func scrollViewPropertiesDecodeWithoutThreshold() throws {
    let json = """
    { "direction": "vertical" }
    """
    let data = json.data(using: .utf8)!
    let props = try JSONDecoder().decode(DSL.Model.Component.ScrollView.Properties.self, from: data)
    #expect(props.scrollThreshold == nil)
}

// MARK: - TextModel letterSpacing

@Test
func textModelDecodesFixedLetterSpacing() throws {
    let json = """
    { "fontSize": 16, "letterSpacing": { "type": "fixed", "value": 2.5 } }
    """
    let data = json.data(using: .utf8)!
    let model = try JSONDecoder().decode(DSL.Model.Style.TextModel.self, from: data)
    #expect(model.letterSpacing?.type == .fixed)
    #expect(model.letterSpacing?.value == 2.5)
}

@Test
func textModelDecodesNegativeLetterSpacing() throws {
    let json = """
    { "fontSize": 20, "letterSpacing": { "type": "fixed", "value": -0.5 } }
    """
    let data = json.data(using: .utf8)!
    let model = try JSONDecoder().decode(DSL.Model.Style.TextModel.self, from: data)
    #expect(model.letterSpacing?.value == -0.5)
}

@Test
func textModelDecodesBareNumberLetterSpacingAsFixed() throws {
    // Shorthand: a bare number is treated as fixed letter spacing in points.
    let json = """
    { "fontSize": 16, "letterSpacing": -1.5 }
    """
    let data = json.data(using: .utf8)!
    let model = try JSONDecoder().decode(DSL.Model.Style.TextModel.self, from: data)
    #expect(model.letterSpacing?.type == .fixed)
    #expect(model.letterSpacing?.value == -1.5)
}

@Test
func textModelDecodesIntegerLetterSpacingAsFixed() throws {
    let json = """
    { "fontSize": 16, "letterSpacing": 2 }
    """
    let data = json.data(using: .utf8)!
    let model = try JSONDecoder().decode(DSL.Model.Style.TextModel.self, from: data)
    #expect(model.letterSpacing?.type == .fixed)
    #expect(model.letterSpacing?.value == 2)
}

// MARK: - TextModel lineHeight

@Test
func textModelDecodesMultiplierLineHeight() throws {
    let json = """
    { "fontSize": 15, "lineHeight": { "type": "multiplier", "value": 1.4 } }
    """
    let data = json.data(using: .utf8)!
    let model = try JSONDecoder().decode(DSL.Model.Style.TextModel.self, from: data)
    #expect(model.lineHeight?.type == .multiplier)
    #expect(model.lineHeight?.value == 1.4)
}

@Test
func textModelDecodesFixedLineHeight() throws {
    let json = """
    { "fontSize": 15, "lineHeight": { "type": "fixed", "value": 24 } }
    """
    let data = json.data(using: .utf8)!
    let model = try JSONDecoder().decode(DSL.Model.Style.TextModel.self, from: data)
    #expect(model.lineHeight?.type == .fixed)
    #expect(model.lineHeight?.value == 24)
}

@Test
func textModelDecodesAllLineHeightTypes() throws {
    let types: [(String, DSL.Model.Style.TextModel.LineHeight.`Type`)] = [
        ("auto", .auto),
        ("multiplier", .multiplier),
        ("fontSizeFraction", .fontSizeFraction),
        ("fixed", .fixed),
        ("interLineSpacing", .interLineSpacing)
    ]
    for (rawType, expected) in types {
        let json = """
        { "fontSize": 15, "lineHeight": { "type": "\(rawType)", "value": 1.0 } }
        """
        let data = json.data(using: .utf8)!
        let model = try JSONDecoder().decode(DSL.Model.Style.TextModel.self, from: data)
        #expect(model.lineHeight?.type == expected)
    }
}

@Test
func textModelDecodesCombinedLetterSpacingAndLineHeight() throws {
    let json = """
    {
        "fontSize": 28, "fontWeight": "bold",
        "letterSpacing": { "type": "fixed", "value": -0.5 },
        "lineHeight": { "type": "multiplier", "value": 1.1 }
    }
    """
    let data = json.data(using: .utf8)!
    let model = try JSONDecoder().decode(DSL.Model.Style.TextModel.self, from: data)
    #expect(model.letterSpacing?.value == -0.5)
    #expect(model.lineHeight?.value == 1.1)
    #expect(model.lineHeight?.type == .multiplier)
}

@Test
func textModelDecodesWithoutLetterSpacingOrLineHeight() throws {
    let json = """
    { "fontSize": 14, "color": "#FFFFFF" }
    """
    let data = json.data(using: .utf8)!
    let model = try JSONDecoder().decode(DSL.Model.Style.TextModel.self, from: data)
    #expect(model.letterSpacing == nil)
    #expect(model.lineHeight == nil)
}

// MARK: - VariableContext overlay ($value for onTextChange, $crossed for scroll threshold)

@MainActor
@Test
func variableContextOverlaysOverrideStoreValues() throws {
    let store = VariableStore()
    try store.defineVariable(name: "name", definition: VariableDefinition(type: .string, initialValue: "Alice"))

    let base = VariableContext(store: store)
    #expect(base.getValue(for: "name") as? String == "Alice")

    let overlaid = base.overlaying("name", value: "Bob")
    #expect(overlaid.getValue(for: "name") as? String == "Bob")
    #expect(base.getValue(for: "name") as? String == "Alice", "Original context unchanged")
}

@MainActor
@Test
func variableContextOverlaysNewKey() throws {
    let store = VariableStore()
    try store.defineVariable(name: "query", definition: VariableDefinition(type: .string, initialValue: ""))

    let context = VariableContext(store: store).overlaying("$value", value: "new text")
    #expect(context.getValue(for: "$value") as? String == "new text")
    #expect(context.getValue(for: "query") as? String == "", "Store values still accessible")
}

@MainActor
@Test
func variableContextOverlaysBooleanAndNumbers() throws {
    let store = VariableStore()
    let context = VariableContext(store: store)
        .overlaying("$crossed", value: true)
        .overlaying("$offset", value: 120.5)

    #expect(context.getValue(for: "$crossed") as? Bool == true)
    #expect(context.getValue(for: "$offset") as? Double == 120.5)
}

@MainActor
@Test
func variableContextOverlayChainAccumulates() throws {
    let store = VariableStore()
    let context = VariableContext(store: store)
        .overlaying("a", value: 1)
        .overlaying("b", value: 2)
        .overlaying("c", value: 3)

    #expect(context.getValue(for: "a") as? Int == 1)
    #expect(context.getValue(for: "b") as? Int == 2)
    #expect(context.getValue(for: "c") as? Int == 3)
}
