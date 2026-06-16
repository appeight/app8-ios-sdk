// Generic, declarative screen-to-screen transition primitive.
//
// A transition animates a set of view properties (opacity, translate, scale,
// rotate) on the outgoing (`from`) and incoming (`to`) screens from a `begin`
// keyframe to an `end` keyframe, under a shared animation descriptor. It is the
// navigation-level analogue of `DSL.Model.Animation` and reuses that model
// wholesale for timing.
//
// Decoding mirrors `Animation` exactly: a value is either an inline definition
// or a pointer into the app-level `transitions` registry, resolved at decode
// time via `decoder.userInfo[.app8TransitionResolver]`. A bare string
// (`"slide"`, `"fade"`, `"system"`) is shorthand for an inline preset.

import UIKit

extension DSL.Model {

    /// A transition reference. Either an inline transition or a pointer to a
    /// named entry in the app-level `transitions` registry. Pointer resolution
    /// to the inline form happens at decode time (mirrors the animation pointer
    /// pattern).
    enum ScreenTransition: Decodable, Sendable {
        case inline(Inline)
        case pointer(String)

        /// Concrete inline transition. Carries everything preset expansion and
        /// the animators need. All visual fields are optional so presets and
        /// identity defaults can fill the gaps.
        struct Inline: Sendable {
            /// Identifier when this inline came from a wrapped form
            /// (`{ id, type, content }`) or the registry. Nil for bare inline.
            var id: String?
            /// Routing hint. Nil means "let the preset decide" (see `Preset.defaultMode`).
            var mode: Mode?
            /// Named preset that seeds the keyframes. Nil means fully custom.
            var preset: Preset?
            /// Directional parameter for edge-based presets (`slide`, `cover`).
            var edge: Edge?
            /// Timing. Resolved from the `animations` registry at decode time
            /// when written as a pointer; nil falls back to the preset default.
            var animation: Animation?
            /// Outgoing screen keyframes (overrides preset).
            var from: Participant?
            /// Incoming screen keyframes (overrides preset).
            var to: Participant?
            /// How the dismiss/pop direction is derived. Defaults to `.auto`.
            var reverse: Reverse
            /// Which screen is stacked on top during the (forward) transition.
            /// Defaults to `.incoming`.
            var raise: Raise?
            /// Modal-only backdrop dimming.
            var dimming: Dimming?
            /// Gesture-driven interactive dismiss/pop configuration.
            var interactive: InteractiveConfig?
            /// Modal-only sized-container geometry + chrome. Nil ⇒ full-screen modal.
            var presentation: ModalPresentation?
        }

        // MARK: - Sub-models

        /// Whether the transition drives a navigation-stack push/pop or a modal
        /// present/dismiss.
        enum Mode: String, SafeEnumCodable, Sendable {
            case push
            case modal
            static var unknownCase: Self { .push }
        }

        /// Built-in transition recipes. Each expands to concrete keyframes plus
        /// a default animation during resolution.
        enum Preset: String, SafeEnumCodable, Sendable {
            case slide
            case fade
            case crossDissolve
            case scale
            case zoom
            case cover
            case popup         // centered card modal (sized) — see ModalPresentation
            case sheet         // bottom-anchored card modal (sized) — see ModalPresentation
            case shared        // shared-element morph (hero / composite) — see ElementTransition
            case none          // instantaneous (no animation)
            case system        // sentinel: use UIKit's native push / modal

            /// Unknown presets degrade to the native transition rather than crash.
            static var unknownCase: Self { .system }

            /// Default routing for the preset when `mode` is unspecified.
            var defaultMode: Mode {
                switch self {
                case .scale, .zoom, .cover, .popup, .sheet: return .modal
                case .slide, .fade, .crossDissolve, .shared, .none, .system: return .push
                }
            }
        }

        /// Direction an edge-based preset enters from (and the reverse exits to).
        enum Edge: String, SafeEnumCodable, Sendable {
            case leading
            case trailing
            case top
            case bottom
            static var unknownCase: Self { .trailing }
        }

        /// Which screen sits on top during the forward transition — i.e. the
        /// container z-order. `incoming` (default) draws the entering/revealed
        /// screen above the leaving one (slide/zoom/cover in *on top*).
        /// `outgoing` draws the leaving screen on top so it can move away to
        /// *reveal* a stationary incoming screen underneath. The reverse
        /// direction mirrors this so a pop/dismiss reads as the inverse.
        enum Raise: String, SafeEnumCodable, Sendable {
            case incoming
            case outgoing
            static var unknownCase: Self { .incoming }
        }

        /// A pair of keyframes describing one screen's motion over the transition.
        struct Participant: Decodable, Sendable {
            var begin: TransitionState
            var end: TransitionState

            init(begin: TransitionState, end: TransitionState) {
                self.begin = begin
                self.end = end
            }

            private enum CodingKeys: String, CodingKey { case begin, end }

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.begin = (try c.decodeIfPresent(TransitionState.self, forKey: .begin)) ?? .identity
                self.end = (try c.decodeIfPresent(TransitionState.self, forKey: .end)) ?? .identity
            }
        }

        /// A single keyframe applied to a screen's view. All fields optional
        /// with identity defaults — authors specify only what moves.
        struct TransitionState: Decodable, Sendable {
            /// `0…1`. Absolute opacity for this keyframe. Omitted ⇒ the natural,
            /// fully-opaque resting state (1) — so an `end` keyframe that omits
            /// `opacity` always animates the screen back to fully visible.
            var opacity: Double?
            var translate: Translation
            var scale: Scale
            /// Rotation in degrees, clockwise.
            var rotate: Double
            /// Origin for scale/rotate in unit coordinates (`0…1`).
            var anchor: Anchor

            static let identity = TransitionState(
                opacity: nil,
                translate: .zero,
                scale: .identity,
                rotate: 0,
                anchor: .center
            )

            init(opacity: Double?, translate: Translation, scale: Scale, rotate: Double, anchor: Anchor) {
                self.opacity = opacity
                self.translate = translate
                self.scale = scale
                self.rotate = rotate
                self.anchor = anchor
            }

            private enum CodingKeys: String, CodingKey {
                case opacity, translate, scale, rotate, anchor
            }

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.opacity = try c.decodeIfPresent(Double.self, forKey: .opacity)
                self.translate = (try c.decodeIfPresent(Translation.self, forKey: .translate)) ?? .zero
                self.scale = (try c.decodeIfPresent(Scale.self, forKey: .scale)) ?? .identity
                self.rotate = (try c.decodeIfPresent(Double.self, forKey: .rotate)) ?? 0
                self.anchor = (try c.decodeIfPresent(Anchor.self, forKey: .anchor)) ?? .center
            }
        }

        /// 2-D translation. Each axis is a `Length` resolved against the
        /// container's width (x) or height (y).
        struct Translation: Decodable, Sendable {
            var x: Length
            var y: Length

            static let zero = Translation(x: .points(0), y: .points(0))

            init(x: Length, y: Length) {
                self.x = x
                self.y = y
            }

            private enum CodingKeys: String, CodingKey { case x, y }

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.x = (try c.decodeIfPresent(Length.self, forKey: .x)) ?? .points(0)
                self.y = (try c.decodeIfPresent(Length.self, forKey: .y)) ?? .points(0)
            }
        }

        /// A length expressed in points (a number) or as a fraction of a
        /// reference dimension (a `"NN%"` string). `"100%"` resolves to exactly
        /// one container width/height, so slides are device-independent.
        enum Length: Decodable, Sendable {
            case points(Double)
            case fraction(Double)

            /// Resolve to a concrete point value against a reference dimension.
            func resolved(against dimension: CGFloat) -> CGFloat {
                switch self {
                case .points(let p):   return CGFloat(p)
                case .fraction(let f):  return CGFloat(f) * dimension
                }
            }

            init(from decoder: any Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let number = try? c.decode(Double.self) {
                    self = .points(number)
                    return
                }
                let string = try c.decode(String.self)
                let trimmed = string.trimmingCharacters(in: .whitespaces)
                if trimmed.hasSuffix("%"), let pct = Double(trimmed.dropLast()) {
                    self = .fraction(pct / 100)
                } else if let number = Double(trimmed) {
                    self = .points(number)
                } else {
                    throw DecodingError.dataCorrupted(.init(
                        codingPath: c.codingPath,
                        debugDescription: "Invalid transition length: \(string)"
                    ))
                }
            }
        }

        /// Anisotropic scale. Decodes from a single number (uniform) or `{ x, y }`.
        struct Scale: Decodable, Sendable {
            var x: Double
            var y: Double

            static let identity = Scale(x: 1, y: 1)

            init(x: Double, y: Double) {
                self.x = x
                self.y = y
            }

            private enum CodingKeys: String, CodingKey { case x, y }

            init(from decoder: any Decoder) throws {
                if let single = try? decoder.singleValueContainer(), let v = try? single.decode(Double.self) {
                    self.x = v
                    self.y = v
                    return
                }
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.x = (try c.decodeIfPresent(Double.self, forKey: .x)) ?? 1
                self.y = (try c.decodeIfPresent(Double.self, forKey: .y)) ?? 1
            }
        }

        /// Scale/rotation origin in unit coordinates. `(0.5, 0.5)` is centre.
        struct Anchor: Decodable, Sendable {
            var x: Double
            var y: Double

            static let center = Anchor(x: 0.5, y: 0.5)

            init(x: Double, y: Double) {
                self.x = x
                self.y = y
            }

            private enum CodingKeys: String, CodingKey { case x, y }

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.x = (try c.decodeIfPresent(Double.self, forKey: .x)) ?? 0.5
                self.y = (try c.decodeIfPresent(Double.self, forKey: .y)) ?? 0.5
            }
        }

        /// How the reverse (dismiss/pop) direction is produced.
        enum Reverse: Decodable, Sendable {
            /// Play the forward transition backwards (roles + keyframes swapped).
            case auto
            /// Explicit, possibly asymmetric, exit keyframes.
            case explicit(from: Participant?, to: Participant?)

            private enum CodingKeys: String, CodingKey { case from, to }

            init(from decoder: any Decoder) throws {
                if let single = try? decoder.singleValueContainer(),
                   let string = try? single.decode(String.self) {
                    // Any string other than an explicit object means "auto".
                    _ = string
                    self = .auto
                    return
                }
                let c = try decoder.container(keyedBy: CodingKeys.self)
                let from = try c.decodeIfPresent(Participant.self, forKey: .from)
                let to = try c.decodeIfPresent(Participant.self, forKey: .to)
                self = .explicit(from: from, to: to)
            }
        }

        /// Modal-only backdrop dimming.
        struct Dimming: Decodable, Sendable {
            /// Hex colour for the dimming view. Defaults to black.
            var color: DSL.Model.Style.Color.Hex?
            /// Peak opacity `0…1`.
            var opacity: Double
            /// Whether tapping the dimmed backdrop dismisses the modal. Default `true`.
            var dismissOnTap: Bool

            init(color: DSL.Model.Style.Color.Hex? = nil, opacity: Double = 0.4, dismissOnTap: Bool = true) {
                self.color = color
                self.opacity = opacity
                self.dismissOnTap = dismissOnTap
            }

            private enum CodingKeys: String, CodingKey { case color, opacity, dismissOnTap }

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.color = try c.decodeIfPresent(DSL.Model.Style.Color.Hex.self, forKey: .color)
                self.opacity = (try c.decodeIfPresent(Double.self, forKey: .opacity)) ?? 0.4
                self.dismissOnTap = (try c.decodeIfPresent(Bool.self, forKey: .dismissOnTap)) ?? true
            }
        }

        /// Gesture-driven interactive dismiss (modal) / pop (push).
        struct InteractiveConfig: Decodable, Sendable {
            var enabled: Bool
            /// The edge the dismissing gesture travels toward. Defaults to the
            /// transition's own `edge` (or trailing/bottom by mode).
            var edge: Edge?
            /// Progress past which lifting the finger completes the transition.
            var threshold: Double
            /// Gesture velocity (points/sec) that completes regardless of progress.
            var velocity: Double

            init(enabled: Bool, edge: Edge?, threshold: Double, velocity: Double) {
                self.enabled = enabled
                self.edge = edge
                self.threshold = threshold
                self.velocity = velocity
            }

            private enum CodingKeys: String, CodingKey { case enabled, edge, threshold, velocity }

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.enabled = (try c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
                self.edge = try c.decodeIfPresent(Edge.self, forKey: .edge)
                self.threshold = (try c.decodeIfPresent(Double.self, forKey: .threshold)) ?? 0.3
                self.velocity = (try c.decodeIfPresent(Double.self, forKey: .velocity)) ?? 800
            }
        }

        // MARK: - Element (shared-element) participation

        /// Per-component participation in a shared-element (`shared` preset)
        /// transition. Declared on a component's `content.transition` and matched
        /// across screens **by `key`** — never by the component's `id`. At
        /// transition time the engine collects each screen's `[key: view]`, keeps
        /// the keys present on *both* sides, and morphs each matched pair.
        struct ElementTransition: Decodable, Sendable {
            /// The matching tag. Two components (one per screen) sharing a `key`
            /// form a morph pair. Unique-per-screen keys ⇒ unambiguous matching.
            var key: String
            /// How the matched pair blends from source to target.
            var morph: Morph
            /// What happens to this element when the other screen has no element
            /// with the same `key` (no counterpart to morph into / from).
            var fallback: Fallback
            /// Stagger (seconds) applied to this element's morph start — lets a
            /// composite play element-by-element. Resolved as a delay-factor of
            /// the transition duration. Nil ⇒ no stagger.
            var stagger: Double?
            /// Optional per-element timing. Honored as the master morph timing for
            /// a single-element (hero) transition; for multi-element composites the
            /// transition-level animation drives and `stagger` orders the elements.
            var animation: Animation?

            private enum CodingKeys: String, CodingKey {
                case key, morph, fallback, stagger, animation
            }

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.key = try c.decode(String.self, forKey: .key)
                self.morph = (try c.decodeIfPresent(Morph.self, forKey: .morph)) ?? .frameFade
                self.fallback = (try c.decodeIfPresent(Fallback.self, forKey: .fallback)) ?? .fade
                self.stagger = try c.decodeIfPresent(Double.self, forKey: .stagger)
                self.animation = try c.decodeIfPresent(Animation.self, forKey: .animation)
            }

            init(key: String, morph: Morph = .frameFade, fallback: Fallback = .fade, stagger: Double? = nil, animation: Animation? = nil) {
                self.key = key
                self.morph = morph
                self.fallback = fallback
                self.stagger = stagger
                self.animation = animation
            }
        }

        /// How a matched element blends between its source and target frames.
        enum Morph: String, SafeEnumCodable, Sendable {
            case frame          // interpolate position + size only (no fade)
            case fade           // cross-dissolve only (no frame change)
            case frameFade      // both — the zoom default
            static var unknownCase: Self { .frameFade }
        }

        /// What to do with a keyed element that has no counterpart on the other
        /// screen during a shared-element transition.
        enum Fallback: String, SafeEnumCodable, Sendable {
            case fade           // fade the element in (incoming) / out (outgoing)
            case slideTop       // fade + slide from/to the top edge
            case slideBottom    // fade + slide from/to the bottom edge
            case none           // leave it to ride the backdrop (no extra motion)
            static var unknownCase: Self { .fade }
        }

        // MARK: - Decoding

        private enum WrapperKeys: String, CodingKey { case id, type, content }

        init(from decoder: any Decoder) throws {
            // Bare string → preset shorthand (e.g. "slide", "fade", "system").
            if let single = try? decoder.singleValueContainer(),
               let string = try? single.decode(String.self) {
                var inline = Inline.empty
                inline.preset = Preset(rawValue: string) ?? .system
                self = .inline(inline)
                return
            }

            // Probe for wrapper keys (`id`, `content`); fall back to flat inline.
            let wrapper = try? decoder.container(keyedBy: WrapperKeys.self)
            let id = try wrapper?.decodeIfPresent(String.self, forKey: .id) ?? nil
            let hasContent: Bool = {
                guard let wrapper, wrapper.contains(.content) else { return false }
                return (try? !wrapper.decodeNil(forKey: .content)) ?? false
            }()

            if let id, !hasContent {
                // Pure pointer. Resolve immediately via the registry resolver in
                // `decoder.userInfo`. The production resolver is `@Sendable`;
                // tests may hand in a non-Sendable closure.
                let resolver: ((String) -> Inline?)? =
                    (decoder.userInfo[.app8TransitionResolver] as? @Sendable (String) -> Inline?)
                    ?? (decoder.userInfo[.app8TransitionResolver] as? (String) -> Inline?)
                if let resolved = resolver?(id) {
                    self = .inline(resolved)
                } else {
                    self = .pointer(id)
                }
                return
            }

            if let id, hasContent, let wrapper {
                var inline = try wrapper.decode(Inline.self, forKey: .content)
                inline.id = id
                self = .inline(inline)
                return
            }

            self = .inline(try Inline(from: decoder))
        }

        // MARK: - Resolution accessors (mirror `Animation`)

        /// Inline form, resolving via the supplied registry resolver when this
        /// is a pointer. `nil` if the pointer cannot be resolved.
        func inline(resolveBy resolver: (String) -> Inline?) -> Inline? {
            switch self {
            case .inline(let i): return i
            case .pointer(let id): return resolver(id)
            }
        }

        /// Inline form when known statically; nil for unresolved pointers.
        var inlineOrNil: Inline? {
            if case .inline(let i) = self { return i }
            return nil
        }

        var pointerId: String? {
            if case .pointer(let id) = self { return id }
            return nil
        }

        var isPointer: Bool { pointerId != nil }
    }
}

extension DSL.Model.ScreenTransition.Inline {
    /// Replace a pointer `animation` with its resolved inline form, in place.
    /// Used when a registry transition is decoded before the animation resolver
    /// is available (app.json decodes ahead of registry construction).
    mutating func normalizeAnimation(resolveBy resolver: (String) -> DSL.Model.Animation.Inline?) {
        guard let animation, animation.isPointer,
              let inline = animation.inline(resolveBy: resolver) else { return }
        self.animation = .inline(inline)
    }
}

// MARK: - Inline decoding (flat form)

extension DSL.Model.ScreenTransition.Inline: Decodable {

    /// An inline with every field at its identity default.
    static var empty: Self {
        .init(
            id: nil,
            mode: nil,
            preset: nil,
            edge: nil,
            animation: nil,
            from: nil,
            to: nil,
            reverse: .auto,
            raise: nil,
            dimming: nil,
            interactive: nil,
            presentation: nil
        )
    }

    private enum CodingKeys: String, CodingKey {
        case mode, preset, edge, animation, from, to, reverse, raise, dimming, interactive, presentation
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = nil
        self.mode = try c.decodeIfPresent(DSL.Model.ScreenTransition.Mode.self, forKey: .mode)
        self.preset = try c.decodeIfPresent(DSL.Model.ScreenTransition.Preset.self, forKey: .preset)
        self.edge = try c.decodeIfPresent(DSL.Model.ScreenTransition.Edge.self, forKey: .edge)
        self.animation = try c.decodeIfPresent(DSL.Model.Animation.self, forKey: .animation)
        self.from = try c.decodeIfPresent(DSL.Model.ScreenTransition.Participant.self, forKey: .from)
        self.to = try c.decodeIfPresent(DSL.Model.ScreenTransition.Participant.self, forKey: .to)
        self.reverse = (try c.decodeIfPresent(DSL.Model.ScreenTransition.Reverse.self, forKey: .reverse)) ?? .auto
        self.raise = try c.decodeIfPresent(DSL.Model.ScreenTransition.Raise.self, forKey: .raise)
        self.dimming = try c.decodeIfPresent(DSL.Model.ScreenTransition.Dimming.self, forKey: .dimming)
        self.interactive = try c.decodeIfPresent(DSL.Model.ScreenTransition.InteractiveConfig.self, forKey: .interactive)
        self.presentation = try c.decodeIfPresent(DSL.Model.ScreenTransition.ModalPresentation.self, forKey: .presentation)
    }
}

// MARK: - Component `transition` property (dual meaning)

extension DSL.Model {

    /// The value of a component's `content.transition`. It carries one of two
    /// kinds of context, disambiguated at decode time:
    ///
    /// - On a **screen root**, it is the screen's default `ScreenTransition`
    ///   (used when navigating *to* that screen with no action-level transition).
    /// - On any **child component**, it is an `ElementTransition` participation
    ///   context (a `key` + morph/fallback) for shared-element transitions.
    ///
    /// Rule: an object containing `"key"` ⇒ element context; anything else (bare
    /// string preset, `{ id }` pointer, or a preset/`from`/`to` object) ⇒ screen
    /// transition. A component's own `id` is never involved in either case.
    enum ComponentTransition: Decodable, Sendable {
        case screen(ScreenTransition)
        case element(ScreenTransition.ElementTransition)

        private enum ProbeKeys: String, CodingKey { case key }

        init(from decoder: any Decoder) throws {
            if let probe = try? decoder.container(keyedBy: ProbeKeys.self),
               probe.contains(.key),
               (try? probe.decodeNil(forKey: .key)) == false {
                self = .element(try ScreenTransition.ElementTransition(from: decoder))
                return
            }
            self = .screen(try ScreenTransition(from: decoder))
        }

        /// The screen-to-screen transition, when this is the screen-default form.
        var screenOrNil: ScreenTransition? {
            if case .screen(let s) = self { return s }
            return nil
        }

        /// The per-component element-participation context, when present.
        var elementOrNil: ScreenTransition.ElementTransition? {
            if case .element(let e) = self { return e }
            return nil
        }
    }
}

/// Exposes a component content's `transition` for type-erased reads (mirrors
/// `LayoutHolder`). Lets the engine pull an element-participation context off any
/// rendered component without switching on its concrete type.
protocol TransitionHolder {
    var transition: DSL.Model.ComponentTransition? { get }
}

extension DSL.Model.Component.Content: TransitionHolder {}
