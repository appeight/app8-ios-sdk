import UIKit

extension DSL.Model.Style.Shadow {

    final class MaterialLayer: CALayer {

        let ownStyle: DSL.Model.Style.Shadow
        let cornerStyle: DSL.Model.Style.Corner?
        private weak var env: UITraitEnvironment?

        // MARK: - Lifecycle

        @MainActor
        init(style: DSL.Model.Style.Shadow, cornerStyle: DSL.Model.Style.Corner?, env: UITraitEnvironment) {
            self.ownStyle = style
            self.cornerStyle = cornerStyle
            self.env = env
            super.init()
            commonInit()
            applyContentScales()
        }

        override init(layer: Any) {
            if let src = layer as? MaterialLayer {
                self.ownStyle = src.ownStyle
                self.cornerStyle = src.cornerStyle
                self.env = src.env
            } else {
                self.ownStyle = DSL.Model.Style.Shadow(UIColor.clear, 0)
                self.cornerStyle = nil
                self.env = nil
            }
            super.init(layer: layer)
            applyContentScales()
            setNeedsLayout()
        }

        required init?(coder: NSCoder) { nil }

        // MARK: - Build

        private func commonInit() {
            needsDisplayOnBoundsChange = true

            if ownStyle.layers.count == 1 {
                configureShadow(on: self, from: ownStyle.layers[0])
            } else {
                for shadowLayer in ownStyle.layers {
                    let sublayer = CALayer()
                    configureShadow(on: sublayer, from: shadowLayer)
                    addSublayer(sublayer)
                }
            }

            setNeedsLayout()
        }

        private func configureShadow(on layer: CALayer, from shadowDef: DSL.Model.Style.Shadow.Layer) {
            let resolvedColor: UIColor
            if let env = env {
                resolvedColor = shadowDef.color.ui.resolvedColor(with: env.traitCollection)
            } else {
                resolvedColor = shadowDef.color.ui
            }

            layer.shadowColor = resolvedColor.cgColor
            layer.shadowRadius = shadowDef.radius
            layer.shadowOffset = shadowDef.offset.cgSize
            layer.shadowOpacity = Float(shadowDef.opacity)

            // Hollow shadows get their shadowPath in layoutSublayers; non-hollow
            // ones need an opaque background for the shadow to cast from.
            if !shadowDef.isHollow {
                layer.backgroundColor = resolvedColor.cgColor
            }
        }

        // MARK: - Scale

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

        var preferredContentsScale: CGFloat? = nil

        private func applyContentScales() {
            let scale = preferredContentsScale ?? resolvedScaleFromHierarchy()
            contentsScale = scale
            sublayers?.forEach { $0.contentsScale = scale }
        }

        // MARK: - Layout

        override func layoutSublayers() {
            super.layoutSublayers()
            guard bounds.width > 0, bounds.height > 0 else { return }

            CATransaction.begin()
            CATransaction.setDisableActions(true)

            let radius = cornerStyle?.resolvedRadius(in: bounds.size) ?? 0
            let path = roundedRectCGPath(in: bounds, radius: radius)

            if ownStyle.layers.count == 1 {
                shadowPath = path
                if !ownStyle.layers[0].isHollow {
                    self.cornerRadius = radius
                }
            } else {
                for (index, sublayer) in (sublayers ?? []).enumerated() {
                    sublayer.frame = bounds
                    sublayer.shadowPath = path
                    sublayer.zPosition = CGFloat(index)
                    if index < ownStyle.layers.count, !ownStyle.layers[index].isHollow {
                        sublayer.cornerRadius = radius
                    }
                }
            }

            CATransaction.commit()

            applyContentScales()
        }

        private func roundedRectCGPath(in rect: CGRect, radius: CGFloat) -> CGPath {
            let r = min(radius, min(rect.width, rect.height) * 0.5)
            return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        }
    }
}
