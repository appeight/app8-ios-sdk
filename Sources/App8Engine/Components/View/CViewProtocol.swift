import UIKit

protocol CViewProtocol: AnyObject {
    @MainActor
    var materialView: MaterialView? { get set }
    @MainActor
    var contentView: UIView { get }
    @MainActor
    var layoutModeId: String? { get }
    /// Per-instance layout mode service from the owning context.
    /// Returns nil when no viewModel is attached (pre-configure / detached views).
    @MainActor
    var layoutModeContext: App8LayoutMode? { get }
}

/// Views that support streaming property/style updates without re-binding layout constraints.
/// The diff in CView calls this for stable children (same id, same type) when a new
/// component definition arrives from the server.
@MainActor
protocol StreamingUpdatable: UIView {
    /// Updates the view in-place with new component data. Returns the root ViewModel
    /// created during the update (if any), which callers can use for caching.
    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract?
}

extension CViewProtocol where Self: UIView {

    var layoutModeId: String? { nil }

    /// Default returns nil — views that opt into layout-mode debug visuals override
    /// this to thread their viewModel.service.context.layoutMode through. nil disables
    /// the debug overlay for that view (acceptable since layout mode is debug-only).
    var layoutModeContext: App8LayoutMode? { nil }

    var layoutModeName: String {
        switch String(describing: type(of: self)) {
        case "CLabelView":      return "L"
        case "CImageView":      return "Im"
        case "CIconView":       return "I"
        case "CShapeView":      return "S"
        case "CView":           return "V"
        case "CCollectionView": return "C"
        default:
            var name = String(describing: type(of: self))
            if name.hasPrefix("C"), name.count > 1 { name = String(name.dropFirst()) }
            if name.hasSuffix("View"), name.count > 4 { name = String(name.dropLast(4)) }
            return name.lowercased()
        }
    }

    @MainActor
    func applyLayoutModeCornerLabels() {
        let name = layoutModeName
        let boldFont = UIFont.monospacedSystemFont(ofSize: 8, weight: .bold)
        let regularFont = UIFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        let attributed = NSMutableAttributedString(
            string: name,
            attributes: [.font: boldFont, .foregroundColor: UIColor.white]
        )
        if let id = layoutModeId {
            attributed.append(NSAttributedString(
                string: ":\(id)",
                attributes: [.font: regularFont, .foregroundColor: UIColor.white]
            ))
        }

        let topLeftTag = 8_001_001
        let bottomRightTag = 8_001_002

        func makeLabel() -> UILabel {
            let label = UILabel()
            label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            label.layer.cornerRadius = 3
            label.layer.masksToBounds = true
            label.isUserInteractionEnabled = false
            return label
        }

        // Top-left label
        let topLeft: UILabel
        if let existing = viewWithTag(topLeftTag) as? UILabel {
            topLeft = existing
        } else {
            topLeft = makeLabel()
            topLeft.tag = topLeftTag
            addSubview(topLeft)
            topLeft.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                topLeft.topAnchor.constraint(equalTo: topAnchor, constant: 3),
                topLeft.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            ])
        }
        let labelsVisible = layoutModeContext?.showLabels ?? true
        topLeft.attributedText = attributed
        topLeft.isHidden = !labelsVisible

        // Bottom-right label
        let bottomRight: UILabel
        if let existing = viewWithTag(bottomRightTag) as? UILabel {
            bottomRight = existing
        } else {
            bottomRight = makeLabel()
            bottomRight.tag = bottomRightTag
            addSubview(bottomRight)
            bottomRight.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                bottomRight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
                bottomRight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            ])
        }
        bottomRight.attributedText = attributed
        bottomRight.isHidden = !labelsVisible
    }

    @MainActor
    func applyBaseStyle(
        _ style: DSL.Model.Style.BaseStyleProtocol?,
        animated: Bool = true,
        duration: TimeInterval = 0.25,
        options: UIView.AnimationOptions = [.curveEaseInOut],
        useSpring: Bool = false
    ) {
        contentMode = style?.contentMode?.ui ?? .scaleToFill
        contentView.backgroundColor = .clear
        backgroundColor = .clear

        // Apply animatable properties (alpha, transform)
        let targetAlpha = style?.alpha ?? 1.0
        let targetTransform = style?.transform?.affineTransform ?? .identity

        // Layout inspection mode: show component outlines only — no backgrounds or fills.
        // Force alpha=1 and identity transform synchronously so that entrance animations
        // (which may start from alpha=0) don't leave views invisible during inspection.
        if layoutModeContext?.isEnabled == true {
            alpha = 1.0
            transform = .identity
            materialView?.alpha = 0
            backgroundColor = UIColor.black.withAlphaComponent(0.1)
            contentView.layer.apply(cornerStyle: .none)
            (self as? App8BaseViewProtocol)?.trackRelativeCorner(.none, on: contentView.layer)
            layer.borderWidth = 1
            layer.borderColor = UIColor.black.withAlphaComponent(0.35).cgColor
            applyLayoutModeCornerLabels()
            return
        }

        // Resolve the animation descriptor. Prefer the state-driven Inline that
        // `applyStyleWithAnimation` stashed on the view; fall back to a
        // synthesized one built from the legacy parameters when no state Inline
        // is active. `nil` means instantaneous.
        let stateInline = (self as? HasActiveStateAnimation)?.activeStateAnimation
        let resolved: DSL.Model.Animation.Inline?
        if let stateInline {
            resolved = stateInline
        } else if animated {
            resolved = .legacy(duration: duration, options: options, useSpring: useSpring)
        } else {
            resolved = nil
        }

        // State transitions are interruptible (re-press during release should
        // catch the in-flight presentation values), and shouldn't block touch.
        // For non-state animated paths, only `.allowUserInteraction` is added.
        let extraOptions: UIView.AnimationOptions = (stateInline != nil)
            ? [.beginFromCurrentState, .allowUserInteraction]
            : [.allowUserInteraction]

        // Material: first creation has no meaningful "from" state, so the
        // initial layer install is forced to instantaneous regardless of the
        // surrounding animation.
        let materialAnimation: DSL.Model.Animation.Inline?

        if let material = style?.material {
            let isFirstApply = self.materialView.isNil
            let materialView = self.materialView ?? MaterialView()
            if self.materialView.isNil {
                insertSubview(materialView, at: .zero)
                materialView.cMakeEqualToSuperview()
                self.materialView = materialView
            }
            materialAnimation = isFirstApply ? nil : resolved

            AnimationRunner.run(
                animation: resolved,
                additionalOptions: extraOptions,
                layerBlock: { [self] in
                    AnimationRunner.run(
                        animation: materialAnimation,
                        layerBlock: {
                            materialView.update(material: material)
                            // Content masked with the same corner style as the
                            // material so child views get clipped consistently.
                            if let cornerStyle = MaterialView.cornerStyle(inMaterial: material) {
                                self.contentView.layer.apply(cornerStyle: cornerStyle.content)
                                (self as? App8BaseViewProtocol)?.trackRelativeCorner(cornerStyle.content, on: self.contentView.layer)
                            } else {
                                self.contentView.layer.apply(cornerStyle: .none)
                                (self as? App8BaseViewProtocol)?.trackRelativeCorner(.none, on: self.contentView.layer)
                            }
                        }
                    )
                },
                viewBlock: { [self] in
                    self.alpha = targetAlpha
                    self.transform = targetTransform
                }
            )
        } else {
            AnimationRunner.run(
                animation: resolved,
                additionalOptions: extraOptions,
                layerBlock: { [self] in
                    self.materialView?.rfs(animatables: { $0?.alpha = .zero }, animated: true)
                    self.contentView.layer.apply(cornerStyle: .none)
                    (self as? App8BaseViewProtocol)?.trackRelativeCorner(.none, on: self.contentView.layer)
                },
                viewBlock: { [self] in
                    self.alpha = targetAlpha
                    self.transform = targetTransform
                }
            )
        }
    }
}

// MARK: - Inline reconstruction from legacy parameters

extension DSL.Model.Animation.Inline {
    /// Build a best-effort `Inline` from the legacy `(duration, options,
    /// useSpring)` parameters used by `applyStyle`. Spring loses its damping /
    /// velocity (the legacy bool just signaled "use a spring"), so we fall
    /// back to `Spring.defaultSpring`. Named curves are extracted from
    /// `UIView.AnimationOptions` when present.
    static func legacy(
        duration: TimeInterval,
        options: UIView.AnimationOptions,
        useSpring: Bool
    ) -> DSL.Model.Animation.Inline {
        let timing: DSL.Model.Animation.Timing
        if useSpring {
            timing = .spring(.defaultSpring)
        } else if options.contains(.curveLinear) {
            timing = .curve(.linear)
        } else if options.contains(.curveEaseIn) {
            timing = .curve(.easeIn)
        } else if options.contains(.curveEaseOut) {
            timing = .curve(.easeOut)
        } else {
            timing = .curve(.easeInOut)
        }
        return DSL.Model.Animation.Inline(
            id: nil,
            duration: duration,
            delay: 0,
            timing: timing,
            options: []
        )
    }
}
