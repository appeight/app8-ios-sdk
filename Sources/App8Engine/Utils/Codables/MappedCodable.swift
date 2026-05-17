import Foundation

/// A bridge a.k.a. “wire type” that is Codable and knows how to:
/// - extract the public Value (via a static keyPath),
/// - be initialized back from that Value (for encoding).
protocol MappedCodableBridge {
    associatedtype MappedValue: Sendable
    /// Where to read the public value from the bridge
    static var mappedKeyPath: KeyPath<Self, MappedValue> { get }
    /// How to build the bridge back from the public value (for encoding)
    init(_ mappedValue: MappedValue)
}

@propertyWrapper
struct MappedCodable<C: Codable & MappedCodableBridge>: Codable {
    public typealias Value = C.MappedValue

    // We keep it optional until decode (or manual assignment) provides it.
    private var storage: Value?
    private(set) var toValue: (C) -> Value = { $0[keyPath: C.mappedKeyPath] }

    // Expose the value; trap if accessed too early to surface mistakes fast.
    public var wrappedValue: Value {
        get {
            guard let v = storage else {
                fatalError("MappedCodable<\(C.self)> accessed before it was decoded or set.")
            }
            return v
        }
        set { storage = newValue }
    }

    // MARK: - Initializers for declaration-time usage

    public init(_ value: Value) {
        self.storage = value
    }

    /// Minimal initializer for: `@MappedCodable(Bridge.self) var value: ...`
    public init(_ bridgeType: C.Type) {
        self.storage = nil
    }

    /// Optional initializer if you want to override the keyPath at the call site.
    public init(_ bridgeType: C.Type, _ keyPath: KeyPath<C, Value>) {
        self.storage = nil
        self.toValue = { $0[keyPath: keyPath] }
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let bridge = try container.decode(C.self)
        self.storage = toValue(bridge)
    }

    public func encode(to encoder: Encoder) throws {
        guard let value = storage else {
            throw EncodingError.invalidValue(
                C.self,
                .init(codingPath: encoder.codingPath,
                      debugDescription: "MappedCodable<\(C.self)> has no value to encode.")
            )
        }

        var container = encoder.singleValueContainer()
        try container.encode(C(value))
    }
}

// Lift conformance through Optional when the wrapped type already conforms.
extension Optional: MappedCodableBridge where Wrapped: MappedCodableBridge {
    typealias MappedValue = Wrapped.MappedValue?

    // Provide a property to point the key path at
    var mappedValue: Wrapped.MappedValue? {
        switch self {
        case .some(let wrapped):
            return wrapped[keyPath: Wrapped.mappedKeyPath]
        case .none:
            return nil
        }
    }

    static var mappedKeyPath: KeyPath<Optional<Wrapped>, MappedValue> {
        \.mappedValue
    }

    init(_ mappedValue: MappedValue) {
        if let mv = mappedValue {
            self = .some(Wrapped(mv))
        } else {
            self = .none
        }
    }
}
