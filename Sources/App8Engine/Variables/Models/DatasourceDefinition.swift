//
//  DatasourceDefinition.swift
//  App8Engine
//

import Foundation

/// Represents a parsed external datasource file
///
/// Supports two formats:
/// 1. Wrapped format: `{ "schema": {...}, "data": [...] }`
/// 2. Raw format: Just the data array/object directly `[...]` or `{...}`
public struct DatasourceDefinition: Codable, Sendable {
    /// Optional JSON Schema for validation (stored but not enforced)
    public let schema: JSONValue?

    /// The actual data (array or object)
    public let data: AnyCodableValue

    enum CodingKeys: String, CodingKey {
        case schema
        case data
    }

    public init(schema: JSONValue? = nil, data: Any) {
        self.schema = schema
        self.data = AnyCodableValue(value: data)
    }

    public init(from decoder: Decoder) throws {
        // Wrapped format: { "schema": ..., "data": ... }
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let dataValue = try? container.decode(AnyCodableValue.self, forKey: .data) {
            self.schema = try container.decodeIfPresent(JSONValue.self, forKey: .schema)
            self.data = dataValue
            return
        }

        // Raw format: array or object directly
        self.schema = nil
        self.data = try AnyCodableValue(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(schema, forKey: .schema)
        try container.encode(data, forKey: .data)
    }

    /// Get the raw data value
    public var rawData: Any {
        data.value
    }
}
