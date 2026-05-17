import UIKit

extension DSL.Model.Component {

    struct Icon {

        typealias Entity = ConcreteEntity<C>
        typealias C = Content<Icon.Properties, Style.Icon>
        
        struct Symbol: Decodable {
            let name: String
        }
        
        struct Asset: Decodable {
            let name: String
        }
        
        struct Remote: Decodable {
            let url: URL
        }
        
        enum `Type`: String, Decodable {
            case symbol, asset, remote, none
            
            enum Model {
                case symbol(Symbol)
                case asset(Asset)
                case remote(Remote)
                case none
            }
        }
    }
}

// MARK: - Properties

extension DSL.Model.Component.Icon {
    
    struct Properties: Decodable, CustomDebugStringConvertible {
        let type: `Type`
        let model: `Type`.Model
        /// Dynamic background color. Accepts the bare expression form or the
        /// wrapped `{ value, animation }` form for per-property animation.
        let backgroundColor: DSL.Model.AnimatedValue<String>?
        /// Dynamic tint color — supports expressions like "{{item.iconColor}}".
        /// Accepts the bare expression form or the wrapped form.
        let tintColor: DSL.Model.AnimatedValue<String>?
        /// Dynamic visibility — supports expressions like "{{!isChecked}}"
        let isHidden: String?

        init(type: `Type`, model: `Type`.Model, backgroundColor: DSL.Model.AnimatedValue<String>? = nil, tintColor: DSL.Model.AnimatedValue<String>? = nil, isHidden: String? = nil) {
            self.type = type
            self.model = model
            self.backgroundColor = backgroundColor
            self.tintColor = tintColor
            self.isHidden = isHidden
        }

        enum CodingKeys: String, CodingKey {
            case type, backgroundColor, tintColor, isHidden
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.type = try container.decode(`Type`.self, forKey: .type)
            self.backgroundColor = try container.decodeIfPresent(DSL.Model.AnimatedValue<String>.self, forKey: .backgroundColor)
            self.tintColor = try container.decodeIfPresent(DSL.Model.AnimatedValue<String>.self, forKey: .tintColor)
            self.isHidden = try container.decodeIfPresent(String.self, forKey: .isHidden)
            switch self.type {
            case .symbol:
                self.model = .symbol(try Symbol(from: decoder))
            case .asset:
                self.model = .asset(try Asset(from: decoder))
            case .remote:
                self.model = .remote(try Remote(from: decoder))
            default:
                self.model = .none
            }
        }

        var debugDescription: String {
            switch model {
            case .symbol(let symbol):
                return "Icon: type = \(type.rawValue), name = \(symbol.name)"
            case .asset(let asset):
                return "Icon: type = \(type.rawValue), name = \(asset.name)"
            case .remote(let remote):
                return "Icon: type = \(type.rawValue), url = \(remote.url)"
            case .none:
                return "Icon: type = none"
            }
        }
    }
}
