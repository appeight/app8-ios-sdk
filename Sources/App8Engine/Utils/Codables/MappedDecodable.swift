import Foundation

/// @MappedDecodable extracts a public Value from a Decodable bridge `C`.
@propertyWrapper
struct MappedDecodable<C: Decodable & MappedCodableBridge>: Decodable {
    public typealias Value = C.MappedValue

    private var storage: Value?
    private(set) var toValue: (C) -> Value = { $0[keyPath: C.mappedKeyPath] }

    public var wrappedValue: Value {
        get {
            guard let v = storage else {
                fatalError("MappedDecodable<\(C.self)> accessed before it was decoded or set.")
            }
            return v
        }
        set { storage = newValue }
    }

    // MARK: - Initializers for declaration-time usage

    /// Initialize with a concrete value (useful in tests or manual construction).
    public init(_ value: Value) {
        self.storage = value
    }

    /// Minimal initializer for: `@MappedDecodable(Bridge.self) var value: ...`
    public init(_ bridgeType: C.Type) {
        self.storage = nil
    }

    /// Optional initializer if you want to override the keyPath at the call site.
    public init(_ bridgeType: C.Type, _ keyPath: KeyPath<C, Value>) {
        self.storage = nil
        self.toValue = { $0[keyPath: keyPath] }
    }

    // MARK: - Decodable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let bridge = try container.decode(C.self)
        self.storage = toValue(bridge)
    }
}
