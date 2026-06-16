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
        /// Sized-modal container geometry + chrome. Nil ⇒ full-screen modal.
        var presentation: ResolvedModalPresentation?
    }

    struct ResolvedDimming {
        var color: UIColor
        var opacity: Double
        /// Whether a backdrop tap dismisses the modal.
        var dismissOnTap: Bool
    }

    /// Concrete sized-modal geometry + chrome, consumed on the main actor by the
    /// presentation controller. All dimensions are resolved against the live
    /// container at layout time (so it stays correct under rotation / keyboard).
    struct ResolvedModalPresentation {
        var width: ModalDimension
        var height: ModalDimension
        var align: ModalAlign
        var margin: ModalInsets
        var corner: DSL.Model.Style.Corner?
        var shadow: DSL.Model.Style.Shadow?
        var ignoresSafeArea: Bool
        var avoidsKeyboard: Bool

        /// The presented container frame within `bounds`, honoring the safe area
        /// (unless ignored), margins, alignment, and an optional keyboard inset
        /// (subtracted from the bottom of the available area).
        func frame(in bounds: CGRect, safeArea: UIEdgeInsets, keyboardHeight: CGFloat) -> CGRect {
            var available = ignoresSafeArea ? bounds : bounds.inset(by: safeArea)
            available = available.inset(by: UIEdgeInsets(
                top: margin.top, left: margin.leading, bottom: margin.bottom, right: margin.trailing
            ))
            if keyboardHeight > 0 {
                let overlap = max(0, available.maxY - (bounds.maxY - keyboardHeight))
                available.size.height = max(0, available.height - overlap)
            }

            let w = min(resolve(width, available: available.width, cross: nil), available.width)
            let h = min(resolve(height, available: available.height, cross: w), available.height)
            let size = CGSize(width: max(0, w), height: max(0, h))

            let x: CGFloat
            switch align {
            case .leading:  x = available.minX
            case .trailing: x = available.maxX - size.width
            case .center, .top, .bottom: x = available.midX - size.width / 2
            }
            let y: CGFloat
            switch align {
            case .top:    y = available.minY
            case .bottom: y = available.maxY - size.height
            case .center, .leading, .trailing: y = available.midY - size.height / 2
            }
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        }

        private func resolve(_ dimension: ModalDimension, available: CGFloat, cross: CGFloat?) -> CGFloat {
            switch dimension {
            case .points(let p):   return CGFloat(p)
            case .fraction(let f): return CGFloat(f) * available
            case .fill:            return available
            case .ratio(let r):    return (cross ?? available) * CGFloat(r)
            }
        }
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
                reverseFrom: nil, reverseTo: nil, dimming: nil, interactive: nil,
                presentation: nil
            )
        }
        if preset == Preset.none {
            return Resolved(
                kind: .none, mode: mode, edge: edge, raise: raise,
                animation: .instant,
                from: .identityPair, to: .identityPair,
                reverseFrom: nil, reverseTo: nil, dimming: nil, interactive: nil,
                presentation: nil
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

        // Sized-modal presets seed a default backdrop dim + (sheet) swipe-dismiss;
        // the author's own `dimming`/`interactive` still win when present.
        let dimmingSource = inline.dimming ?? preset.flatMap(defaultDimming(for:))
        let dimming = dimmingSource.map {
            ResolvedDimming(
                color: ($0.color ?? .init("#000000")).ui,
                opacity: $0.opacity,
                dismissOnTap: $0.dismissOnTap
            )
        }
        let interactive = inline.interactive ?? preset.flatMap(defaultInteractive(for:))

        // Sized-modal geometry: the preset's default container (popup / sheet),
        // overlaid field-by-field with any author `presentation`, then resolved.
        let presetPresentation = preset.flatMap(defaultPresentation(for:))
        let presentationModel: ModalPresentation? = {
            switch (presetPresentation, inline.presentation) {
            case (let base?, let override): return base.merging(override)
            case (nil, let override):       return override
            }
        }()
        let presentation = presentationModel.map(resolvePresentation)

        // The `shared` preset routes to the shared-element animator; its `from`/
        // `to` keyframes describe the *backdrop* motion (the non-matched content),
        // while matched elements morph on top per their own `ElementTransition`.
        let kind: Resolved.Kind = (preset == Preset.shared) ? .shared : .custom

        return Resolved(
            kind: kind, mode: mode, edge: edge, raise: raise,
            animation: resolvedAnimation,
            from: from, to: to,
            reverseFrom: reverseFrom, reverseTo: reverseTo,
            dimming: dimming, interactive: interactive,
            presentation: presentation
        )
    }

    /// Fill a `ModalPresentation`'s gaps with hard defaults (centered 86%-wide card).
    private static func resolvePresentation(_ m: ModalPresentation) -> ResolvedModalPresentation {
        ResolvedModalPresentation(
            width: m.width ?? .fraction(0.86),
            height: m.height ?? .ratio(0.62),
            align: m.align ?? .center,
            margin: m.margin ?? .zero,
            corner: m.corner,
            shadow: m.shadow,
            ignoresSafeArea: m.ignoresSafeArea ?? false,
            avoidsKeyboard: m.avoidsKeyboard ?? true
        )
    }

    // MARK: - Sized-modal preset defaults

    /// Default container geometry + chrome for the sized-modal presets.
    private static func defaultPresentation(for preset: Preset) -> ModalPresentation? {
        switch preset {
        case .popup:
            return ModalPresentation(
                width: .fraction(0.86), height: .ratio(0.62), align: .center, margin: .zero,
                corner: .init(radius: .fixed(28), curve: .continuous),
                shadow: defaultModalShadow, ignoresSafeArea: false, avoidsKeyboard: true
            )
        case .sheet:
            // No shadow: a bottom sheet hugs the screen edge, and the soft blurred
            // halo reads as an unwanted gradient over the (uniform) dimming. Authors
            // can still add one explicitly via `presentation.shadow`.
            return ModalPresentation(
                width: .fill, height: .fraction(0.5), align: .bottom, margin: .zero,
                corner: .init(radius: .fixed(24), curve: .continuous),
                shadow: nil, ignoresSafeArea: true, avoidsKeyboard: true
            )
        default:
            return nil
        }
    }

    /// Default backdrop dim for sized-modal presets.
    private static func defaultDimming(for preset: Preset) -> DSL.Model.ScreenTransition.Dimming? {
        switch preset {
        case .popup, .sheet: return .init(opacity: 0.45)
        default:             return nil
        }
    }

    /// Default interactive dismiss for sized-modal presets (sheet swipes down).
    private static func defaultInteractive(for preset: Preset) -> InteractiveConfig? {
        switch preset {
        case .sheet: return .init(enabled: true, edge: .bottom, threshold: 0.3, velocity: 800)
        default:     return nil
        }
    }

    private static var defaultModalShadow: DSL.Model.Style.Shadow {
        DSL.Model.Style.Shadow(.black, 30, CGSize(width: 0, height: 12), 0.22)
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

        case .scale, .zoom, .popup:
            // New screen/card scales up from 92% while fading in.
            return Participant.Pair(
                from: Participant(begin: .identity, end: .identity),
                to: Participant(
                    begin: state(opacity: 0, scale: 0.92),
                    end: .identity
                )
            )

        case .cover, .sheet:
            // New screen/card slides in from `edge` (default bottom) over the old.
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
        case .scale, .zoom, .popup:
            return DSL.Model.Animation.Inline(
                id: nil, duration: 0.5, delay: 0,
                timing: .spring(.init(damping: 0.82, velocity: 0, mass: nil, stiffness: nil)),
                options: []
            )
        case .cover, .sheet:
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
        case .cover, .sheet: return .bottom
        default:             return .trailing
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
