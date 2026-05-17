//
//  CShapeModelTests.swift
//  App8Engine
//

import Foundation
import Testing
@testable import App8Engine

private func decodeShape(_ json: String) throws -> DSL.Model.Component.Shape.Properties {
    let data = json.data(using: .utf8)!
    let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: data)
    guard let entity: DSL.Model.Component.ConcreteEntity<DSL.Model.Component.Shape.C> = component.asConcreteEntity() else {
        Issue.record("Expected ConcreteEntity<Shape.C>")
        throw TestError.castFailed
    }
    return entity.content.properties
}

private enum TestError: Error { case castFailed }

private func shapeJSON(_ propertiesJSON: String) -> String {
    """
    {
        "type": "shape",
        "id": "test-shape",
        "content": {
            "properties": \(propertiesJSON),
            "layout": {}
        }
    }
    """
}

@Test
func shapeKindArcParsesProperties() throws {
    let json = shapeJSON("""
    {
        "kind": "arc",
        "progress": "{{p}}",
        "startAngle": -90,
        "lineWidth": 18,
        "lineCap": "round",
        "strokeColor": "#FF2D55",
        "trackColor": "#FF2D5533",
        "trackLineWidth": 14,
        "animationDuration": 1.0,
        "animationCurve": "easeOut"
    }
    """)

    let props = try decodeShape(json)
    #expect(props.kind == .arc)
    #expect(props.startAngle == -90)
    #expect(props.lineWidth == 18)
    #expect(props.lineCap == .round)
    #expect(props.strokeColor == "#FF2D55")
    #expect(props.trackColor == "#FF2D5533")
    #expect(props.trackLineWidth == 14)
    #expect(props.progress?.value == "{{p}}")
    #expect(props.animationDuration == 1.0)
    #expect(props.animationCurve == "easeOut")
    #expect(props.fillColor == nil)
}

@Test
func shapeKindBarParsesProperties() throws {
    let json = shapeJSON("""
    {
        "kind": "bar",
        "progress": "{{p}}",
        "lineWidth": 20,
        "lineCap": "round",
        "strokeColor": "#FF9500",
        "trackColor": "#FF950033"
    }
    """)

    let props = try decodeShape(json)
    #expect(props.kind == .bar)
    #expect(props.lineWidth == 20)
    #expect(props.lineCap == .round)
    #expect(props.strokeColor == "#FF9500")
    #expect(props.trackColor == "#FF950033")
    #expect(props.progress?.value == "{{p}}")
}

@Test
func shapeKindCircleWithFillColor() throws {
    let json = shapeJSON("""
    {
        "kind": "circle",
        "fillColor": "#30D158",
        "lineWidth": 0
    }
    """)

    let props = try decodeShape(json)
    #expect(props.kind == .circle)
    #expect(props.fillColor == "#30D158")
    #expect(props.lineWidth == 0)
    #expect(props.strokeColor == nil)
}

@Test
func shapeKindCircleAsRingWithProgress() throws {
    let json = shapeJSON("""
    {
        "kind": "circle",
        "strokeColor": "#30D158",
        "progress": "{{p}}"
    }
    """)

    let props = try decodeShape(json)
    #expect(props.kind == .circle)
    #expect(props.fillColor == nil)
    #expect(props.strokeColor == "#30D158")
    #expect(props.progress?.value == "{{p}}")
}

@Test
func shapeKindLineParsesProperties() throws {
    let json = shapeJSON("""
    {
        "kind": "line",
        "lineWidth": 1,
        "lineCap": "butt",
        "strokeColor": "#FFFFFF33"
    }
    """)

    let props = try decodeShape(json)
    #expect(props.kind == .line)
    #expect(props.lineWidth == 1)
    #expect(props.lineCap == .butt)
    #expect(props.strokeColor == "#FFFFFF33")
    #expect(props.trackColor == nil)
    #expect(props.progress == nil)
}

@Test
func shapeOptionalPropertiesAreNilWhenAbsent() throws {
    let json = shapeJSON("""
    { "kind": "arc" }
    """)

    let props = try decodeShape(json)
    #expect(props.kind == .arc)
    #expect(props.progress == nil)
    #expect(props.startAngle == nil)
    #expect(props.lineWidth == nil)
    #expect(props.lineCap == nil)
    #expect(props.strokeColor == nil)
    #expect(props.trackColor == nil)
    #expect(props.trackLineWidth == nil)
    #expect(props.animationDuration == nil)
    #expect(props.animationCurve == nil)
    #expect(props.fillColor == nil)
}

@Test
func shapeProgressLiteralPreservedAsString() throws {
    let json = shapeJSON("""
    {
        "kind": "arc",
        "progress": "0.75"
    }
    """)

    let props = try decodeShape(json)
    #expect(props.progress?.value == "0.75")
}

@Test
func shapeInvalidKindFailsDecoding() throws {
    let json = shapeJSON("""
    { "kind": "rectangle" }
    """)

    let data = json.data(using: .utf8)!
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(DSL.Model.Component.Any.self, from: data)
    }
}
