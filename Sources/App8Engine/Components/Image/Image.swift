import UIKit

extension DSL.Model.Component {

    typealias Style = DSL.Model.Style
    
    struct Image {
        
        typealias Entity = ConcreteEntity<C>
        typealias C = Content<Image.Properties, Style.Image>
        
        struct LocalAsset: Decodable {
            let name: String
        }
        
        enum `Type`: String, Decodable {
            case localAsset, remoteAsset, none
            
            enum Model {
                case asset(LocalAsset)
                case remoteAsset(DSL.Model.Asset)
                case none
            }
        }
    }
}

// MARK: - Properties

extension DSL.Model.Component.Image {
    
    struct Properties: Decodable, CustomDebugStringConvertible {
        let type: `Type`
        let model: `Type`.Model
        
        init(type: `Type`, model: `Type`.Model) {
            self.type = type
            self.model = model
        }
        
        enum CodingKeys: String, CodingKey {
            case type
        }
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.type = try container.decode(`Type`.self, forKey: .type)
            switch self.type {
            case .localAsset:
                self.model = .asset(try LocalAsset(from: decoder))
            case .remoteAsset:
                self.model = .remoteAsset(try DSL.Model.Asset(from: decoder))
            default:
                self.model = .none
            }
        }
        
        var debugDescription: String {
            switch model {
            case .asset(let asset):
                return "Icon: type = \(type.rawValue), name = \(asset.name)"
            case .remoteAsset(let asset):
                return "Icon: type = \(type.rawValue), url = \(asset)"
            case .none:
                return "Icon: type = none"
            }
        }
    }
}
