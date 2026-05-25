//
//  AnalyticsBindingTests.swift
//  App8Engine
//
//  Cover the dual decode shape: shorthand `"tap": "name"` and full form
//  `"tap": { "name": "...", "properties": {...} }`.
//

import Foundation
import Testing
@testable import App8Engine

private func decode(_ json: String) throws -> DSL.Model.AnalyticsBinding {
    let data = json.data(using: .utf8)!
    return try JSONDecoder().decode(DSL.Model.AnalyticsBinding.self, from: data)
}

@Test
func shorthandDecodesNameOnly() throws {
    let binding = try decode("\"stripeConnectClicked\"")
    #expect(binding.name == "stripeConnectClicked")
    #expect(binding.properties == nil)
}

@Test
func fullFormDecodesNameAndProperties() throws {
    let json = """
    {
        "name": "userCardClicked",
        "properties": {
            "displayName": "{{name}}",
            "followers": 42
        }
    }
    """
    let binding = try decode(json)
    #expect(binding.name == "userCardClicked")
    let props = try #require(binding.properties)
    #expect(props["displayName"]?.value as? String == "{{name}}")
    #expect(props["followers"]?.value as? Int == 42)
}

@Test
func fullFormWithoutPropertiesDecodes() throws {
    let json = "{ \"name\": \"simpleEvent\" }"
    let binding = try decode(json)
    #expect(binding.name == "simpleEvent")
    #expect(binding.properties == nil)
}

@Test
func malformedShapeThrows() {
    // Numeric in the shorthand position isn't a valid binding; full form
    // requires `name` to be a string.
    let json = "{ \"name\": 123 }"
    #expect(throws: DecodingError.self) {
        _ = try decode(json)
    }
}
