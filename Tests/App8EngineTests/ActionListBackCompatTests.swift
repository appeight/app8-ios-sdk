//
//  ActionListBackCompatTests.swift
//  App8Engine
//
//  Lock in JSON backwards compatibility for the actions-shape change:
//  every `actions: { trigger: Action }` form must keep decoding alongside
//  the new `actions: { trigger: [Action, Action, ...] }` form.
//

import Foundation
import Testing
@testable import App8Engine

private struct ActionsWrapper: Decodable {
    let actions: [String: DSL.Model.ActionList]
}

private func decode(_ json: String) throws -> [String: [DSL.Model.Action]] {
    let data = json.data(using: .utf8)!
    let wrapper = try JSONDecoder().decode(ActionsWrapper.self, from: data)
    var out: [String: [DSL.Model.Action]] = [:]
    for (key, list) in wrapper.actions { out[key] = list.actions }
    return out
}

@Test
func singleActionObjectDecodesAsOneElementList() throws {
    let json = """
    { "actions": { "tap": { "type": "navigation", "nextScreen": "next" } } }
    """
    let decoded = try decode(json)
    let tap = try #require(decoded["tap"])
    #expect(tap.count == 1)
    #expect(tap.first?.type == .navigation)
    #expect(tap.first?.nextScreen == "next")
}

@Test
func actionArrayDecodesInJsonOrder() throws {
    let json = """
    {
        "actions": {
            "tap": [
                { "type": "emit", "name": "checkout.started" },
                { "type": "navigation", "nextScreen": "confirm" }
            ]
        }
    }
    """
    let decoded = try decode(json)
    let tap = try #require(decoded["tap"])
    #expect(tap.count == 2)
    #expect(tap[0].type == .emit)
    #expect(tap[0].name == "checkout.started")
    #expect(tap[1].type == .navigation)
    #expect(tap[1].nextScreen == "confirm")
}

@Test
func emptyActionArrayDecodes() throws {
    let json = """
    { "actions": { "tap": [] } }
    """
    let decoded = try decode(json)
    #expect(decoded["tap"]?.isEmpty == true)
}

@Test
func multipleTriggersCoexist() throws {
    let json = """
    {
        "actions": {
            "tap":        { "type": "haptic", "hapticStyle": "light" },
            "longPress":  [{ "type": "navigation", "nextScreen": "menu" }]
        }
    }
    """
    let decoded = try decode(json)
    #expect(decoded["tap"]?.first?.type == .haptic)
    #expect(decoded["longPress"]?.first?.type == .navigation)
}
