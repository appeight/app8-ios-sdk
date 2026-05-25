//
//  EmitActionTests.swift
//  App8Engine
//
//  Verify the `.emit` action decodes name + payload correctly and that the
//  payload preserves heterogeneous scalar values.
//

import Foundation
import Testing
@testable import App8Engine

private func decodeAction(_ json: String) throws -> DSL.Model.Action {
    let data = json.data(using: .utf8)!
    return try JSONDecoder().decode(DSL.Model.Action.self, from: data)
}

@Test
func emitDecodesNameOnly() throws {
    let json = """
    { "type": "emit", "name": "connect.tapped" }
    """
    let action = try decodeAction(json)
    #expect(action.type == .emit)
    #expect(action.name == "connect.tapped")
    #expect(action.payload == nil)
}

@Test
func emitDecodesWithPayload() throws {
    let json = """
    {
        "type": "emit",
        "name": "user.selected",
        "payload": {
            "displayName": "{{name}}",
            "followers": 1024,
            "verified": true
        }
    }
    """
    let action = try decodeAction(json)
    #expect(action.type == .emit)
    #expect(action.name == "user.selected")
    let payload = try #require(action.payload)
    #expect(payload["displayName"]?.value as? String == "{{name}}")
    #expect(payload["followers"]?.value as? Int == 1024)
    #expect(payload["verified"]?.value as? Bool == true)
}

@Test
func emitWithEmptyPayloadDecodes() throws {
    let json = """
    { "type": "emit", "name": "foo.bar", "payload": {} }
    """
    let action = try decodeAction(json)
    let payload = try #require(action.payload)
    #expect(payload.isEmpty)
}

@Test
func emitMissingNameStillDecodesButNameIsNil() throws {
    // Decoder accepts this; the engine's dispatch site is responsible for
    // dropping it with a warning (CBaseViewModel `.emit` case).
    let json = """
    { "type": "emit" }
    """
    let action = try decodeAction(json)
    #expect(action.type == .emit)
    #expect(action.name == nil)
}
