import UIKit

extension DSL.Model.Style {

    struct Outline: Decodable, StylePointerResolvable {
        typealias Entity = ConcreteEntity<Self>

        let lineWidth: Float
        let position: Position
        var fill: Fill

        static var none: Outline {
            Outline(lineWidth: 0, position: .inside, fill: .none)
        }

        mutating func resolveStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
            fill.resolveStylePointers(resolver: resolver)
        }

        func isResolved() -> Bool {
            fill.isResolved()
        }

        func unresolvedPointerIds() -> [String] {
            fill.unresolvedPointerIds()
        }

        enum Position: String, Codable, Equatable {
            case inside, outside, center

            var isOutside: Bool { self == .outside }
            var isCenter:  Bool { self == .center }
            var isInside:  Bool { self == .inside }
        }
    }
}

extension DSL.Model.Style.Outline {

    final class Layer: CALayer, NamedSublayersProtocol {

        enum LayerName: String, NamedSublayersLayerName { case content, mask, hole }
        var namedLayers: [String : CALayer] = [:]

        let ownStyle: DSL.Model.Style.Outline
        let cornerStyle: DSL.Model.Style.Corner?

        @MainActor
        init(style: DSL.Model.Style.Outline, cornerStyle: DSL.Model.Style.Corner?, env: UITraitEnvironment) {
            self.ownStyle = style
            self.cornerStyle = cornerStyle
            super.init()
            commonInit(env: env)
            applyContentScales()
        }

        override init(layer: Any) {
            if let src = layer as? Layer {
                self.ownStyle = src.ownStyle
                self.cornerStyle = src.cornerStyle
            } else {
                self.ownStyle = .none
                self.cornerStyle = nil
            }
            super.init(layer: layer)

            // rebind names to CA-copied sublayers; reattach mask
            rebindNamedLayers()
            if let content = self[.content],
               let mask = self[.mask] as? CAShapeLayer {
                content.mask = mask
            }
            applyContentScales()
            setNeedsLayout()
        }

        required init?(coder: NSCoder) { nil }

        // MARK: - Build

        @MainActor
        private func commonInit(env: UITraitEnvironment) {
            needsDisplayOnBoundsChange = true

            // Rectangular content; ring geometry comes from mask
            guard let content = DSL.Model.Style.Fill.LayerFactory
                .makeLayer(style: ownStyle.fill, cornerStyle: nil, in: env) else { return }
            content.masksToBounds = false
            setLayer(content, named: .content)

            let mask = CAShapeLayer()
            mask.fillRule = .evenOdd
            mask.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull()]
            setLayer(mask, named: .mask, superlayer: nil, addToSublayers: false)
            content.mask = mask

            let hole = CAShapeLayer()
            hole.fillColor = nil
            hole.isHidden = true
            hole.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull()]
            setLayer(hole, named: .hole)

            setNeedsLayout()
        }

        // MARK: - Scale without UIKit

        /// Walks up the layer tree for a non-zero `contentsScale`, falling back to 2.0
        /// when nothing is set (CALayer, unlike a view-backed layer, has no inherent scale).
        private func resolvedScaleFromHierarchy() -> CGFloat {
            var L: CALayer? = self
            while let layer = L {
                let s = layer.contentsScale
                if s > 0 {
                    preferredContentsScale = s
                    return s
                }
                L = layer.superlayer
            }
            return 2.0
        }

        /// Override point for hosts that know the right scale.
        var preferredContentsScale: CGFloat? = nil

        private func applyContentScales() {
            let scale = preferredContentsScale ?? resolvedScaleFromHierarchy()
            contentsScale = scale
            namedLayers.values.forEach { $0.contentsScale = scale }
        }

        // MARK: - Layout (CoreGraphics paths, no UIKit)

        override func layoutSublayers() {
            super.layoutSublayers()
            guard
                bounds.width > 0, bounds.height > 0,
                let content = self[.content],
                let mask = self[.mask] as? CAShapeLayer,
                let hole = self[.hole] as? CAShapeLayer
            else { return }

            CATransaction.begin()
            CATransaction.setDisableActions(true)

            let w = max(0, CGFloat(ownStyle.lineWidth))
            let grow: CGFloat = ownStyle.position.isInside ? 0 : (ownStyle.position.isCenter ? w * 0.5 : w)

            content.frame = bounds.insetBy(dx: -grow, dy: -grow)

            let baseR  = cornerStyle?.radius ?? 0
            let outerR = max(0, baseR + grow)
            let innerR = max(0, outerR - w)

            let outerRect = content.bounds
            let innerRect = outerRect.insetBy(dx: w, dy: w)

            let outerPath = roundedRectCGPath(in: outerRect, radius: outerR)
            let innerPath = roundedRectCGPath(in: innerRect, radius: innerR)

            let ring = CGMutablePath()
            ring.addPath(outerPath)
            ring.addPath(innerPath)

            mask.frame = content.bounds
            mask.path  = ring // even-odd

            hole.frame = content.frame
            hole.path  = innerPath

            CATransaction.commit()
            
            applyContentScales()
        }

        private func roundedRectCGPath(in rect: CGRect, radius: CGFloat) -> CGPath {
            let r = min(radius, min(rect.width, rect.height) * 0.5)
            return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        }
    }
}
