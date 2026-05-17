import UIKit

extension DSL.Model.Style {

    struct Fill: Decodable, StylePointerResolvable {
        typealias Entity = ConcreteEntity<Self>
        
        @Wrapped var solid: Color.Themed?
        @Wrapped var gradient: Gradient?
        
        private init() {
            _solid = .none
            _gradient = .none
        }
        
        static var none: Fill {
            Fill()
        }
        
        mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
            _solid.resolvePointer(type: .key(.color), resolver: resolver)
            _gradient.resolvePointer(type: .key(.gradient), resolver: resolver)
        }
        
        func isResolved() -> Bool {
            var conditions: [Bool] = []
            if let solid {
                conditions.append(solid.isResolved())
            }
            if let gradient {
                conditions.append(gradient.isResolved())
            }
            return conditions.allSatisfy { $0 }
        }

        func unresolvedPointerIds() -> [String] {
            _solid.unresolvedPointerIds() + _gradient.unresolvedPointerIds()
        }
    }
}

extension DSL.Model.Style.Fill {

    struct LayerFactory {

        @MainActor
        static func makeLayer(style: DSL.Model.Style.Fill, cornerStyle: DSL.Model.Style.Corner?, in env: UITraitEnvironment) -> CALayer? {
            if let solid = style.solid?.ui {
                let layer = CALayer()
                let resolvedColor = solid.resolvedColor(with: env.traitCollection)
                layer.backgroundColor = resolvedColor.cgColor
                if let cornerStyle {
                    layer.apply(cornerStyle: cornerStyle)
                }
                return layer
            } else if let gradient = style.gradient {
                let gradientLayer = CAGradientLayer()
                gradientLayer.apply(gradient: gradient, in: env)
                if let cornerStyle {
                    gradientLayer.apply(cornerStyle: cornerStyle)
                }
                return gradientLayer
            }
            return nil
        }
    }
}
