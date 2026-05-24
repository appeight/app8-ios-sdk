import UIKit

extension DSL.Model {

    public struct Layout: Decodable, Sendable {
        var width: Dimension?
        var height: Dimension?
        var leading: Dimension?
        var trailing: Dimension?
        var top: Dimension?
        var bottom: Dimension?
        var ignoresSafeArea: Bool?
        @SafeOptionalArrayDecodable
        var constraints: [Constraint]? = nil
        /// Per-axis content hugging priorities. Only specified axes are applied;
        /// unspecified axes preserve UIKit defaults (e.g. UILabel's vertical hugging).
        var contentHuggingPriority: AxisPriority?
        /// Per-axis content compression resistance priorities. Only specified axes are applied.
        var contentCompressionResistancePriority: AxisPriority?

        static var fillSuperview: Layout {
            return Layout(
                width: nil, height: nil,
                leading: .fixed(0), trailing: .fixed(0),
                top: .fixed(0), bottom: .fixed(0),
                ignoresSafeArea: nil, constraints: [],
                contentHuggingPriority: nil,
                contentCompressionResistancePriority: nil
            )
        }

        /// True when the layout object carries no positioning or sizing information.
        /// An empty `{}` JSON object decodes to this state and should behave like `nil`.
        var isEmpty: Bool {
            width == nil && height == nil &&
            leading == nil && trailing == nil &&
            top == nil && bottom == nil &&
            ignoresSafeArea == nil &&
            (constraints ?? []).isEmpty &&
            contentHuggingPriority == nil &&
            contentCompressionResistancePriority == nil
        }
        
        enum Dimension: Decodable {
            case fixed(Float), fraction(Float), expression(String)

            private enum CodingKeys: String, CodingKey {
                case type, value
            }

            private enum DimensionType: String, Decodable {
                case fixed, fraction, expression
            }

            init(from decoder: any Decoder) throws {
                // Shorthand: bare number → fixed.
                if let container = try? decoder.singleValueContainer(),
                   let floatValue = try? container.decode(Float.self) {
                    self = .fixed(floatValue)
                    return
                }

                // Shorthand: bare "{{...}}" string → expression.
                if let container = try? decoder.singleValueContainer(),
                   let stringValue = try? container.decode(String.self),
                   stringValue.contains("{{") {
                    self = .expression(stringValue)
                    return
                }

                let container = try decoder.container(keyedBy: CodingKeys.self)
                let type = try container.decode(DimensionType.self, forKey: .type)

                switch type {
                case .fixed:
                    let value = try container.decode(Float.self, forKey: .value)
                    self = .fixed(value)
                case .fraction:
                    let value = try container.decode(Float.self, forKey: .value)
                    self = .fraction(value)
                case .expression:
                    let value = try container.decode(String.self, forKey: .value)
                    self = .expression(value)
                }
            }
        }
    }
}

extension DSL.Model.Layout {

    /// A single constraint. When `target` is omitted, `type` must be `.width` or
    /// `.height` and the constraint applies to the view itself (e.g. a min-height clamp).
    public struct Constraint: Decodable, Sendable {
        let type: Attribute
        let target: Target?
        var attribute: Attribute?
        var constant: Float?
        var multiplier: Float?
        /// Relation between the two sides. Tiny field name (`op`) chosen for LLM-generated DSL.
        var op: Relation?
        /// Priority for the resulting NSLayoutConstraint. Reuses the same
        /// `PriorityValue` decoder as `contentHuggingPriority`.
        var priority: PriorityValue?

        enum Attribute: String, Decodable {
            case leading, trailing, top, bottom, centerX, centerY, width, height
        }

        /// Decodes from `"="` (default if omitted), `"<="`, `">="`.
        public enum Relation: String, Decodable, Sendable {
            case equal = "="
            case lessThanOrEqual = "<="
            case greaterThanOrEqual = ">="
        }

        enum Target: Decodable {
            case superview, sibling(String), keyboard, selfView
            /// Safe-area layout guide. `nil` anchors to the superview's safe area
            /// (`"safeArea"`); a non-nil id anchors to the safe area of the sibling
            /// component with that id (`"safeArea(headerBar)"`).
            case safeArea(String?)

            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                let targetString = try container.decode(String.self)
                switch targetString.lowercased() {
                case "superview":
                    self = .superview
                case "keyboard":
                    self = .keyboard
                case "safearea":
                    self = .safeArea(nil)
                case "self":
                    self = .selfView
                default:
                    if let siblingId = Self.safeAreaSiblingId(in: targetString) {
                        self = .safeArea(siblingId)
                    } else {
                        self = .sibling(targetString)
                    }
                }
            }

            /// Parses the `safeArea(<id>)` form. The `safeArea` keyword is matched
            /// case-insensitively; the inner id is returned verbatim because
            /// sibling ids are case-sensitive. Returns `nil` for any other string.
            private static func safeAreaSiblingId(in raw: String) -> String? {
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                guard trimmed.lowercased().hasPrefix("safearea("),
                      trimmed.hasSuffix(")") else { return nil }
                let start = trimmed.index(trimmed.startIndex, offsetBy: "safearea(".count)
                let end = trimmed.index(before: trimmed.endIndex)
                let id = trimmed[start..<end].trimmingCharacters(in: .whitespaces)
                return id.isEmpty ? nil : id
            }
        }
    }
}

// MARK: - Content priority

extension DSL.Model.Layout {

    /// Per-axis content priority. Either axis may be nil — only specified axes
    /// are applied to the view.
    public struct AxisPriority: Decodable, Sendable, Equatable {
        let h: PriorityValue?
        let v: PriorityValue?
    }

    /// Decodes from either a named priority (`"defaultHigh"`) or a raw `Float` (e.g. `749`).
    public enum PriorityValue: Decodable, Sendable, Equatable {
        case named(Named)
        case custom(Float)

        public enum Named: String, Decodable, Sendable {
            case required
            case defaultHigh
            case defaultLow
            case fittingSizeLevel
            case dragThatCanResizeScene
            case sceneSizeStayPut
            case dragThatCannotResizeScene
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let f = try? c.decode(Float.self) {
                self = .custom(f)
                return
            }
            if let s = try? c.decode(String.self), let n = Named(rawValue: s) {
                self = .named(n)
                return
            }
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Expected a named priority string or a numeric Float"
            )
        }

        var ui: UILayoutPriority {
            switch self {
            case .custom(let f):
                return UILayoutPriority(f)
            case .named(let n):
                switch n {
                case .required:                   return .required
                case .defaultHigh:                return .defaultHigh
                case .defaultLow:                 return .defaultLow
                case .fittingSizeLevel:           return .fittingSizeLevel
                case .dragThatCanResizeScene:     return .dragThatCanResizeScene
                case .sceneSizeStayPut:           return .sceneSizeStayPut
                case .dragThatCannotResizeScene:  return .dragThatCannotResizeScene
                }
            }
        }
    }
}

