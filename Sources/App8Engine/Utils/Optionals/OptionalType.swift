public protocol AnyOptional {
    var isNil: Bool { get }
    var isNotNil: Bool { get }
    mutating func setNil()
}

public protocol OptionalType: AnyOptional {
    associatedtype Wrapped
    var optional: Wrapped? { get }
    static var nilValue: Self { get }
    init(optional: Wrapped?)
}

extension Optional: OptionalType {
    public var optional: Wrapped? { return self }
    public var isNil: Bool {
        if let wrapped = optional, let innerOptional = wrapped as? (any OptionalType) {
            return innerOptional.isNil
        } else {
            return optional == nil
        }
    }
    public var isNotNil: Bool { !isNil }
    
    public static var nilValue: Self { return Self<Wrapped>.none }
    
    public init(optional: Wrapped?) {
        if let optional {
            self.init(optional)
        } else {
            self.init(nilLiteral: ())
        }
    }
    
    public mutating func setNil() {
        self = .none
    }
}
