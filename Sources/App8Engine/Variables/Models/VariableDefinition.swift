//
//  VariableDefinition.swift
//  App8Engine
//

import Foundation

/// Preview hint for standalone screen rendering — never used in production navigation flows
public struct VariablePreview: Codable, Sendable {
    /// Datasource path to pick an item from (e.g. "datasources/listings")
    public let source: String?
    /// Index into the datasource data array (default: 0)
    public let index: Int?
    /// Literal sample value to inject when no datasource is available
    public let value: AnyCodableValue?

    public init(source: String? = nil, index: Int? = nil, value: Any? = nil) {
        self.source = source
        self.index = index
        self.value = value.map { AnyCodableValue(value: $0) }
    }
}

/// Definition of a variable from JSON DSL
public struct VariableDefinition: Codable, Sendable {
    public let type: VariableType
    public let initialValue: AnyCodableValue?
    public let computed: String?
    /// External datasource reference (e.g., "datasources/listings")
    public let source: String?
    /// When true, the engine subscribes to streamDatasource() for live updates
    public let streaming: Bool?
    /// Datasource path whose item schema this variable conforms to (e.g. "datasources/listings")
    /// Documents the expected shape for object variables passed as nav params
    public let schema: String?
    /// Sample value hint used only during standalone renderScreen() calls
    public let preview: VariablePreview?

    enum CodingKeys: String, CodingKey {
        case type
        case initialValue
        case computed
        case source
        case streaming
        case schema
        case preview
    }

    public init(type: VariableType, initialValue: Any? = nil, computed: String? = nil, source: String? = nil, streaming: Bool? = nil, schema: String? = nil, preview: VariablePreview? = nil) {
        self.type = type
        self.initialValue = initialValue.map { AnyCodableValue(value: $0) }
        self.computed = computed
        self.source = source
        self.streaming = streaming
        self.schema = schema
        self.preview = preview
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(VariableType.self, forKey: .type)
        computed = try container.decodeIfPresent(String.self, forKey: .computed)
        initialValue = try container.decodeIfPresent(AnyCodableValue.self, forKey: .initialValue)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        streaming = try container.decodeIfPresent(Bool.self, forKey: .streaming)
        schema = try container.decodeIfPresent(String.self, forKey: .schema)
        preview = try container.decodeIfPresent(VariablePreview.self, forKey: .preview)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(computed, forKey: .computed)
        try container.encodeIfPresent(initialValue, forKey: .initialValue)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(streaming, forKey: .streaming)
        try container.encodeIfPresent(schema, forKey: .schema)
        try container.encodeIfPresent(preview, forKey: .preview)
    }

    /// Get the raw initial value
    public var rawInitialValue: Any? {
        return initialValue?.value
    }

    /// Returns true if this variable references an external datasource
    public var hasExternalSource: Bool {
        source != nil
    }

    /// Returns true if this variable has live streaming enabled
    public var isStreaming: Bool {
        streaming == true
    }

    /// Create a copy with resolved initialValue (used after datasource loading)
    public func withResolvedValue(_ value: Any) -> VariableDefinition {
        VariableDefinition(type: type, initialValue: value, computed: computed, source: nil, streaming: streaming, schema: schema, preview: preview)
    }
}

/// Helper type for encoding/decoding Any values
/// Note: @unchecked Sendable because Any cannot conform to Sendable,
/// but values stored are JSON primitives which are safe to send across threads
public struct AnyCodableValue: Codable, @unchecked Sendable {
    public let value: Any

    public init(value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodableValue].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodableValue].self) {
            value = dictionary.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodableValue(value: $0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodableValue(value: $0) })
        case is NSNull:
            try container.encodeNil()
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Cannot encode value of type \(Swift.type(of: value))"
                )
            )
        }
    }
}
