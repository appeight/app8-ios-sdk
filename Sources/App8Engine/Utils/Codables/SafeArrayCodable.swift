@propertyWrapper
struct SafeArrayCodable<T: Codable>: Codable, ArrayWrapper {
    var wrappedValue: [T]

    init(wrappedValue: [T]) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        self.wrappedValue = try Self.decodeArray(type: T.self, decoder: decoder)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for item in wrappedValue {
            try container.encode(item)
        }
    }
}

@propertyWrapper
struct SafeArrayDecodable<T: Decodable & Sendable>: Decodable, ArrayWrapper, Sendable {

    var wrappedValue: [T]

    init(wrappedValue: [T]) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        do {
            wrappedValue = try Self.decodeArray(type: T.self, decoder: decoder)
        } catch {
            (decoder.userInfo[.app8Logger] as? A8Log)?.warning("SafeArrayDecodable failure, assign empty: \(error)")
            wrappedValue = []
        }
    }
}

@propertyWrapper
struct SafeOptionalArrayDecodable<T: Decodable & Sendable>: Decodable, ArrayWrapper {
    var wrappedValue: [T]?

    init(wrappedValue: [T]?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        self.wrappedValue = try? Self.decodeArray(type: T.self, decoder: decoder)
    }
}


/// Swift's synthesized Decodable uses `container.decode(_:forKey:)` for property-wrapper
/// backing storage. A missing JSON key throws `keyNotFound` before the wrapper's `init(from:)`
/// can run. These overloads convert the call to `decodeIfPresent`, so a missing key yields
/// an empty array (SafeArrayDecodable) or nil (SafeOptionalArrayDecodable).
extension KeyedDecodingContainer {
    func decode<T>(
        _ type: SafeArrayDecodable<T>.Type,
        forKey key: Key
    ) throws -> SafeArrayDecodable<T> {
        try decodeIfPresent(type, forKey: key) ?? SafeArrayDecodable<T>(wrappedValue: [])
    }

    func decode<T>(
        _ type: SafeOptionalArrayDecodable<T>.Type,
        forKey key: Key
    ) throws -> SafeOptionalArrayDecodable<T> {
        try decodeIfPresent(type, forKey: key) ?? SafeOptionalArrayDecodable<T>(wrappedValue: nil)
    }
}

private protocol ArrayWrapper {
    static func decodeArray<T: Decodable>(type: T.Type, decoder: Decoder) throws -> [T]
}

extension ArrayWrapper {

    static func decodeArray<T: Decodable>(type: T.Type, decoder: Decoder) throws -> [T] {
        if let container = try? decoder.singleValueContainer() {
            let decodedElements = try container.decode([FailableDecodable<T>].self).resolve()
            return decodedElements
        } else {
            var container = try decoder.unkeyedContainer()
            let decodedElements = try container.decode([FailableDecodable<T>].self).resolve()
            return decodedElements
        }
    }
}

extension SafeArrayDecodable: Equatable where T: Equatable {
    static func == (lhs: SafeArrayDecodable<T>, rhs: SafeArrayDecodable<T>) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

extension SafeArrayDecodable: Hashable where T: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}
