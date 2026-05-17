import Foundation

/// @MappedEncodable builds an Encodable bridge `C` from a public Value when encoding.
@propertyWrapper
struct MappedEncodable<C: Encodable & MappedCodableBridge>: Encodable {
    public typealias Value = C.MappedValue

    private var storage: Value?

    public var wrappedValue: Value {
        get {
            guard let v = storage else {
                fatalError("MappedEncodable<\(C.self)> accessed before it was set.")
            }
            return v
        }
        set { storage = newValue }
    }

    // MARK: - Initializers for declaration-time usage

    /// Initialize with a concrete value (recommended so encoding won’t throw).
    public init(_ value: Value) {
        self.storage = value
    }

    /// Minimal initializer for: `@MappedEncodable(Bridge.self) var value: ...`
    /// You must assign before encoding, otherwise encoding throws.
    public init(_ bridgeType: C.Type) {
        self.storage = nil
    }

    // MARK: - Encodable

    public func encode(to encoder: Encoder) throws {
        guard let value = storage else {
            throw EncodingError.invalidValue(
                C.self,
                .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "MappedEncodable<\(C.self)> has no value to encode."
                )
            )
        }

        var container = encoder.singleValueContainer()
        try container.encode(C(value))
    }
}
