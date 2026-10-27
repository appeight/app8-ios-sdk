import UIKit

extension DSL.Model.Style {

    protocol BaseStyleProtocol {
        var contentMode: View.ContentMode? { get }
        var material: Material? { get }
        var alpha: CGFloat? { get }
        var transform: View.Transform? { get }
        var blendMode: View.BlendMode? { get }
    }
}

extension DSL.Model.Style.BaseStyleProtocol {
    /// Only view and image styles carry a blend mode; every other style
    /// composites normally.
    var blendMode: DSL.Model.Style.View.BlendMode? { nil }
}

extension DSL.Model.Style {

    struct View: Decodable, BaseStyleProtocol, StylePointerResolvable, CustomDecodable {

        private(set) var contentMode: ContentMode?
        @Wrapped var material: Material?
        private(set) var alpha: CGFloat?
        private(set) var transform: Transform?
        private(set) var blendMode: BlendMode?

        static func decode<CodingKeys: CodingKey>(fromContainer container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Self {
            if container.contains(key) {
                return try container.decode(Self.self, forKey: key)
            } else {
                return .init()
            }
        }
        
        mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
            _material.resolvePointer(type: .key(.material), resolver: resolver)
        }

        func isResolved() -> Bool {
            material?.isResolved() ?? false
        }

        func unresolvedPointerIds() -> [String] {
            _material.unresolvedPointerIds()
        }

        /// Transform for animations (translateY, scale, rotation)
        struct Transform: Decodable, Sendable {
            let translateY: CGFloat?
            let scale: CGFloat?
            let rotation: CGFloat?  // Rotation in degrees

            var affineTransform: CGAffineTransform {
                var t = CGAffineTransform.identity
                if let translateY {
                    t = t.translatedBy(x: 0, y: translateY)
                }
                if let scale {
                    t = t.scaledBy(x: scale, y: scale)
                }
                if let rotation {
                    t = t.rotated(by: rotation * .pi / 180)  // Convert degrees to radians
                }
                return t
            }
        }

        /// How the view composites with what's rendered beneath it (the
        /// Figma / CSS `mix-blend-mode` set). Applied as the layer's
        /// `compositingFilter`; `normal` clears it.
        enum BlendMode: String, SafeEnumCodable, Sendable {
            case normal
            case multiply
            case screen
            case overlay
            case darken
            case lighten
            case colorDodge
            case colorBurn
            case softLight
            case hardLight
            case difference
            case exclusion
            case hue
            case saturation
            case color
            case luminosity

            static var unknownCase: Self { .normal }

            /// Core Image compositing filter name, nil for `normal`.
            var compositingFilter: String? {
                switch self {
                case .normal: return nil
                case .multiply: return "multiplyBlendMode"
                case .screen: return "screenBlendMode"
                case .overlay: return "overlayBlendMode"
                case .darken: return "darkenBlendMode"
                case .lighten: return "lightenBlendMode"
                case .colorDodge: return "colorDodgeBlendMode"
                case .colorBurn: return "colorBurnBlendMode"
                case .softLight: return "softLightBlendMode"
                case .hardLight: return "hardLightBlendMode"
                case .difference: return "differenceBlendMode"
                case .exclusion: return "exclusionBlendMode"
                case .hue: return "hueBlendMode"
                case .saturation: return "saturationBlendMode"
                case .color: return "colorBlendMode"
                case .luminosity: return "luminosityBlendMode"
                }
            }
        }

        enum ContentMode: String, Decodable, MappedCodableBridge {
            typealias MappedValue = UIView.ContentMode
            static var mappedKeyPath: KeyPath<Self, MappedValue> { \.ui }
            
            case scaleToFill
            case scaleAspectFit
            case scaleAspectFill
            case redraw
            case center
            case top
            case bottom
            case left
            case right
            case topLeft
            case topRight
            case bottomLeft
            case bottomRight
            
            var ui: UIView.ContentMode {
                switch self {
                case .scaleToFill: return .scaleToFill
                case .scaleAspectFit: return .scaleAspectFit
                case .scaleAspectFill: return .scaleAspectFill
                case .redraw: return .redraw
                case .center: return .center
                case .top: return .top
                case .bottom: return .bottom
                case .left: return .left
                case .right: return .right
                case .topLeft: return .topLeft
                case .topRight: return .topRight
                case .bottomLeft: return .bottomLeft
                case .bottomRight: return .bottomRight
                }
            }
            
            init(_ mappedValue: MappedValue) {
                switch mappedValue {
                case .scaleToFill:
                    self = .scaleToFill
                case .scaleAspectFit:
                    self = .scaleAspectFit
                case .scaleAspectFill:
                    self = .scaleAspectFill
                case .redraw:
                    self = .redraw
                case .center:
                    self = .center
                case .top:
                    self = .top
                case .bottom:
                    self = .bottom
                case .left:
                    self = .left
                case .right:
                    self = .right
                case .topLeft:
                    self = .topLeft
                case .topRight:
                    self = .topRight
                case .bottomLeft:
                    self = .bottomLeft
                case .bottomRight:
                    self = .bottomRight
                @unknown default:
                    self = .scaleAspectFit
                }
            }
        }
    }
}
