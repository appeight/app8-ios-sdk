import UIKit

extension DSL.Model.Component {

    struct Video {

        typealias Entity = ConcreteEntity<C>
        typealias C = Content<Video.Properties, Style.Video>

        struct LocalAsset: Decodable {
            /// Bundle resource name, with or without extension ("intro" or "intro.mp4").
            let name: String
        }

        enum `Type`: String, Decodable {
            case localAsset, remoteAsset, none

            enum Model {
                case asset(LocalAsset)
                /// A backend/host-provided asset, resolved at runtime via the data
                /// source (`getAsset`) — same as `image`'s remoteAsset.
                case remoteAsset(DSL.Model.Asset)
                case none
            }
        }
    }
}

// MARK: - Properties

extension DSL.Model.Component.Video {

    struct Properties: Decodable, CustomDebugStringConvertible {
        let type: `Type`
        let model: `Type`.Model
        /// Start playing automatically when on-screen. Default `true`.
        let autoplay: Bool
        /// Seamlessly loop playback. Default `true`.
        let loop: Bool
        /// Mute audio. Default `true` (background/onboarding loops are silent).
        let muted: Bool

        init(type: `Type`, model: `Type`.Model, autoplay: Bool = true, loop: Bool = true, muted: Bool = true) {
            self.type = type
            self.model = model
            self.autoplay = autoplay
            self.loop = loop
            self.muted = muted
        }

        enum CodingKeys: String, CodingKey {
            case type, autoplay, loop, muted
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
            self.autoplay = try container.decodeIfPresent(Bool.self, forKey: .autoplay) ?? true
            self.loop = try container.decodeIfPresent(Bool.self, forKey: .loop) ?? true
            self.muted = try container.decodeIfPresent(Bool.self, forKey: .muted) ?? true
        }

        var debugDescription: String {
            switch model {
            case .asset(let asset):
                return "Video: type = \(type.rawValue), name = \(asset.name)"
            case .remoteAsset(let asset):
                return "Video: type = \(type.rawValue), asset = \(asset)"
            case .none:
                return "Video: type = none"
            }
        }
    }
}
