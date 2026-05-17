import UIKit

final class MaterialView: UIView {

    private typealias Fill = DSL.Model.Style.Fill
    private typealias Outline = DSL.Model.Style.Outline
    private typealias Shadow = DSL.Model.Style.Shadow
    private typealias VisualEffect = DSL.Model.Style.VisualEffect
    private typealias Material = DSL.Model.Style.Material

    /// Tracked layer with its type key for diffing
    private struct TrackedLayer {
        weak var layer: CALayer?
        let typeKey: DSL.Model.Style.SType.Key
    }

    /// Tracked view with its type key for diffing
    private struct TrackedView {
        weak var view: UIView?
        let typeKey: DSL.Model.Style.SType.Key
    }

    private var trackedLayers: [TrackedLayer] = []
    private var trackedViews: [TrackedView] = []

    override func layoutSubviews() {
        super.layoutSubviews()
        for tracked in trackedLayers {
            tracked.layer?.frame = bounds
        }
        for tracked in trackedViews {
            tracked.view?.frame = bounds
        }
    }

    func applyLayoutFill() {
        removeAllTracked()

        let fillLayer = CALayer()
        fillLayer.backgroundColor = UIColor.black.withAlphaComponent(0.1).cgColor
        fillLayer.frame = bounds
        layer.addSublayer(fillLayer)
        trackedLayers.append(TrackedLayer(layer: fillLayer, typeKey: .fill))
    }

    func update(material: DSL.Model.Style.Material) {
        let cornerStyle = Self.cornerStyle(inMaterial: material)

        var expectedLayers: [(typeKey: DSL.Model.Style.SType.Key, style: DSL.Model.Style.`Any`)] = []
        for layerStyle in material.layers where !layerStyle.type.isKeyed(.corner) {
            guard case .key(let typeKey) = layerStyle.type else { continue }
            expectedLayers.append((typeKey, layerStyle))
        }

        var expectedCALayers: [(typeKey: DSL.Model.Style.SType.Key, style: DSL.Model.Style.`Any`)] = []
        var expectedUIViews: [(typeKey: DSL.Model.Style.SType.Key, style: DSL.Model.Style.`Any`)] = []

        for entry in expectedLayers {
            switch entry.typeKey {
            case .fill, .outline, .shadow:
                expectedCALayers.append(entry)
            case .visualEffect, .material:
                expectedUIViews.append(entry)
            default:
                break
            }
        }

        updateCALayers(expected: expectedCALayers, cornerStyle: cornerStyle)
        updateUIViews(expected: expectedUIViews, cornerStyle: cornerStyle)

        var zIndex: CGFloat = 0
        for tracked in trackedLayers {
            tracked.layer?.zPosition = zIndex
            zIndex += 1
        }
        for tracked in trackedViews {
            tracked.view?.layer.zPosition = zIndex
            zIndex += 1
        }
    }

    // MARK: - Diffing

    private func updateCALayers(
        expected: [(typeKey: DSL.Model.Style.SType.Key, style: DSL.Model.Style.`Any`)],
        cornerStyle: DSL.Model.Style.Corner.Entity?
    ) {
        for (index, entry) in expected.enumerated() {
            if index < trackedLayers.count, trackedLayers[index].typeKey == entry.typeKey {
                if let existingLayer = trackedLayers[index].layer {
                    if updateLayerInPlace(existingLayer, typeKey: entry.typeKey, style: entry.style, cornerStyle: cornerStyle) {
                        continue
                    }
                }
                // In-place update failed or layer was deallocated — replace
                trackedLayers[index].layer?.removeFromSuperlayer()
                if let newLayer = createCALayer(typeKey: entry.typeKey, style: entry.style, cornerStyle: cornerStyle) {
                    newLayer.frame = layer.bounds
                    layer.addSublayer(newLayer)
                    trackedLayers[index] = TrackedLayer(layer: newLayer, typeKey: entry.typeKey)
                }
            } else if index < trackedLayers.count {
                trackedLayers[index].layer?.removeFromSuperlayer()
                if let newLayer = createCALayer(typeKey: entry.typeKey, style: entry.style, cornerStyle: cornerStyle) {
                    newLayer.frame = layer.bounds
                    layer.addSublayer(newLayer)
                    trackedLayers[index] = TrackedLayer(layer: newLayer, typeKey: entry.typeKey)
                }
            } else {
                if let newLayer = createCALayer(typeKey: entry.typeKey, style: entry.style, cornerStyle: cornerStyle) {
                    newLayer.frame = layer.bounds
                    layer.addSublayer(newLayer)
                    trackedLayers.append(TrackedLayer(layer: newLayer, typeKey: entry.typeKey))
                }
            }
        }

        while trackedLayers.count > expected.count {
            trackedLayers.removeLast().layer?.removeFromSuperlayer()
        }
    }

    private func updateUIViews(
        expected: [(typeKey: DSL.Model.Style.SType.Key, style: DSL.Model.Style.`Any`)],
        cornerStyle: DSL.Model.Style.Corner.Entity?
    ) {
        for (index, entry) in expected.enumerated() {
            let canReuse = index < trackedViews.count
                && trackedViews[index].typeKey == entry.typeKey
                && trackedViews[index].view != nil

            if canReuse {
                // Reusing the existing view; nested materials still need recursive update.
                if entry.typeKey == .material,
                   let nestedMaterialView = trackedViews[index].view as? MaterialView,
                   let nestedMaterial: Material.Entity = entry.style.asConcreteEntity() {
                    nestedMaterialView.update(material: nestedMaterial.content)
                }
                continue
            } else if index < trackedViews.count {
                trackedViews[index].view?.removeFromSuperview()
                let newView = createUIView(typeKey: entry.typeKey, style: entry.style, cornerStyle: cornerStyle)
                if let newView {
                    newView.frame = bounds
                    insertSubview(newView, at: index)
                    trackedViews[index] = TrackedView(view: newView, typeKey: entry.typeKey)
                }
            } else {
                let newView = createUIView(typeKey: entry.typeKey, style: entry.style, cornerStyle: cornerStyle)
                if let newView {
                    newView.frame = bounds
                    addSubview(newView)
                    trackedViews.append(TrackedView(view: newView, typeKey: entry.typeKey))
                }
            }
        }

        while trackedViews.count > expected.count {
            trackedViews.removeLast().view?.removeFromSuperview()
        }
    }

    // MARK: - In-Place Update

    /// Try to update a layer's properties in-place without recreating it.
    /// Returns true if the update succeeded. In-place updates participate in
    /// the surrounding `CATransaction` set up by `AnimationRunner.run`, so
    /// animatable CALayer keypaths (background color, gradient, shadow*,
    /// stroke color) animate with the configured duration and timing function.
    private func updateLayerInPlace(
        _ layer: CALayer,
        typeKey: DSL.Model.Style.SType.Key,
        style: DSL.Model.Style.`Any`,
        cornerStyle: DSL.Model.Style.Corner.Entity?
    ) -> Bool {
        switch typeKey {
        case .fill:
            guard let fillStyle: Fill.Entity = style.asConcreteEntity() else { return false }
            return updateFillLayerInPlace(layer, fill: fillStyle.content, cornerStyle: cornerStyle?.content)
        case .shadow:
            guard let shadowStyle: Shadow.Entity = style.asConcreteEntity(),
                  let shadowLayer = layer as? DSL.Model.Style.Shadow.MaterialLayer else { return false }
            return updateShadowLayerInPlace(shadowLayer, newStyle: shadowStyle.content)
        case .outline:
            guard let outlineStyle: Outline.Entity = style.asConcreteEntity(),
                  let outlineLayer = layer as? DSL.Model.Style.Outline.Layer else { return false }
            return updateOutlineLayerInPlace(outlineLayer, newStyle: outlineStyle.content)
        default:
            return false
        }
    }

    /// Animate-friendly shadow update. Mutates `shadow*` keypaths on the
    /// existing `Shadow.MaterialLayer` so the surrounding `CATransaction`
    /// drives the transition. Layer-count or hollow-flag changes can't be
    /// animated cleanly — those fall back to recreate.
    private func updateShadowLayerInPlace(
        _ shadowLayer: DSL.Model.Style.Shadow.MaterialLayer,
        newStyle: DSL.Model.Style.Shadow
    ) -> Bool {
        guard newStyle.layers.count == 1,
              shadowLayer.ownStyle.layers.count == 1,
              newStyle.layers[0].isHollow == shadowLayer.ownStyle.layers[0].isHollow else {
            return false
        }
        let def = newStyle.layers[0]
        let resolvedColor = def.color.ui.resolvedColor(with: traitCollection)
        shadowLayer.shadowColor = resolvedColor.cgColor
        shadowLayer.shadowRadius = def.radius
        shadowLayer.shadowOffset = def.offset.cgSize
        shadowLayer.shadowOpacity = Float(def.opacity)
        if !def.isHollow {
            shadowLayer.backgroundColor = resolvedColor.cgColor
        }
        return true
    }

    /// Animate-friendly outline update. Updates the inner content layer's
    /// fill (solid → backgroundColor; gradient → CAGradientLayer keypaths).
    /// `lineWidth` and `position` changes alter the geometry path computed
    /// in `layoutSublayers` — those fall back to recreate.
    private func updateOutlineLayerInPlace(
        _ outlineLayer: DSL.Model.Style.Outline.Layer,
        newStyle: DSL.Model.Style.Outline
    ) -> Bool {
        guard newStyle.lineWidth == outlineLayer.ownStyle.lineWidth,
              newStyle.position == outlineLayer.ownStyle.position,
              let content = outlineLayer[.content] else {
            return false
        }
        if let solid = newStyle.fill.solid?.ui {
            content.backgroundColor = solid.resolvedColor(with: traitCollection).cgColor
            return true
        }
        if let gradient = newStyle.fill.gradient, let gradientLayer = content as? CAGradientLayer {
            gradientLayer.apply(gradient: gradient, in: self)
            return true
        }
        return false
    }

    /// Update fill layer colors in-place. Participates in the surrounding
    /// `CATransaction` so when the caller wraps this in `AnimationRunner.run`,
    /// background-color and gradient color/location changes animate with the
    /// configured duration and timing function. When the caller passes a
    /// `nil` animation, the surrounding transaction has actions disabled, so
    /// changes still apply instantaneously.
    private func updateFillLayerInPlace(_ layer: CALayer, fill: Fill, cornerStyle: DSL.Model.Style.Corner?) -> Bool {
        if let solid = fill.solid?.ui {
            let resolvedColor = solid.resolvedColor(with: traitCollection)
            layer.backgroundColor = resolvedColor.cgColor
            if let cornerStyle {
                layer.apply(cornerStyle: cornerStyle)
            }
            return true
        } else if let gradient = fill.gradient, let gradientLayer = layer as? CAGradientLayer {
            gradientLayer.apply(gradient: gradient, in: self)
            if let cornerStyle {
                gradientLayer.apply(cornerStyle: cornerStyle)
            }
            return true
        }
        return false
    }

    // MARK: - Layer/View Creation

    private func createCALayer(
        typeKey: DSL.Model.Style.SType.Key,
        style: DSL.Model.Style.`Any`,
        cornerStyle: DSL.Model.Style.Corner.Entity?
    ) -> CALayer? {
        switch typeKey {
        case .fill:
            if let fillStyle: Fill.Entity = style.asConcreteEntity() {
                return Fill.LayerFactory.makeLayer(
                    style: fillStyle.content,
                    cornerStyle: cornerStyle?.content,
                    in: self
                )
            }
        case .outline:
            if let outlineStyle: Outline.Entity = style.asConcreteEntity() {
                return Outline.Layer(
                    style: outlineStyle.content,
                    cornerStyle: cornerStyle?.content,
                    env: self
                )
            }
        case .shadow:
            if let shadowStyle: Shadow.Entity = style.asConcreteEntity() {
                return Shadow.MaterialLayer(
                    style: shadowStyle.content,
                    cornerStyle: cornerStyle?.content,
                    env: self
                )
            }
        default:
            break
        }
        return nil
    }

    private func createUIView(
        typeKey: DSL.Model.Style.SType.Key,
        style: DSL.Model.Style.`Any`,
        cornerStyle: DSL.Model.Style.Corner.Entity?
    ) -> UIView? {
        switch typeKey {
        case .visualEffect:
            if let effectStyle: VisualEffect.Entity = style.asConcreteEntity() {
                return makeVisualEffectView(
                    style: effectStyle.content,
                    cornerStyle: cornerStyle?.content
                )
            }
        case .material:
            if let nestedMaterial: Material.Entity = style.asConcreteEntity() {
                let nestedView = MaterialView()
                nestedView.update(material: nestedMaterial.content)
                return nestedView
            }
        default:
            break
        }
        return nil
    }

    // MARK: - Cleanup

    private func removeAllTracked() {
        for tracked in trackedLayers {
            tracked.layer?.removeFromSuperlayer()
        }
        for tracked in trackedViews {
            tracked.view?.removeFromSuperview()
        }
        trackedLayers.removeAll()
        trackedViews.removeAll()
    }

    // MARK: - Utils

    private func makeVisualEffectView(
        style: DSL.Model.Style.VisualEffect,
        cornerStyle: DSL.Model.Style.Corner?
    ) -> UIVisualEffectView {
        let effect: UIVisualEffect
        if let blur = style.blur {
            effect = UIBlurEffect(style: blur.uiBlurStyle)
        } else if style.glass != nil {
            if #available(iOS 26.0, *) {
                effect = UIGlassEffect(style: .regular)
            } else {
                effect = UIBlurEffect(style: .systemUltraThinMaterial)
            }
        } else {
            effect = UIBlurEffect(style: .regular)
        }

        let view = UIVisualEffectView(effect: effect)
        if let cornerStyle {
            view.layer.cornerRadius = cornerStyle.radius
            view.layer.cornerCurve = cornerStyle.curve.ca
            view.clipsToBounds = true
        }
        return view
    }

    static func cornerStyle(inMaterial material: DSL.Model.Style.Material) -> DSL.Model.Style.Corner.Entity? {
        return material.layers.first(where: { $0.type.isKeyed(.corner) })?.asConcreteEntity()
    }
}
