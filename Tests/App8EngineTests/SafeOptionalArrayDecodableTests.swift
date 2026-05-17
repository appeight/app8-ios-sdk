//
//  SafeOptionalArrayDecodableTests.swift
//  App8Engine
//

import Foundation
import Testing
@testable import App8Engine

// MARK: - Layout.constraints (missing key)

@Test
func layoutDecodesWhenConstraintsKeyMissing() throws {
    let json = """
    {
        "top": 0,
        "bottom": 0,
        "leading": 0,
        "trailing": 0
    }
    """
    let data = Data(json.utf8)
    let layout = try JSONDecoder().decode(DSL.Model.Layout.self, from: data)

    #expect(layout.constraints == nil)
}

@Test
func layoutDecodesWhenConstraintsKeyNull() throws {
    let json = """
    {
        "top": 0,
        "constraints": null
    }
    """
    let data = Data(json.utf8)
    let layout = try JSONDecoder().decode(DSL.Model.Layout.self, from: data)

    #expect(layout.constraints == nil)
}

@Test
func layoutDecodesWhenConstraintsPresent() throws {
    let json = """
    {
        "top": 0,
        "constraints": [
            {
                "type": "bottom",
                "target": "keyboard",
                "constant": 8
            }
        ]
    }
    """
    let data = Data(json.utf8)
    let layout = try JSONDecoder().decode(DSL.Model.Layout.self, from: data)

    #expect(layout.constraints?.count == 1)
    #expect(layout.constraints?.first?.type == .bottom)
}

@Test
func layoutDecodesWhenConstraintsEmpty() throws {
    let json = """
    {
        "leading": 0,
        "trailing": 0,
        "constraints": []
    }
    """
    let data = Data(json.utf8)
    let layout = try JSONDecoder().decode(DSL.Model.Layout.self, from: data)

    #expect(layout.constraints != nil)
    #expect(layout.constraints?.isEmpty == true)
}

// MARK: - DecodeErrorCollector must NOT record errors for missing optional arrays

@Test
func noCollectorErrorWhenConstraintsKeyMissing() throws {
    let json = """
    {
        "top": 0,
        "bottom": 0,
        "leading": 0,
        "trailing": 0
    }
    """
    let data = Data(json.utf8)

    let collector = DecodeErrorCollector()
    DecodeErrorCollector.current = collector

    let layout = try JSONDecoder().decode(DSL.Model.Layout.self, from: data)
    DecodeErrorCollector.current = nil

    #expect(layout.constraints == nil)
    #expect(collector.entries.isEmpty, "Missing optional array key should not produce collector errors")
}

// MARK: - Component without style key decodes without error

@Test
func componentWithoutStyleKeyDecodesCleanly() throws {
    let json = """
    {
        "type": "button",
        "id": "test-button",
        "content": {
            "properties": {
                "text": "Tap me"
            }
        }
    }
    """
    let data = Data(json.utf8)

    let collector = DecodeErrorCollector()
    DecodeErrorCollector.current = collector

    let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: data)
    DecodeErrorCollector.current = nil

    #expect(component.id == "test-button")
    #expect(collector.entries.isEmpty, "Missing style key should not produce collector errors")
}

@Test
func collectionWithoutStyleKeyDecodesCleanly() throws {
    let json = """
    {
        "type": "collection",
        "id": "test-collection",
        "content": {
            "layout": {
                "leading": 0,
                "trailing": 0
            },
            "properties": {
                "data": "{{items}}",
                "layout": {
                    "type": "vertical",
                    "itemSpacing": 10
                }
            }
        }
    }
    """
    let data = Data(json.utf8)

    let collector = DecodeErrorCollector()
    DecodeErrorCollector.current = collector

    let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: data)
    DecodeErrorCollector.current = nil

    #expect(component.id == "test-collection")
    #expect(collector.entries.isEmpty, "Missing style key on collection should not produce collector errors")
}

// MARK: - Component with layout (no constraints) decodes without error

@Test
func componentWithLayoutNoConstraintsDecodesCleanly() throws {
    let json = """
    {
        "type": "view",
        "id": "test-view",
        "content": {
            "properties": {},
            "style": {},
            "layout": {
                "top": 0,
                "bottom": 0,
                "leading": 0,
                "trailing": 0
            }
        }
    }
    """
    let data = Data(json.utf8)

    let collector = DecodeErrorCollector()
    DecodeErrorCollector.current = collector

    let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: data)
    DecodeErrorCollector.current = nil

    #expect(component.id == "test-view")
    #expect(collector.entries.isEmpty, "Layout without constraints key should not produce collector errors")
}
