//
//  GesturesGlassGeometryTests.swift
//  App8EngineTests
//
//  Covers the generic primitives that let custom controls (e.g. a vertical
//  glass slider) be composed without a bespoke component:
//   • `gestures.pan` binding model
//   • reserved `view.*` geometry in expressions
//   • container-glass + capsule-corner style decoding
//

import Foundation
import Testing
@testable import App8Engine

// MARK: - Helpers

private func decodeComponent<C: DSL.Model.Component.EntityContent>(_ json: String, as type: C.Type) throws -> C {
    let data = json.data(using: .utf8)!
    let component = try JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: data)
    guard let entity: DSL.Model.Component.ConcreteEntity<C> = component.asConcreteEntity() else {
        throw DecodingError.typeMismatch(C.self, .init(codingPath: [], debugDescription: "wrong content type"))
    }
    return entity.content
}

// MARK: - gestures.pan model

@Test
func gesturesPanDecodesAllBindings() throws {
    let json = """
    { "id": "v",
      "type": "view",
      "content": {
        "gestures": { "pan": {
          "translationX": "tx", "translationY": "ty",
          "velocityX": "vx", "velocityY": "vy",
          "locationX": "lx", "locationY": "ly"
        } }
      }
    }
    """
    let content = try decodeComponent(json, as: DSL.Model.Component.View.C.self)
    let pan = try #require(content.gestures?.pan)
    #expect(pan.translationX == "tx")
    #expect(pan.translationY == "ty")
    #expect(pan.velocityX == "vx")
    #expect(pan.velocityY == "vy")
    #expect(pan.locationX == "lx")
    #expect(pan.locationY == "ly")
    #expect(pan.hasBindings == true)
}

@Test
func gesturesPanPartialBindings() throws {
    let json = """
    { "id": "v", "type": "view", "content": { "gestures": { "pan": { "locationY": "dragY" } } } }
    """
    let content = try decodeComponent(json, as: DSL.Model.Component.View.C.self)
    let pan = try #require(content.gestures?.pan)
    #expect(pan.locationY == "dragY")
    #expect(pan.translationX == nil)
    #expect(pan.hasBindings == true)
}

@Test
func gesturesAbsentByDefault() throws {
    let json = """
    { "id": "v", "type": "view", "content": { "properties": {} } }
    """
    let content = try decodeComponent(json, as: DSL.Model.Component.View.C.self)
    #expect(content.gestures == nil)
}

// MARK: - view.* geometry in expressions

@MainActor
@Test
func viewGeometryResolvesInExpressions() throws {
    let store = VariableStore()
    let context = VariableContext(store: store).overlaying("view", value: [
        "width": 90.0, "height": 200.0, "centerX": 45.0, "centerY": 100.0
    ])
    let parser = ExpressionParser()
    let evaluator = ExpressionEvaluator()
    func eval(_ s: String) throws -> Double? {
        let v = try evaluator.evaluate(try parser.parse(s), context: context)
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }
    #expect(try eval("view.height") == 200.0)
    #expect(try eval("view.width") == 90.0)
    #expect(try eval("view.width * 0.5") == 45.0)
    #expect(try eval("view.height - 24") == 176.0)
}

@MainActor
@Test
func brightnessMappingExpressionClampsAndMaps() throws {
    let store = VariableStore()
    try store.defineVariable(name: "dragY", definition: VariableDefinition(type: .number, initialValue: 100))
    let parser = ExpressionParser()
    let evaluator = ExpressionEvaluator()
    let expr = "max(0, min(100, (200 - dragY) / 2))"
    func brightness(forDragY y: Double) throws -> Double? {
        try store.setValue(name: "dragY", value: y)
        let v = try evaluator.evaluate(try parser.parse(expr), context: VariableContext(store: store))
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }
    #expect(try brightness(forDragY: 100) == 50.0)   // middle
    #expect(try brightness(forDragY: 0) == 100.0)    // top = brightest
    #expect(try brightness(forDragY: 200) == 0.0)    // bottom = darkest
    #expect(try brightness(forDragY: -20) == 100.0)  // above top → clamped
    #expect(try brightness(forDragY: 260) == 0.0)    // below bottom → clamped
}

// MARK: - container glass + capsule corner styles

@Test
func visualEffectContainerGlassDecodes() throws {
    let json = """
    { "glass": "normal", "container": true }
    """
    let ve = try JSONDecoder().decode(DSL.Model.Style.VisualEffect.self, from: json.data(using: .utf8)!)
    #expect(ve.glass == .normal)
    #expect(ve.container == true)
}

@Test
func visualEffectContainerDefaultsNil() throws {
    let json = """
    { "glass": "normal" }
    """
    let ve = try JSONDecoder().decode(DSL.Model.Style.VisualEffect.self, from: json.data(using: .utf8)!)
    #expect(ve.container == nil)
}

@Test
func cornerCapsuleShorthandDecodes() throws {
    let json = """
    { "radius": "capsule", "curve": "continuous" }
    """
    let corner = try JSONDecoder().decode(DSL.Model.Style.Corner.self, from: json.data(using: .utf8)!)
    if case .capsule = corner.radius {} else { Issue.record("expected .capsule, got \(corner.radius)") }
    // Capsule resolves to half the smaller dimension.
    #expect(corner.resolvedRadius(in: CGSize(width: 90, height: 200)) == 45)
    #expect(corner.radius.isRelative == true)
}

@Test
func cornerCapsuleKeyedDecodes() throws {
    let json = """
    { "radius": { "type": "capsule" } }
    """
    let corner = try JSONDecoder().decode(DSL.Model.Style.Corner.self, from: json.data(using: .utf8)!)
    if case .capsule = corner.radius {} else { Issue.record("expected .capsule, got \(corner.radius)") }
}
