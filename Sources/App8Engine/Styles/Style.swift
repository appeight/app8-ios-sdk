import Foundation

extension DSL.Model {

    struct Style {

        protocol `Protocol`: Decodable, Sendable, Identifiable where ID == String {
            var type: SType { get }
        }

        protocol StylePointerResolvable {
            func isResolved() -> Bool
            mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?)
            /// Returns the IDs of style pointers that could not be resolved.
            func unresolvedPointerIds() -> [String]
        }
        
        struct Pointer: Protocol {
            let id: String
            let type: SType
            /// `false` when `"type"` was omitted from JSON (type is `.custom("")` sentinel in that case)
            let typeSpecified: Bool

            private enum CodingKeys: String, CodingKey { case id, type }

            init(id: String, type: SType, typeSpecified: Bool) {
                self.id = id
                self.type = type
                self.typeSpecified = typeSpecified
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(String.self, forKey: .id)
                if let t = try container.decodeIfPresent(SType.self, forKey: .type) {
                    type = t
                    typeSpecified = true
                } else {
                    type = .custom("")
                    typeSpecified = false
                }
            }
        }
        
        protocol Entity: Protocol {
            associatedtype Content: Decodable
            var type: SType { get }
            var content: Content { get set }
        }

        struct ConcreteEntity<Content: Decodable & Sendable>: Entity {
            let id: String
            let type: SType
            var content: Content
            
            init(_ pointer: Pointer, content: Content) {
                id = pointer.id
                type = pointer.type
                self.content = content
            }
        }
        
        enum SType: Decodable, Equatable {
            case key(Key), custom(String)

            enum Key: String, Codable {
                // materials
                case fill, outline, shadow, corner, visualEffect, material
                // primitives
                case color, gradient
                // typography
                case text, font
                // components
                case view, image, icon, video
            }
            
            func isKeyed(_ key: Key) -> Bool {
                if case .key(let k) = self, k == key {
                    return true
                }
                return false
            }
            
            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                let stringValue = try container.decode(String.self)
                if let key = Key(rawValue: stringValue) {
                    self = .key(key)
                } else {
                    self = .custom(stringValue)
                }
            }
        }
    }
}

extension DSL.Model.Style.StylePointerResolvable {
    func unresolvedPointerIds() -> [String] { [] }
}

extension DSL.Model.Style.`Protocol` {
    static var materialTypes: Set<DSL.Model.Style.SType.Key> {
        return [.fill, .outline, .shadow, .corner, .visualEffect, .material]
    }

    var isMaterial: Bool {
        switch type {
        case .key(let key):
            return Self.materialTypes.contains(key)
        default:
            return false
        }
    }
}

extension DSL.Model.Style.Entity {

    @discardableResult
    mutating func setContent(_ content: any Decodable) -> Bool {
        if let content = content as? Content {
            self.content = content
            return true
        }
        return false
    }
}

// MARK: Type-erased

extension DSL.Model.Style {

    /// Type-erased wrapper to decode `any Protocol`.
    struct `Any`: `Protocol`, StylePointerResolvable {
        private(set) var base: any `Protocol`

        // Forwarded conformance
        var id: String { base.id }
        var type: SType { base.type }
        private(set) var jsonStringRepresentation: String?

        private enum CodingKeys: String, CodingKey {
            case id, type, content
        }

        init(from decoder: any Decoder) throws {
            jsonStringRepresentation = (try? RawJSON(from: decoder))?.string

            let container = try decoder.container(keyedBy: CodingKeys.self)
            let t = try container.decodeIfPresent(SType.self, forKey: .type)

            // Determine whether `content` exists and is non-nil
            let hasNonNilContent: Bool = {
                guard container.contains(.content) else { return false }
                return (try? !container.decodeNil(forKey: .content)) ?? false
            }()

            // If no content (missing or null) → Pointer
            guard hasNonNilContent else {
                let id = try container.decode(String.self, forKey: .id)
                if let t = t {
                    self.base = Pointer(id: id, type: t, typeSpecified: true)
                } else {
                    self.base = Pointer(id: id, type: .custom(""), typeSpecified: false)
                }
                return
            }

            // Content present — type is required as discriminator
            guard let t = t else {
                throw DecodingError.keyNotFound(
                    CodingKeys.type,
                    .init(codingPath: container.codingPath,
                          debugDescription: "Style with 'content' requires a 'type' field")
                )
            }

            // Otherwise decode the concrete entity for the discriminator
            switch t {
            case .key(.fill):
                self.base = try ConcreteEntity<Fill>(from: decoder)
            case .key(.color):
                self.base = try ConcreteEntity<Color.Themed>(from: decoder)
            case .key(.gradient):
                self.base = try ConcreteEntity<Gradient>(from: decoder)
            case .key(.outline):
                self.base = try ConcreteEntity<Outline>(from: decoder)
            case .key(.shadow):
                self.base = try ConcreteEntity<Shadow>(from: decoder)
            case .key(.corner):
                self.base = try ConcreteEntity<Corner>(from: decoder)
            case .key(.visualEffect):
                self.base = try ConcreteEntity<VisualEffect>(from: decoder)
            case .key(.material):
                self.base = try ConcreteEntity<Material>(from: decoder)
            case .key(.text):
                self.base = try ConcreteEntity<TextModel>(from: decoder)
            case .key(.font):
                self.base = try ConcreteEntity<Font>(from: decoder)
            case .key(.view):
                self.base = try ConcreteEntity<View>(from: decoder)
            case .key(.image):
                self.base = try ConcreteEntity<Image>(from: decoder)
            case .key(.video):
                self.base = try ConcreteEntity<Video>(from: decoder)
            case .key(.icon):
                self.base = try ConcreteEntity<Icon>(from: decoder)
            case .custom(let customType):
                // Content present with a custom discriminator — unsupported. (Custom pointers without content are handled above.)
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "Unsupported custom SType with content: \(customType)"
                ))
            }
        }
        
        init<Content: Decodable & Sendable>(_ concreteEntity: ConcreteEntity<Content>) {
            base = concreteEntity
        }
        
        func asConcreteEntity<Content: Decodable & Sendable>() -> ConcreteEntity<Content>? {
            return base as? ConcreteEntity<Content>
        }

        func asEntity() -> (any Entity)? {
            return base as? (any Entity)
        }

        func asPointer() -> Pointer? {
            return base as? Pointer
        }

        mutating func patchBase(_ base: any `Protocol`) {
            self.base = base
        }

        mutating func resolveStylePointers(resolver: (String) -> (any Entity)?) {
            if let pointer = asPointer(),
               var resolved = resolver(pointer.id) {
                if var furtherResolvable = resolved as? (any Entity & StylePointerResolvable) {
                    furtherResolvable.resolveStylePointers(resolver: resolver)
                    resolved = furtherResolvable
                }
                base = resolved
                
            } else if
                var entity = asEntity(),
                var resolved = entity.content as? (Decodable & StylePointerResolvable) {
                resolved.resolveStylePointers(resolver: resolver)
                entity.setContent(resolved)
                base = entity
            }
        }
        
        func isResolved() -> Bool {
            guard let entity = asEntity() else {
                return false
            }
            if let resolvable = entity.content as? StylePointerResolvable {
                return resolvable.isResolved()
            }
            return true
        }

        /// Returns the IDs of style pointers that could not be resolved.
        func unresolvedPointerIds() -> [String] {
            if let pointer = asPointer() {
                return [pointer.id]
            }
            guard let entity = asEntity(),
                  let resolvable = entity.content as? StylePointerResolvable else {
                return []
            }
            return resolvable.unresolvedPointerIds()
        }
    }
}

extension DSL.Model.Style {

    /// Holds either a pointer or a resolved entity.
    @propertyWrapper
    struct Wrapped<T: Decodable & Sendable>: Decodable {
        private(set) var base: `Any`?
        private(set) var directValue: T?

        var wrappedValue: T? {
            if let directValue { return directValue }
            let concreteEntity: ConcreteEntity<T>? = base?.asConcreteEntity()
            return concreteEntity?.content
        }

        init(base: `Any`? = nil) {
            self.base = base
            self.directValue = nil
        }

        static var none: Self { .init() }

        init(from decoder: any Decoder) throws {
            if let styleAny = try? `Any`(from: decoder) {
                base = styleAny
                directValue = nil
            } else if T.self is any OptionalType {
                base = nil
                directValue = try? T(from: decoder)
            } else {
                base = nil
                directValue = try T(from: decoder)
            }
        }
        
        /// Returns the unresolved pointer ID if this wrapped field still holds a pointer, or recurses into resolved content.
        func unresolvedPointerIds() -> [String] {
            if let pointer = base?.asPointer() {
                return [pointer.id]
            }
            if let entity = base?.asEntity(),
               let resolvable = entity.content as? StylePointerResolvable {
                return resolvable.unresolvedPointerIds()
            }
            return []
        }

        mutating func resolvePointer(type: SType, resolver: (String) -> (any DSL.Model.Style.Entity)?) {
            if let pointer = base?.asPointer(),
               (!pointer.typeSpecified || pointer.type == type),
               let resolved = resolver(pointer.id) {
                // Must explicitly unwrap and reassign - optional chaining with mutating methods on structs doesn't persist the mutation
                if var unwrapped = base {
                    unwrapped.patchBase(resolved)
                    // Recursively resolve nested pointers within the resolved entity
                    unwrapped.resolveStylePointers(resolver: resolver)
                    base = unwrapped
                }
            } else if
                var entity = base?.asEntity(),
                var resolved = entity.content as? (Decodable & StylePointerResolvable) {
                resolved.resolveStylePointers(resolver: resolver)
                entity.setContent(resolved)
                if var unwrapped = base {
                    unwrapped.patchBase(entity)
                    base = unwrapped
                }
            }
        }
    }
}

/// https://forums.swift.org/t/propertywrapper-decoding-behaviour/61076/2
extension KeyedDecodingContainer {
    func decode<T>(_ type: DSL.Model.Style.Wrapped<T>.Type, forKey key: Key) throws -> DSL.Model.Style.Wrapped<T> {
        try decodeIfPresent(type, forKey: key) ?? DSL.Model.Style.Wrapped<T>(base: nil)
    }
}
