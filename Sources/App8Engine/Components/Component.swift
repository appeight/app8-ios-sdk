import Foundation

extension DSL.Model {
    
    struct Component {
        
        protocol `Protocol`: Node, Identifiable where ID == String {
            var templateId: String? { get }
            var type: CType { get }
        }
        
        struct Pointer: Protocol {
            let templateId: String?
            let id: String
            let type: CType
        }
        
        protocol TemplatePointerResolvable {
            mutating func resolveTemplatePointers(using resolver: TemplateResolver)
        }
        
        protocol EntityContent: Decodable, StyleHolder, LayoutHolder, PropertiesHolder, ActionsHolder, ChildrenHolder {
            mutating func resolveStateStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?)
        }
        
        protocol Entity: Protocol {
            associatedtype Content: EntityContent
            var type: CType { get }
            var content: Content { get set }
        }
        
        struct ConcreteEntity<Content: EntityContent>: Entity {
            let templateId: String?
            let id: String
            let type: CType
            var content: Content
            
            init(_ pointer: Pointer, content: Content) {
                templateId = pointer.templateId
                id = pointer.id
                type = pointer.type
                self.content = content
            }
        }
        
        enum CType: Decodable {
            case key(Key), custom(String)
            
            enum Key: String, Codable {
                case screen, view, button, image, icon, striplet, label, textField, textView, list, scrollView, tabBarScreen, collection, map, stackView, shape, tableView, activityIndicator, toggle, slider, pageControl, picker, shimmer, datePicker
            }
            
            func isOneOf(_ keys: Key...) -> Bool {
                if case .key(let key) = self {
                    return keys.contains(key)
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

            /// Converts CType to JSONValue for serialization
            var jsonValue: JSONValue {
                switch self {
                case .key(let key):
                    return .string(key.rawValue)
                case .custom(let name):
                    return .string(name)
                }
            }
        }
    }
}

extension DSL.Model.Component.Entity {
    
    @discardableResult
    mutating func setContent(_ content: any DSL.Model.Component.EntityContent) -> Bool {
        if let content = content as? Content {
            self.content = content
            return true
        }
        return false
    }
}

extension DSL.Model.Component {

    /// Type-erased wrapper to decode `any Component.Protocol`
    struct `Any`: `Protocol`, Decodable, Sendable, TemplatePointerResolvable, DSL.Model.Style.StylePointerResolvable {
        private(set) var base: any `Protocol`

        // Forwarded conformance
        var templateId: String? { base.templateId }
        var id: String { base.id }
        var type: CType { base.type }

        private enum CodingKeys: String, CodingKey {
            case id, type, content
        }

        init(from decoder: any Decoder) throws {
            guard decoder.codingPath.count <= EngineLimits.maxJSONDepth else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Component tree nested too deeply"))
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let t = try container.decode(CType.self, forKey: .type)

            // Determine whether `content` exists and is non-nil
            let hasNonNilContent: Bool = {
                guard container.contains(.content) else { return false }
                return (try? !container.decodeNil(forKey: .content)) ?? false
            }()

            // If no content (missing or null) → Pointer
            guard hasNonNilContent else {
                self.base = try Pointer(from: decoder)
                return
            }

            // Otherwise decode the concrete entity for the discriminator
            switch t {
            case .key(.screen):
                self.base = try ConcreteEntity<View.C>(from: decoder)
            case .key(.view):
                self.base = try ConcreteEntity<View.C>(from: decoder)
            case .key(.button):
                self.base = try ConcreteEntity<Button.C>(from: decoder)
            case .key(.image):
                self.base = try ConcreteEntity<Image.C>(from: decoder)
            case .key(.icon):
                self.base = try ConcreteEntity<Icon.C>(from: decoder)
//            case .key(.striplet):
//                self.base = try Component.ConcreteEntity<Component.Striplet>(from: decoder)
            case .key(.label):
                self.base = try ConcreteEntity<Label.C>(from: decoder)
            case .key(.scrollView):
                self.base = try ConcreteEntity<ScrollView.C>(from: decoder)
            case .key(.tabBarScreen):
                self.base = try ConcreteEntity<TabBarScreen.C>(from: decoder)
            case .key(.collection):
                self.base = try ConcreteEntity<CollectionContent>(from: decoder)
            case .key(.map):
                self.base = try ConcreteEntity<MapContent>(from: decoder)
            case .key(.textField):
                self.base = try ConcreteEntity<TextField.C>(from: decoder)
            case .key(.textView):
                self.base = try ConcreteEntity<TextView.C>(from: decoder)
            case .key(.stackView):
                self.base = try ConcreteEntity<StackView.C>(from: decoder)
            case .key(.shape):
                self.base = try ConcreteEntity<Shape.C>(from: decoder)
            case .key(.tableView):
                self.base = try ConcreteEntity<TableView.Content>(from: decoder)
//            case .key(.collectionView):
//                self.base = try Component.ConcreteEntity<Component.CollectionView>(from: decoder)
            case .key(.activityIndicator):
                self.base = try ConcreteEntity<ActivityIndicator.C>(from: decoder)
            case .key(.toggle):
                self.base = try ConcreteEntity<Toggle.C>(from: decoder)
            case .key(.slider):
                self.base = try ConcreteEntity<Slider.C>(from: decoder)
            case .key(.pageControl):
                self.base = try ConcreteEntity<PageControl.C>(from: decoder)
            case .key(.picker):
                self.base = try ConcreteEntity<Picker.C>(from: decoder)
            case .key(.shimmer):
                self.base = try ConcreteEntity<Shimmer.C>(from: decoder)
            case .key(.datePicker):
                self.base = try ConcreteEntity<DatePicker.C>(from: decoder)
            case .custom(let name):
                // Pointers to custom types are handled above (no content).
                // Reaching here means there IS content for an unsupported custom type.
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "Unsupported custom Component.CType with content: \(name)"
                ))
            default:
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "Unsupported Component.CType: \(t)"
                ))
            }
        }
        
        func asConcreteEntity<Content: EntityContent>() -> ConcreteEntity<Content>? {
            return base as? ConcreteEntity<Content>
        }
        
        func asEntity() -> (any Entity)? {
            return base as? (any Entity)
        }
        
        func asPointer() -> Pointer? {
            return base as? Pointer
        }

        /**
         Extracts the content as a type-erased layout holder to access layout properties.
         */
        func extractContent() -> (any DSL.Model.LayoutHolder)? {
            if let entity = base as? ConcreteEntity<View.C> {
                return entity.content
            }
            if let entity = base as? ConcreteEntity<Button.C> {
                return entity.content
            }
            if let entity = base as? ConcreteEntity<Image.C> {
                return entity.content
            }
            if let entity = base as? ConcreteEntity<Icon.C> {
                return entity.content
            }
            if let entity = base as? ConcreteEntity<Label.C> {
                return entity.content
            }
            if let entity = base as? ConcreteEntity<ScrollView.C> {
                return entity.content
            }
            if let entity = base as? ConcreteEntity<TabBarScreen.C> {
                return entity.content
            }
            if let entity = base as? ConcreteEntity<CollectionContent> {
                return entity.content
            }
            if let entity = base as? ConcreteEntity<StackView.C> {
                return entity.content
            }
            if let entity = base as? ConcreteEntity<Shape.C> {
                return entity.content
            }
            if let entity = base as? ConcreteEntity<ActivityIndicator.C> {
                return entity.content
            }
            if let entity = base as? ConcreteEntity<Toggle.C> {
                return entity.content
            }
            if let entity = base as? ConcreteEntity<Slider.C> {
                return entity.content
            }
            if let entity = base as? ConcreteEntity<PageControl.C> {
                return entity.content
            }
            if let entity = base as? ConcreteEntity<Picker.C> {
                return entity.content
            }
            if let entity = base as? ConcreteEntity<Shimmer.C> {
                return entity.content
            }
            if let entity = base as? ConcreteEntity<DatePicker.C> {
                return entity.content
            }
            return nil
        }

        mutating func patchBase(_ base: any `Protocol`) {
            self.base = base
        }
        
        /// Resolves template pointers by preprocessing component JSON.
        /// Call this method after decoding to resolve any remaining template references.
        mutating func resolveTemplatePointers(using resolver: TemplateResolver) {
            // If this is a pointer with templateId, build component from template
            if let pointer = asPointer(),
               let templateId = pointer.templateId,
               let templateContent = resolver.resolvedTemplates[templateId],
               let templateType = resolver.getTemplateType(templateId) {
                // Build JSON for the resolved component
                var componentJson: [String: JSONValue] = [
                    "id": .string(pointer.id),
                    "type": templateType.jsonValue
                ]

                // Add content from template
                if case .object(let contentObj) = templateContent {
                    componentJson["content"] = .object(contentObj)
                }

                // Try to decode as concrete component
                if let decoded = Self.decodeFromJson(.object(componentJson)) {
                    self.base = decoded.base
                }
            }

            // Recursively resolve children
            guard var entity = asEntity() else { return }
            var content = entity.content
            var children = content.children
            for i in 0..<children.count {
                var child = children[i]
                child.resolveTemplatePointers(using: resolver)
                children[i] = child
            }
            content.children = children
            entity.setContent(content)
            patchBase(entity)
        }

        /// Decodes a Component.Any from JSONValue
        private static func decodeFromJson(_ json: JSONValue) -> `Any`? {
            guard let data = try? JSONEncoder().encode(json),
                  let component = try? JSONDecoder().decode(`Any`.self, from: data) else {
                return nil
            }
            return component
        }
        
        mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
            guard var entity = asEntity() else { return }
            var content = entity.content

            // Resolve own style
            if var ownStyle = content.style as? DSL.Model.Style.StylePointerResolvable {
                ownStyle.resolveStylePointers(resolver: resolver)
                content.setResolvedStyle(ownStyle)
            }

            // Resolve state styles (for components with states)
            content.resolveStateStylePointers(resolver: resolver)

            // Traverse children
            var children = content.children
            for i in 0 ..< children.count {
                var child = children[i]
                child.resolveStylePointers(resolver: resolver)
                children[i] = child
            }
            content.children = children

            // Assign content
            entity.setContent(content)
            patchBase(entity)
        }
        
        func isResolved() -> Bool {
            guard let entity = asEntity() else { return false }
            if let ownStyle = entity.content.style as? DSL.Model.Style.StylePointerResolvable, !ownStyle.isResolved() {
                return false
            }
            return true
        }

        /**
         Returns the IDs of all style pointers that could not be resolved, recursively across this component and its children.
         */
        func unresolvedPointerIds() -> [String] {
            guard let entity = asEntity() else { return [] }
            var ids: [String] = []
            if let ownStyle = entity.content.style as? DSL.Model.Style.StylePointerResolvable {
                ids += ownStyle.unresolvedPointerIds()
            }
            for child in entity.content.children {
                ids += child.unresolvedPointerIds()
            }
            return ids
        }
    }
}
