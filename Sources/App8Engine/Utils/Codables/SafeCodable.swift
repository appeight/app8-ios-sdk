@propertyWrapper
public struct SafeCodable<T: Codable>: Codable where T: DefaultValueProvider {

    public var wrappedValue: T

    public init() {
        self.wrappedValue = T.defaultValue
    }

    public init(defaultValue: T) {
        self.wrappedValue = defaultValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.wrappedValue =
            (try? container.decode(T.self)) ?? T.defaultValue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

public protocol DefaultValueProvider {
    static var defaultValue: Self { get }
}
