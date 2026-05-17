import UIKit

extension DSL.Model.Style {

    struct Shadow: Decodable, StylePointerResolvable {
        typealias Entity = ConcreteEntity<Self>

        @SafeArrayDecodable
        var layers: [Layer]

        mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
            for i in 0..<layers.count {
                layers[i].resolveStylePointers(resolver: resolver)
            }
        }

        func isResolved() -> Bool {
            layers.allSatisfy { $0.color.isResolved() }
        }

        func unresolvedPointerIds() -> [String] {
            layers.flatMap { $0.unresolvedPointerIds() }
        }
        
        /// Single-layer convenience initializer.
        init(_ color: UIColor, _ radius: CGFloat, _ offset: CGSize = .zero, _ opacity: CGFloat = 1, isHollow: Bool = true) {
            self.layers = [Layer(color, radius, offset, opacity, isHollow: isHollow)]
        }
        
        init(multilayered: [Layer]) {
            self.layers = multilayered
        }
        
        var debugDescription: String {
            let layers = layers.map(\.debugDescription)
            return "layers: [\(layers.joined(separator: "\n"))]"
        }

        struct Layer: Decodable, Sendable, Equatable, StylePointerResolvable {
            var color: Color.Themed
            let radius: CGFloat
            var offset: Offset
            let opacity: CGFloat
            var isHollow: Bool = true

            var debugDescription: String {
                return "Style.Shadow.Layer(color: \(color), radius: \(radius), offset: \(offset), opacity: \(opacity), isHollow: \(isHollow)"
            }

            enum CodingKeys: String, CodingKey {
                case color, radius, offset, opacity, isHollow
            }

            struct Offset: Decodable, Equatable, MappedCodableBridge {
                let x, y: CGFloat
                var cgSize: CGSize {
                    CGSize(width: x, height: y)
                }
                static var mappedKeyPath: KeyPath<Self, MappedValue> { \.cgSize }
                init(_ mappedValue: CGSize) {
                    x = mappedValue.width
                    y = mappedValue.height
                }
            }
            
            init(_ color: UIColor, _ radius: CGFloat, _ offset: CGSize = .zero, _ opacity: CGFloat = 1, isHollow: Bool = true) {
                self.color = .init(color)
                self.radius = radius
                self.offset = .init(offset)
                self.opacity = opacity
                self.isHollow = isHollow
            }
            
            mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
                color.resolveStylePointers(resolver: resolver)
            }

            func isResolved() -> Bool {
                color.isResolved()
            }

            func unresolvedPointerIds() -> [String] {
                color.unresolvedPointerIds()
            }

            static func == (lhs: Layer, rhs: Layer) -> Bool {
                return lhs.color == rhs.color
                && lhs.radius == rhs.radius
                && lhs.offset == rhs.offset
                && lhs.opacity == rhs.opacity
                && lhs.isHollow == rhs.isHollow
            }
        }
        
        struct AnimationOptions {
            let setFromValues: Bool
            static let `default` = AnimationOptions(setFromValues: false)
        }
    }
}

// MARK: - Shadow Applicable

extension DSL.Model.Style.Shadow {

    protocol Applicable {
        @MainActor func apply(shadowStyle: DSL.Model.Style.Shadow?, animationOptions: AnimationOptions?)
        @MainActor func removeShadow()
    }
}

extension DSL.Model.Style.Shadow.Applicable {

    @MainActor func apply(shadowStyle: DSL.Model.Style.Shadow?, animationOptions: DSL.Model.Style.Shadow.AnimationOptions? = .default) {
        apply(shadowStyle: shadowStyle, animationOptions: animationOptions)
    }
}

// MARK: - UI Extensions

extension UIView: DSL.Model.Style.Shadow.Applicable {
    
    @MainActor func apply(shadowStyle: DSL.Model.Style.Shadow?) {
        layer.apply(shadowStyle: shadowStyle)
    }
    
    @MainActor func removeShadow() {
        layer.removeShadow()
    }
}

fileprivate var shadowLayerPrefix: String { "shadow_layer_" }

extension CALayer: DSL.Model.Style.Shadow.Applicable {
    
    func apply(shadowStyle: DSL.Model.Style.Shadow?, animationOptions: DSL.Model.Style.Shadow.AnimationOptions? = nil) {
        guard let shadowStyle = shadowStyle else {
            removeShadow()
            return
        }
        
        let animated = animationOptions != nil
        guard let singleLayer = shadowStyle.layers.first, shadowStyle.layers.count == 1 else {
            // TODO: Handle multi-layer shadows
            return
        }
        if let animationOptions {
            let groupAnimation = CAAnimationGroup()
            var animations: [CABasicAnimation] = []

            let colorAnimation = CABasicAnimation(keyPath: "shadowColor")
            colorAnimation.fromValue = shadowColor
            colorAnimation.toValue = singleLayer.color.ui.cgColor
            animations.append(colorAnimation)

            let radiusAnimation = CABasicAnimation(keyPath: "shadowRadius")
            radiusAnimation.fromValue = shadowRadius
            radiusAnimation.toValue = singleLayer.radius
            animations.append(radiusAnimation)

            let offsetAnimation = CABasicAnimation(keyPath: "shadowOffset")
            offsetAnimation.fromValue = NSValue(cgSize: shadowOffset)
            offsetAnimation.toValue = NSValue(cgSize: singleLayer.offset.cgSize)
            animations.append(offsetAnimation)

            let opacityAnimation = CABasicAnimation(keyPath: "shadowOpacity")
            opacityAnimation.fromValue = shadowOpacity
            opacityAnimation.toValue = Float(singleLayer.opacity)
            animations.append(opacityAnimation)

            // TODO: Apply path in a different UI-bound context (Layer is Sendable and can't have a dynamic `CGPath`)
            /*
            let pathAnimation = CABasicAnimation(keyPath: "shadowPath")
            pathAnimation.fromValue = shadowPath
            pathAnimation.toValue = singleLayer.path
            animations.append(pathAnimation)
             */

            if !animationOptions.setFromValues {
                animations.forEach { $0.fromValue = nil }
            }

            groupAnimation.animations = animations
            groupAnimation.isRemovedOnCompletion = false
            add(groupAnimation, forKey: "shadowStyleAnimation")
        }

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)

        shadowColor = singleLayer.color.ui.cgColor
        shadowRadius = singleLayer.radius
        shadowOffset = singleLayer.offset.cgSize
        shadowOpacity = Float(singleLayer.opacity)
        // TODO: apply shadowPath — see TODO above re: Sendable Layer / dynamic CGPath
//        shadowPath = singleLayer.path

        CATransaction.commit()
    }
    
    func removeShadow() {
        shadowColor = nil
        shadowRadius = 0
        shadowOffset = .zero
        shadowOpacity = 0
        shadowPath = nil
    }
    
    @MainActor
    func removeAllShadows() {
        removeShadow()
        sublayers?
            .filter { $0.accessibilityLabel?.hasPrefix(shadowLayerPrefix) ?? false }
            .forEach { $0.removeFromSuperlayer() }
    }
}
