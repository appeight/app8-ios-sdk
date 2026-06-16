// Resolves a declarative `ScreenTransition.Inline` into a fully-concrete
// `Resolved` value the animators consume. Named presets expand into begin/end
// keyframes here; any explicit `from`/`to`/`animation`/`mode` on the inline
// overlays the preset's defaults.

import UIKit

extension DSL.Model.ScreenTransition {

    /// Fully-resolved, ready-to-run transition. Produced from an `Inline` at
    /// navigation time. Consumed on the main actor by the animators, so it
    /// carries a `UIColor` and is intentionally not `Sendable`.
    struct Resolved {
        enum Kind {
            case system   // install no custom delegate — use UIKit's native transition
            case none     // no animation (instantaneous)
            case custom   // animate the screen keyframes below (PropertyTransitionAnimator)
            case shared   // morph matched elements between screens (SharedElementTransitionAnimator)
        }

        var kind: Kind
        var mode: Mode
        var edge: Edge
        /// Container z-order during the forward transition.
        var raise: Raise
        var animation: DSL.Model.Animation.Inline
        /// Forward (present/push) keyframes.
        var from: Participant
        var to: Participant
        /// Explicit reverse (dismiss/pop) keyframes; nil → auto-invert `from`/`to`.
        var reverseFrom: Participant?
        var reverseTo: Participant?
        var dimming: ResolvedDimming?
        var interactive: InteractiveConfig?
    }

    struct ResolvedDimming {
        var color: UIColor
        var opacity: Double
    }

    // MARK: - Resolution

    // (see `Resolved` helpers below for animator construction)

    /// Expand an inline transition into a `Resolved`. `animationResolver` covers
    /// the rare case where the inline's `animation` is still a registry pointer
    /// (registry entries decoded before the animation resolver was installed).
    static func resolve(
        _ inline: Inline,
        animationResolver: (String) -> DSL.Model.Animation.Inline? = { _ in nil }
    ) -> Resolved {
        let preset = inline.preset
        let mode = inline.mode ?? preset?.defaultMode ?? .push
        let edge = inline.edge ?? preset?.defaultEdge ?? .trailing
        let raise = inline.raise ?? .incoming

        // Sentinels short-circuit before any keyframe work. Compare against the
        // qualified cases — an unqualified `.none` would resolve to `Optional.none`
        // (i.e. nil), not `Preset.none`.
        if preset == Preset.system {
            return Resolved(
                kind: .system, mode: mode, edge: edge, raise: raise,
                animation: .defaultStateTransition,
                from: .identityPair, to: .identityPair,
                reverseFrom: nil, reverseTo: nil, dimming: nil, interactive: nil
            )
        }
        if preset == Preset.none {
            return Resolved(
                kind: .none, mode: mode, edge: edge, raise: raise,
                animation: .instant,
                from: .identityPair, to: .identityPair,
                reverseFrom: nil, reverseTo: nil, dimming: nil, interactive: nil
            )
        }

        // Seed keyframes + default animation from the preset (if any).
        let seed = preset.map { keyframes(for: $0, edge: edge) }
        var from = seed?.from ?? .identityPair
        var to = seed?.to ?? .identityPair

        // Explicit author keyframes override the preset seed.
        if let f = inline.from { from = f }
        if let t = inline.to { to = t }

        // Timing: explicit inline animation → preset default → generic default.
        let resolvedAnimation = inline.animation?.inline(resolveBy: animationResolver)
            ?? preset.map { defaultAnimation(for: $0) }
            ?? .transitionDefault

        // Reverse keyframes (explicit only; nil means auto-invert downstream).
        var reverseFrom: Participant?
        var reverseTo: Participant?
        if case .explicit(let rf, let rt) = inline.reverse {
            reverseFrom = rf
            reverseTo = rt
        }

        let dimming = inline.dimming.map {
            ResolvedDimming(color: ($0.color ?? .init("#000000")).ui, opacity: $0.opacity)
        }

        // The `shared` preset routes to the shared-element animator; its `from`/
        // `to` keyframes describe the *backdrop* motion (the non-matched content),
        // while matched elements morph on top per their own `ElementTransition`.
        let kind: Resolved.Kind = (preset == Preset.shared) ? .shared : .custom

        return Resolved(
            kind: kind, mode: mode, edge: edge, raise: raise,
            animation: resolvedAnimation,
            from: from, to: to,
            reverseFrom: reverseFrom, reverseTo: reverseTo,
            dimming: dimming, interactive: inline.interactive
        )
    }

    /// Convenience: resolve a `ScreenTransition` reference, returning nil for an
    /// unresolved pointer (caller falls back to the native transition).
    static func resolve(
        _ transition: DSL.Model.ScreenTransition,
        animationResolver: (String) -> DSL.Model.Animation.Inline? = { _ in nil }
    ) -> Resolved? {
        guard let inline = transition.inlineOrNil else { return nil }
        return resolve(inline, animationResolver: animationResolver)
    }

    // MARK: - Preset keyframes

    private static func keyframes(for preset: Preset, edge: Edge) -> Participant.Pair {
        switch preset {
        case .slide:
            // Incoming enters from `edge`; outgoing parallaxes 30% the opposite way.
            return Participant.Pair(
                from: Participant(
                    begin: .identity,
                    end: state(translate: offscreen(edge.opposite, fraction: 0.3))
                ),
                to: Participant(
                    begin: state(translate: offscreen(edge, fraction: 1.0)),
                    end: .identity
                )
            )

        case .fade, .crossDissolve:
            // New screen fades in over the old (safe for opaque full-screen content).
            return Participant.Pair(
                from: Participant(begin: .identity, end: .identity),
                to: Participant(begin: state(opacity: 0), end: state(opacity: 1))
            )

        case .scale, .zoom:
            // New screen scales up from 92% while fading in.
            return Participant.Pair(
                from: Participant(begin: .identity, end: .identity),
                to: Participant(
                    begin: state(opacity: 0, scale: 0.92),
                    end: .identity
                )
            )

        case .cover:
            // New screen slides in from `edge` (default bottom) over the old.
            return Participant.Pair(
                from: Participant(begin: .identity, end: .identity),
                to: Participant(
                    begin: state(translate: offscreen(edge, fraction: 1.0)),
                    end: .identity
                )
            )

        case .shared:
            // Backdrop only: the incoming screen's non-matched content fades in
            // over the outgoing one while matched elements morph on top. Authors
            // may override with explicit `from`/`to`.
            return Participant.Pair(
                from: Participant(begin: .identity, end: .identity),
                to: Participant(begin: state(opacity: 0), end: state(opacity: 1))
            )

        case .none, .system:
            return Participant.Pair(from: .identityPair, to: .identityPair)
        }
    }

    private static func defaultAnimation(for preset: Preset) -> DSL.Model.Animation.Inline {
        switch preset {
        case .slide:
            return DSL.Model.Animation.Inline(
                id: nil, duration: 0.35, delay: 0, timing: .curve(.easeInOut), options: []
            )
        case .fade, .crossDissolve:
            return DSL.Model.Animation.Inline(
                id: nil, duration: 0.3, delay: 0, timing: .curve(.easeInOut), options: []
            )
        case .scale, .zoom:
            return DSL.Model.Animation.Inline(
                id: nil, duration: 0.5, delay: 0,
                timing: .spring(.init(damping: 0.82, velocity: 0, mass: nil, stiffness: nil)),
                options: []
            )
        case .cover:
            return DSL.Model.Animation.Inline(
                id: nil, duration: 0.5, delay: 0,
                timing: .spring(.init(damping: 0.9, velocity: 0, mass: nil, stiffness: nil)),
                options: []
            )
        case .shared:
            return DSL.Model.Animation.Inline(
                id: nil, duration: 0.55, delay: 0,
                timing: .spring(.init(damping: 0.85, velocity: 0, mass: nil, stiffness: nil)),
                options: []
            )
        case .none, .system:
            return .instant
        }
    }

    // MARK: - Keyframe builders

    private static func state(
        opacity: Double? = nil,
        translate: Translation = .zero,
        scale: Double = 1,
        rotate: Double = 0
    ) -> TransitionState {
        TransitionState(
            opacity: opacity,
            translate: translate,
            scale: Scale(x: scale, y: scale),
            rotate: rotate,
            anchor: .center
        )
    }

    /// Off-screen translation of `fraction` container-dimensions toward `edge`.
    private static func offscreen(_ edge: Edge, fraction: Double) -> Translation {
        switch edge {
        case .trailing: return Translation(x: .fraction(fraction),  y: .points(0))
        case .leading:  return Translation(x: .fraction(-fraction), y: .points(0))
        case .bottom:   return Translation(x: .points(0), y: .fraction(fraction))
        case .top:      return Translation(x: .points(0), y: .fraction(-fraction))
        }
    }
}

// MARK: - Small helpers

extension DSL.Model.ScreenTransition.Edge {
    var opposite: Self {
        switch self {
        case .leading:  return .trailing
        case .trailing: return .leading
        case .top:      return .bottom
        case .bottom:   return .top
        }
    }
}

extension DSL.Model.ScreenTransition.Preset {
    /// Default entry edge for edge-based presets.
    var defaultEdge: DSL.Model.ScreenTransition.Edge {
        switch self {
        case .cover: return .bottom
        default:     return .trailing
        }
    }
}

extension DSL.Model.ScreenTransition.Participant {
    /// A participant that holds the identity state at both ends (no motion).
    static var identityPair: Self { .init(begin: .identity, end: .identity) }

    /// A forward `from`/`to` keyframe pair.
    struct Pair {
        var from: DSL.Model.ScreenTransition.Participant
        var to: DSL.Model.ScreenTransition.Participant
    }
}

extension DSL.Model.ScreenTransition.Resolved {
    /// Whether this resolves to an engine-driven animator (custom screen keyframes
    /// or a shared-element morph) rather than UIKit's native / instantaneous path.
    var isAnimated: Bool { kind == .custom || kind == .shared }

    /// Build the animator for this transition in the given direction. `.shared`
    /// morphs matched elements; everything else animates the screen keyframes.
    @MainActor
    func makeAnimator(direction: TransitionDirection) -> UIViewControllerAnimatedTransitioning {
        switch kind {
        case .shared:
            return SharedElementTransitionAnimator(resolved: self, direction: direction)
        case .custom, .none, .system:
            return PropertyTransitionAnimator(resolved: self, direction: direction)
        }
    }
}

extension DSL.Model.Animation.Inline {
    /// Zero-duration animation used for `none`/`system` transitions.
    static let instant = DSL.Model.Animation.Inline(
        id: nil, duration: 0, delay: 0, timing: .curve(.linear), options: []
    )

    /// Generic transition fallback timing when no preset / inline animation applies.
    static let transitionDefault = DSL.Model.Animation.Inline(
        id: nil, duration: 0.35, delay: 0, timing: .curve(.easeInOut), options: []
    )
}
