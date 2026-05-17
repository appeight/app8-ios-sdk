@propertyWrapper
public struct OptionallyCodable<T: Codable & OptionalType> {
    public var wrappedValue: T
    
    public init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }
}

extension OptionallyCodable: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try? decoder.singleValueContainer()
        self.wrappedValue = (try? container?.decode(T.self)) ?? T.nilValue
    }
}

extension OptionallyCodable: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension OptionallyCodable: Hashable & Equatable where T: Hashable & Equatable {
    public static func == (lhs: OptionallyCodable<T>, rhs: OptionallyCodable<T>) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}

public extension KeyedDecodingContainer {
    func decode<T>(_ type: OptionallyCodable<T>.Type, forKey key: Key) throws -> OptionallyCodable<T> where T: Codable & OptionalType {
        // Missing key, explicit null, or any decode failure all yield nilValue.
        if !contains(key) {
            return OptionallyCodable(wrappedValue: T.nilValue)
        }
        if try decodeNil(forKey: key) {
            return OptionallyCodable(wrappedValue: T.nilValue)
        }
        do {
            let value = try decode(T.self, forKey: key)
            return OptionallyCodable(wrappedValue: value)
        } catch {
            return OptionallyCodable(wrappedValue: T.nilValue)
        }
    }
}

public extension KeyedEncodingContainer {
    mutating func encode<T>(_ value: OptionallyCodable<T>, forKey key: Key) throws where T: Codable & OptionalType {
        try encode(value.wrappedValue, forKey: key)
    }
}
