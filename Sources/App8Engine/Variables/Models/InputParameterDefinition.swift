//
//  InputParameterDefinition.swift
//  App8Engine
//

import Foundation

/// Definition for an input parameter that a screen can receive
public struct InputParameterDefinition: Codable, Sendable {
    /// The expected type of the parameter
    public let type: VariableType

    /// Whether this parameter is required
    public let required: Bool

    /// Default value if not provided (only valid when required is false)
    public let defaultValue: AnyCodableValue?

    public init(type: VariableType, required: Bool = true, defaultValue: AnyCodableValue? = nil) {
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
    }

    enum CodingKeys: String, CodingKey {
        case type
        case required
        case defaultValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(VariableType.self, forKey: .type)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? true
        defaultValue = try container.decodeIfPresent(AnyCodableValue.self, forKey: .defaultValue)
    }
}
