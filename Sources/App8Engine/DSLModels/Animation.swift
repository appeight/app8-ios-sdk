// Generic, declarative animation primitive driving state transitions and
// per-property variable-driven changes.

import UIKit
import QuartzCore

extension DSL.Model {

    /// An animation reference. Either an inline animation or a pointer to a
    /// named entry in the app-level `animations` registry. Resolution to the
    /// inline form happens at app load (mirrors the style pointer pattern).
    enum Animation: Decodable, Sendable {
        case inline(Inline)
        case pointer(String)

        /// Concrete inline animation. Carries everything the runner needs.
        struct Inline: Sendable {
            /// Identifier when this inline came from a wrapped form
            /// (`{ id, type, content }`). Nil for bare flat inline.
            var id: String?
            var duration: Double
            var delay: Double
            var timing: Timing
            var options: [Option]
        }

        /// Timing description. Spring is realized via UIView spring API or
        /// CASpringAnimation; cubic-bezier maps to CAMediaTimingFunction; named
        /// curves map to UIView.AnimationOptions / CAMediaTimingFunction.
        enum Timing: Sendable {
            case curve(NamedCurve)
            case cubicBezier(x1: Double, y1: Double, x2: Double, y2: Double)
            case spring(Spring)
        }

        enum NamedCurve: String, Decodable, Sendable {
            case linear
            case easeIn
            case easeOut
            case easeInOut
        }

        struct Spring: Decodable, Sendable {
            /// Damping fraction in `[0, 1]`. Lower = bouncier.
            var damping: Double
            /// Initial velocity. Positive values continue the gesture's direction.
            var velocity: Double
            /// Optional mass for `CASpringAnimation`. Ignored by `UIView` spring API.
            var mass: Double?
            /// Optional stiffness for `CASpringAnimation`. Ignored by `UIView` spring API.
            var stiffness: Double?
        }

        enum Option: String, Decodable, Sendable {
            case beginFromCurrent
            case allowUserInteraction
            case `repeat`
            case autoreverse
        }

        // MARK: - Decoding

        private enum WrapperKeys: String, CodingKey { case id, type, content }

        init(from decoder: any Decoder) throws {
            // Probe for wrapper keys (`id`, `content`); fall back to the flat inline form.
            let wrapper = try? decoder.container(keyedBy: WrapperKeys.self)
            let id = try wrapper?.decodeIfPresent(String.self, forKey: .id) ?? nil
            let hasContent = wrapper?.contains(.content) ?? false

            if let id, !hasContent {
                // Pure pointer. Try to resolve immediately via the
                // `app8AnimationResolver` registered in `decoder.userInfo`.
                // The production resolver (in `App8.swift`) is `@Sendable`;
                // tests sometimes hand in a non-Sendable closure. Try the
                // Sendable cast first, fall back to non-Sendable.
                let resolver: ((String) -> Inline?)? =
                    (decoder.userInfo[.app8AnimationResolver] as? @Sendable (String) -> Inline?)
                    ?? (decoder.userInfo[.app8AnimationResolver] as? (String) -> Inline?)
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

        // MARK: - Resolution

        /// Returns the inline form, resolving via the supplied registry resolver
        /// when this is a pointer. `nil` if the pointer cannot be resolved.
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

// MARK: - Inline decoding (flat form: legacy + extended)

extension DSL.Model.Animation.Inline: Decodable {

    private enum CodingKeys: String, CodingKey {
        case duration, delay, curve, cubicBezier, spring, options
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = nil
        self.duration = (try c.decodeIfPresent(Double.self, forKey: .duration)) ?? 0.25
        self.delay = (try c.decodeIfPresent(Double.self, forKey: .delay)) ?? 0
        self.options = (try c.decodeIfPresent([DSL.Model.Animation.Option].self, forKey: .options)) ?? []

        // Timing precedence: spring > cubicBezier > named curve. Default is easeInOut.
        if let spring = try c.decodeIfPresent(DSL.Model.Animation.Spring.self, forKey: .spring) {
            self.timing = .spring(spring)
        } else if let pts = try c.decodeIfPresent([Double].self, forKey: .cubicBezier), pts.count == 4 {
            self.timing = .cubicBezier(x1: pts[0], y1: pts[1], x2: pts[2], y2: pts[3])
        } else if let curveString = try c.decodeIfPresent(String.self, forKey: .curve) {
            // Legacy: `curve: "spring"` with no parameters maps to a default spring.
            if curveString == "spring" {
                self.timing = .spring(.defaultSpring)
            } else if let named = DSL.Model.Animation.NamedCurve(rawValue: curveString) {
                self.timing = .curve(named)
            } else {
                self.timing = .curve(.easeInOut)
            }
        } else {
            self.timing = .curve(.easeInOut)
        }
    }
}

// MARK: - Defaults

extension DSL.Model.Animation.Spring {
    /// Default spring used when JSON specifies `curve: "spring"` without
    /// parameters, or for any caller that wants a generic settle behavior.
    static let defaultSpring = DSL.Model.Animation.Spring(
        damping: 0.85,
        velocity: 0,
        mass: nil,
        stiffness: nil
    )
}

extension DSL.Model.Animation.Inline {
    /// Built-in animation used as a fallback for button press feedback when the
    /// component declares no `states`. Replaces the historical hardcoded 0.15s
    /// spring-ish in `CButtonView`.
    static let defaultPressFeedback = DSL.Model.Animation.Inline(
        id: nil,
        duration: 0.15,
        delay: 0,
        timing: .curve(.easeOut),
        options: []
    )

    /// Fallback timing for variable-driven `transform*` updates on `CView` when no
    /// per-property `animation` descriptor is supplied.
    static let legacyTransformVariableUpdate = DSL.Model.Animation.Inline(
        id: nil,
        duration: 0.3,
        delay: 0,
        timing: .spring(.init(damping: 0.75, velocity: 0.3, mass: nil, stiffness: nil)),
        options: []
    )

    /// Fallback timing for variable-driven `alpha` updates on `CView`.
    static let legacyAlphaVariableUpdate = DSL.Model.Animation.Inline(
        id: nil,
        duration: 0.25,
        delay: 0,
        timing: .curve(.easeOut),
        options: []
    )

    /// Generic ease-in-out fallback used when state transitions reset to base
    /// without a specific animation supplied. Matches the legacy default of the
    /// retired `StateAnimation.default`.
    static let defaultStateTransition = DSL.Model.Animation.Inline(
        id: nil,
        duration: 0.2,
        delay: 0,
        timing: .curve(.easeInOut),
        options: []
    )
}

extension DSL.Model.Animation {
    /// Generic default for callers that need *some* animation but don't have a
    /// specific descriptor. Used by `StateManager.resetToBase(animated:)`.
    static var `default`: DSL.Model.Animation {
        .inline(.defaultStateTransition)
    }
}

// MARK: - UIView / CALayer mapping helpers

extension DSL.Model.Animation.Inline {

    /// `UIView.AnimationOptions` derived from `options` plus the named curve
    /// (when applicable). Spring and cubic-bezier timings do **not** carry a
    /// curve mask through this property — the runner picks the spring API or a
    /// CATransaction with a custom timing function for those cases.
    var uiAnimationOptions: UIView.AnimationOptions {
        var opts: UIView.AnimationOptions = []
        for opt in options {
            switch opt {
            case .beginFromCurrent:    opts.insert(.beginFromCurrentState)
            case .allowUserInteraction: opts.insert(.allowUserInteraction)
            case .repeat:               opts.insert(.repeat)
            case .autoreverse:          opts.insert(.autoreverse)
            }
        }
        if case .curve(let named) = timing {
            switch named {
            case .linear:    opts.insert(.curveLinear)
            case .easeIn:    opts.insert(.curveEaseIn)
            case .easeOut:   opts.insert(.curveEaseOut)
            case .easeInOut: opts.insert(.curveEaseInOut)
            }
        }
        return opts
    }

    /// Timing function for layer animations and CATransaction. Returns nil when
    /// timing is spring (springs use CASpringAnimation, which carries its own).
    var caTimingFunction: CAMediaTimingFunction? {
        switch timing {
        case .spring:
            return nil
        case .curve(let named):
            switch named {
            case .linear:    return CAMediaTimingFunction(name: .linear)
            case .easeIn:    return CAMediaTimingFunction(name: .easeIn)
            case .easeOut:   return CAMediaTimingFunction(name: .easeOut)
            case .easeInOut: return CAMediaTimingFunction(name: .easeInEaseOut)
            }
        case .cubicBezier(let x1, let y1, let x2, let y2):
            return CAMediaTimingFunction(controlPoints: Float(x1), Float(y1), Float(x2), Float(y2))
        }
    }

    /// Spring parameters when timing is spring; nil otherwise.
    var springParameters: DSL.Model.Animation.Spring? {
        if case .spring(let s) = timing { return s }
        return nil
    }

    /// True when timing is spring-based.
    var isSpring: Bool { springParameters != nil }
}
