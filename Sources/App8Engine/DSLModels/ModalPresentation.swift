// Declarative geometry + chrome for a *sized* modal presentation.
//
// A `ScreenTransition` with `mode: modal` may carry a `presentation` block that
// describes the presented container's frame (relatively or absolutely, like
// layout) and its chrome (corner radius, shadow). Without it, a modal covers the
// whole container as before — so the block is purely additive.
//
// Motion stays on the transition (`preset` / `from` / `to` / `animation`); this
// block is only about *where* and *how big* the container sits and how it is
// clipped. The presented screen's own `style.material` remains its background, so
// there is no second styling system here — only `corner` (reusing `Style.Corner`)
// and `shadow` (reusing `Style.Shadow`).

import UIKit

extension DSL.Model.ScreenTransition {

    /// Container geometry + chrome for a sized modal. All fields optional so a
    /// preset (`popup` / `sheet`) can seed defaults and the author overrides only
    /// what differs.
    struct ModalPresentation: Decodable, Sendable {
        /// Container width. Default `.fraction(0.86)` (see `Resolved` defaults).
        var width: ModalDimension?
        /// Container height. `.ratio` is valid here (a multiple of the resolved
        /// width); default `.ratio(0.62)`.
        var height: ModalDimension?
        /// Where the sized box sits in the available area. Default `.center`.
        var align: ModalAlign?
        /// Margins inset from the available area (safe area, unless
        /// `ignoresSafeArea`). Default `.zero`.
        var margin: ModalInsets?
        /// Corner radius + curve clipped onto the container. Reuses `Style.Corner`.
        var corner: DSL.Model.Style.Corner?
        /// Drop shadow rendered behind the (clipped) container. Reuses
        /// `Style.Shadow`. Colors should be inline (hex), like `dimming`.
        var shadow: DSL.Model.Style.Shadow?
        /// Lay the container out within the full container bounds rather than the
        /// safe area. Default `false`.
        var ignoresSafeArea: Bool?
        /// Re-center the container above the keyboard when it appears. Default `true`.
        var avoidsKeyboard: Bool?

        private enum CodingKeys: String, CodingKey {
            case width, height, align, margin, corner, shadow, ignoresSafeArea, avoidsKeyboard
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.width = try c.decodeIfPresent(ModalDimension.self, forKey: .width)
            self.height = try c.decodeIfPresent(ModalDimension.self, forKey: .height)
            self.align = try c.decodeIfPresent(ModalAlign.self, forKey: .align)
            self.margin = try c.decodeIfPresent(ModalInsets.self, forKey: .margin)
            self.corner = try Self.decodeCorner(c, forKey: .corner)
            self.shadow = try c.decodeIfPresent(DSL.Model.Style.Shadow.self, forKey: .shadow)
            self.ignoresSafeArea = try c.decodeIfPresent(Bool.self, forKey: .ignoresSafeArea)
            self.avoidsKeyboard = try c.decodeIfPresent(Bool.self, forKey: .avoidsKeyboard)
        }

        init(
            width: ModalDimension? = nil,
            height: ModalDimension? = nil,
            align: ModalAlign? = nil,
            margin: ModalInsets? = nil,
            corner: DSL.Model.Style.Corner? = nil,
            shadow: DSL.Model.Style.Shadow? = nil,
            ignoresSafeArea: Bool? = nil,
            avoidsKeyboard: Bool? = nil
        ) {
            self.width = width
            self.height = height
            self.align = align
            self.margin = margin
            self.corner = corner
            self.shadow = shadow
            self.ignoresSafeArea = ignoresSafeArea
            self.avoidsKeyboard = avoidsKeyboard
        }

        /// Lenient corner decode — a *superset* of `Style.Corner` so a transition
        /// can write the common shorthands without a mandatory `curve`:
        /// `28` · `"50%"` · `{ "radius": 28 }` · `{ "radius": 28, "curve": "circular" }`.
        /// `curve` defaults to `continuous`.
        private static func decodeCorner(
            _ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys
        ) throws -> DSL.Model.Style.Corner? {
            guard c.contains(key), (try? c.decodeNil(forKey: key)) == false else { return nil }
            // Full `{ radius, curve }` form.
            if let full = try? c.decode(DSL.Model.Style.Corner.self, forKey: key) { return full }
            // Bare radius (`28` / `"50%"` / `{ type, value }`).
            if let radius = try? c.decode(DSL.Model.Style.Corner.Radius.self, forKey: key) {
                return DSL.Model.Style.Corner(radius: radius, curve: .continuous)
            }
            // Object with optional curve (`{ radius, curve? }`).
            let nested = try c.nestedContainer(keyedBy: CornerKeys.self, forKey: key)
            let radius = try nested.decode(DSL.Model.Style.Corner.Radius.self, forKey: .radius)
            let curve = (try nested.decodeIfPresent(DSL.Model.Style.Corner.Curve.self, forKey: .curve)) ?? .continuous
            return DSL.Model.Style.Corner(radius: radius, curve: curve)
        }

        private enum CornerKeys: String, CodingKey { case radius, curve }

        /// Field-by-field overlay of `override` onto `self` (override wins where
        /// present). Lets a `sheet` preset's defaults be tweaked one field at a
        /// time (`{ "preset": "sheet", "presentation": { "height": "50%" } }`).
        func merging(_ override: ModalPresentation?) -> ModalPresentation {
            guard let override else { return self }
            return ModalPresentation(
                width: override.width ?? width,
                height: override.height ?? height,
                align: override.align ?? align,
                margin: override.margin ?? margin,
                corner: override.corner ?? corner,
                shadow: override.shadow ?? shadow,
                ignoresSafeArea: override.ignoresSafeArea ?? ignoresSafeArea,
                avoidsKeyboard: override.avoidsKeyboard ?? avoidsKeyboard
            )
        }
    }

    /// One axis of a modal container's size.
    ///
    /// DSL forms:
    /// - number — `320` → absolute points
    /// - percent string — `"86%"` → fraction of the available axis
    /// - `"fill"` — fill the available axis
    /// - `{ "ratio": 0.62 }` — (height only) a multiple of the *resolved width*
    /// - `{ "points": n }` / `{ "fraction": f }` — explicit keyed forms
    enum ModalDimension: Decodable, Sendable, Equatable {
        /// Absolute points.
        case points(Double)
        /// Fraction `0…1` of the available axis (container/safe area minus margin).
        case fraction(Double)
        /// (Height only) a multiple of the resolved width — an aspect lock.
        case ratio(Double)
        /// Fill the available axis.
        case fill

        private enum CodingKeys: String, CodingKey { case points, fraction, ratio, fill }

        init(from decoder: any Decoder) throws {
            // Scalar form: number → points; "NN%" → fraction; "fill" → fill.
            if let single = try? decoder.singleValueContainer() {
                if let number = try? single.decode(Double.self) {
                    self = .points(number)
                    return
                }
                if let string = try? single.decode(String.self) {
                    let trimmed = string.trimmingCharacters(in: .whitespaces).lowercased()
                    if trimmed == "fill" {
                        self = .fill
                        return
                    }
                    if trimmed.hasSuffix("%"), let pct = Double(trimmed.dropLast()) {
                        self = .fraction(pct / 100)
                        return
                    }
                    if let number = Double(trimmed) {
                        self = .points(number)
                        return
                    }
                }
            }
            // Keyed form: { ratio | points | fraction }.
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let r = try c.decodeIfPresent(Double.self, forKey: .ratio) {
                self = .ratio(r)
            } else if let p = try c.decodeIfPresent(Double.self, forKey: .points) {
                self = .points(p)
            } else if let f = try c.decodeIfPresent(Double.self, forKey: .fraction) {
                self = .fraction(f)
            } else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid modal dimension"
                ))
            }
        }
    }

    /// Where the sized container anchors in the available area. The named edge is
    /// the primary axis; the cross axis is centered. `center` centers both.
    enum ModalAlign: String, SafeEnumCodable, Sendable {
        case center
        case top
        case bottom
        case leading
        case trailing
        static var unknownCase: Self { .center }
    }

    /// Margins inset from the available area. Decodes from a single number
    /// (uniform) or a per-edge object.
    struct ModalInsets: Decodable, Sendable, Equatable {
        var top: CGFloat
        var bottom: CGFloat
        var leading: CGFloat
        var trailing: CGFloat

        static let zero = ModalInsets(top: 0, bottom: 0, leading: 0, trailing: 0)

        init(top: CGFloat, bottom: CGFloat, leading: CGFloat, trailing: CGFloat) {
            self.top = top
            self.bottom = bottom
            self.leading = leading
            self.trailing = trailing
        }

        init(uniform value: CGFloat) {
            self.init(top: value, bottom: value, leading: value, trailing: value)
        }

        private enum CodingKeys: String, CodingKey { case top, bottom, leading, trailing }

        init(from decoder: any Decoder) throws {
            if let single = try? decoder.singleValueContainer(), let v = try? single.decode(CGFloat.self) {
                self.top = v; self.bottom = v; self.leading = v; self.trailing = v
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.top = (try c.decodeIfPresent(CGFloat.self, forKey: .top)) ?? 0
            self.bottom = (try c.decodeIfPresent(CGFloat.self, forKey: .bottom)) ?? 0
            self.leading = (try c.decodeIfPresent(CGFloat.self, forKey: .leading)) ?? 0
            self.trailing = (try c.decodeIfPresent(CGFloat.self, forKey: .trailing)) ?? 0
        }
    }
}
