import UIKit

extension DSL.Model.Style {

    struct Corner: Decodable {
        typealias Entity = ConcreteEntity<Self>

        let radius: Radius
        let curve: Curve

        static var none: Corner {
            .init(radius: .fixed(0), curve: .circular)
        }

        /// Resolve the corner radius for a concrete layer/view size.
        func resolvedRadius(in size: CGSize) -> CGFloat {
            radius.resolved(in: size)
        }

        enum Curve: String, SafeEnumCodable {
            case circular, continuous
            static var unknownCase: Self { .circular }
            var ca: CALayerCornerCurve {
                switch self {
                case .circular: return .circular
                case .continuous: return .continuous
                }
            }
        }

        /// Corner radius — either an absolute point value or a fraction of the
        /// view's smaller dimension. A fraction stays correct under resize, so
        /// `0.5` always yields a perfect circle/capsule regardless of size.
        ///
        /// DSL forms:
        /// - bare number — `"radius": 12` → fixed points
        /// - percent string — `"radius": "50%"` → fraction (0.5)
        /// - keyed object — `"radius": { "type": "fraction", "value": 0.5 }`
        enum Radius: Decodable {
            /// Absolute radius in points.
            case fixed(CGFloat)
            /// Fraction of `min(width, height)`. `0.5` = full circle.
            case fraction(CGFloat)

            /// True when the resolved value depends on the view's size and so
            /// must be re-applied on every layout pass.
            var isRelative: Bool {
                if case .fraction = self { return true }
                return false
            }

            func resolved(in size: CGSize) -> CGFloat {
                switch self {
                case .fixed(let value):
                    return max(0, value)
                case .fraction(let fraction):
                    return max(0, min(size.width, size.height) * fraction)
                }
            }

            private enum CodingKeys: String, CodingKey { case type, value }
            private enum RadiusType: String, Decodable { case fixed, fraction }

            init(from decoder: any Decoder) throws {
                if let single = try? decoder.singleValueContainer() {
                    // Shorthand: bare number → fixed points.
                    if let number = try? single.decode(CGFloat.self) {
                        self = .fixed(number)
                        return
                    }
                    // Shorthand: "50%" → fraction of the smaller dimension.
                    if let string = try? single.decode(String.self),
                       string.hasSuffix("%"),
                       let percent = Double(string.dropLast()) {
                        self = .fraction(CGFloat(percent) / 100)
                        return
                    }
                }
                // Keyed form: { "type": "fixed" | "fraction", "value": N }
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let type = try container.decode(RadiusType.self, forKey: .type)
                let value = try container.decode(CGFloat.self, forKey: .value)
                switch type {
                case .fixed:    self = .fixed(value)
                case .fraction: self = .fraction(value)
                }
            }
        }
    }
}

extension CALayer {

    /// Apply a corner style, resolving a `fraction` radius against this layer's
    /// current `bounds`. Callers must re-invoke this after the layer is resized
    /// — the engine does this from `layoutSubviews` (see `MaterialView`).
    func apply(cornerStyle: DSL.Model.Style.Corner) {
        apply(cornerStyle: cornerStyle, in: bounds.size)
    }

    /// Apply a corner style, resolving a `fraction` radius against an explicit
    /// `size`. Used when the layer's own `bounds` are not yet up to date for
    /// the current layout pass (e.g. a layer nested below the component view —
    /// see `App8BaseView.layoutSubviews`).
    func apply(cornerStyle: DSL.Model.Style.Corner, in size: CGSize) {
        let radius = cornerStyle.resolvedRadius(in: size)
        masksToBounds = radius > 0
        cornerRadius = radius
        cornerCurve = cornerStyle.curve.ca
    }
}
