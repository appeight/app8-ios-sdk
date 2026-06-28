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

        /// What the player shows once a non-looping clip plays to the end.
        /// Ignored while `loop == true` (the looper never reaches an end).
        enum EndBehavior: String, Decodable, Equatable {
            /// Hold the final rendered frame (default). Fixes the historical
            /// black-layer-on-end bug.
            case freezeLastFrame
            /// Treat completion as a loop point — equivalent to `loop: true`.
            case loop
            /// Hide the player layer (and poster) after completion.
            case hidePoster
            /// Show `endPoster` (falling back to `poster`) after completion.
            case showPoster
        }

        /// How a playing clip's audio coexists with whatever else the device is
        /// already playing (music, a podcast, another app). The engine maps each
        /// case onto an `AVAudioSession` category so a silent background loop never
        /// hijacks the device's audio.
        enum AudioMix: String, Decodable, Equatable {
            /// Derive from `muted` (default): muted clips behave like `mix`,
            /// audible clips like `interrupt`.
            case auto
            /// Mix silently alongside other audio — never interrupt it. Governed
            /// by the ringer switch. Best for muted background loops.
            case mix
            /// Lower (duck) other audio while this clip plays, then restore it.
            case duck
            /// Take over device audio, stopping other sources; plays through the
            /// ringer switch. For a real video the user is meant to hear.
            case interrupt
        }

        /// A still image shown before playback (and optionally after, via
        /// `endPoster`). Reused for both pre- and post-playback posters so the
        /// schema stays small.
        struct PosterSource: Decodable {
            enum Kind: String, Decodable, Equatable {
                /// First frame of the video itself — no extra authored asset.
                case firstFrame
                /// Bundled image resource (`UIImage(named:)`).
                case localAsset
                /// Host/data-source image, resolved by id/name like `image`.
                case remoteAsset
                /// Direct image URL.
                case url
                /// A specific frame of the video at `time` seconds.
                case frameAtTime
            }

            let kind: Kind
            /// localAsset bundle name / remoteAsset name.
            let name: String?
            /// remoteAsset id (data source lookup).
            let id: String?
            /// Image URL (for `.url`).
            let url: String?
            /// Seconds into the video (for `.frameAtTime`).
            let time: Double?

            enum CodingKeys: String, CodingKey {
                case type, name, id, url, time
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.kind = try container.decode(Kind.self, forKey: .type)
                self.name = try container.decodeIfPresent(String.self, forKey: .name)
                self.id = try container.decodeIfPresent(String.self, forKey: .id)
                self.url = try container.decodeIfPresent(String.self, forKey: .url)
                self.time = try container.decodeIfPresent(Double.self, forKey: .time)
            }

            init(kind: Kind, name: String? = nil, id: String? = nil, url: String? = nil, time: Double? = nil) {
                self.kind = kind
                self.name = name
                self.id = id
                self.url = url
                self.time = time
            }

            /// The remote asset this poster references, if any — for prefetch.
            /// `firstFrame`/`frameAtTime`/`localAsset` need no warming.
            var remoteAsset: DSL.Model.Asset? {
                switch kind {
                case .remoteAsset, .url:
                    return DSL.Model.Asset(id: id, name: name, url: url)
                case .firstFrame, .frameAtTime, .localAsset:
                    return nil
                }
            }
        }

        /// A forward-only boundary on the timeline. When playback crosses
        /// `time`, the engine fires `actions[.onTimeMark]` with `$markId` set.
        struct Mark: Decodable {
            let id: String
            let time: Double
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
        /// How this clip's audio coexists with other device audio. Default
        /// `.auto` (derives from `muted`). See `AudioMix`.
        let audioMix: AudioMix
        /// What to show after a non-looping clip completes. Default `.freezeLastFrame`.
        let endBehavior: EndBehavior
        /// Still shown before the first frame paints.
        let poster: PosterSource?
        /// Still shown after completion (when `endBehavior` is `.showPoster`).
        /// Falls back to `poster` when omitted.
        let endPoster: PosterSource?
        /// Delay before the initial play, in seconds (poster stays up).
        let startDelay: Double?
        /// Seek offset to begin playback at, in seconds.
        let startTime: Double?
        /// Playback rate (e.g. 0.5, 2.0). Defaults to 1.0 at the call site.
        let rate: Float?
        /// Forward-only timeline marks that fire `actions[.onTimeMark]`.
        let marks: [Mark]?

        init(
            type: `Type`,
            model: `Type`.Model,
            autoplay: Bool = true,
            loop: Bool = true,
            muted: Bool = true,
            audioMix: AudioMix = .auto,
            endBehavior: EndBehavior = .freezeLastFrame,
            poster: PosterSource? = nil,
            endPoster: PosterSource? = nil,
            startDelay: Double? = nil,
            startTime: Double? = nil,
            rate: Float? = nil,
            marks: [Mark]? = nil
        ) {
            self.type = type
            self.model = model
            self.autoplay = autoplay
            self.loop = loop
            self.muted = muted
            self.audioMix = audioMix
            self.endBehavior = endBehavior
            self.poster = poster
            self.endPoster = endPoster
            self.startDelay = startDelay
            self.startTime = startTime
            self.rate = rate
            self.marks = marks
        }

        enum CodingKeys: String, CodingKey {
            case type, autoplay, loop, muted, audioMix
            case endBehavior, poster, endPoster, startDelay, startTime, rate, marks
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
            self.audioMix = try container.decodeIfPresent(AudioMix.self, forKey: .audioMix) ?? .auto
            self.endBehavior = try container.decodeIfPresent(EndBehavior.self, forKey: .endBehavior) ?? .freezeLastFrame
            self.poster = try container.decodeIfPresent(PosterSource.self, forKey: .poster)
            self.endPoster = try container.decodeIfPresent(PosterSource.self, forKey: .endPoster)
            self.startDelay = try container.decodeIfPresent(Double.self, forKey: .startDelay)
            self.startTime = try container.decodeIfPresent(Double.self, forKey: .startTime)
            self.rate = try container.decodeIfPresent(Float.self, forKey: .rate)
            self.marks = try container.decodeIfPresent([Mark].self, forKey: .marks)
        }

        /// `loop == true` or an explicit `endBehavior: loop` both drive the
        /// gapless looping path.
        var loops: Bool { loop || endBehavior == .loop }

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
