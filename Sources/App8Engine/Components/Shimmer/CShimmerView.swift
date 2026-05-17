//
//  CShimmerView.swift
//  App8Engine
//

import UIKit
import Combine

class CShimmerView: App8BaseView<DSL.Model.Component.Shimmer.C>, CViewProtocol {

    weak var materialView: MaterialView?
    let contentView = UIView()
    private var viewModel: CShimmerViewModel?

    private var trackedChildren: [String: (view: UIView, typeName: String)] = [:]

    private let shimmerLayer = CAGradientLayer()
    private var isShimmerAnimating = false

    private var propertiesCancellable: AnyCancellable?
    private var variablesCancellable: AnyCancellable?

    // MARK: - Setup

    override func setup() {
        super.setup()

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()
        contentView.clipsToBounds = true

        shimmerLayer.colors = [
            UIColor.white.withAlphaComponent(0.0).cgColor,
            UIColor.white.withAlphaComponent(0.3).cgColor,
            UIColor.white.withAlphaComponent(0.0).cgColor
        ]
        shimmerLayer.locations = [0.0, 0.5, 1.0]
        shimmerLayer.masksToBounds = true
    }

    // MARK: - Configure

    func configure(viewModel: CShimmerViewModel, superview: UIView? = nil, animated: Bool = true) {
        guard let superview = superview ?? self.superview else { return }
        self.viewModel = viewModel

        bindLayout(
            viewModel.layout,
            in: superview,
            viewRegistry: viewModel.service.componentRegistry.viewRegistry,
            parentComponentPath: viewModel.parentPath,
            keyboardService: viewModel.service.context.keyboardService,
            animated: animated
        )
        bindStyle(viewModel.style, animation: viewModel.animation)
        configureContent(viewModel: viewModel, animated: animated)
        applyCurrentProperties()

        propertiesCancellable = viewModel.properties
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentProperties()
            }

        variablesCancellable = viewModel.variablesChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentProperties()
            }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if shimmerLayer.superlayer != nil {
            // Update frame/radius without restarting the animation.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shimmerLayer.frame = contentView.bounds
            shimmerLayer.cornerRadius = contentView.layer.cornerRadius
            CATransaction.commit()
        } else if isShimmerAnimating || (viewModel != nil && contentView.bounds.size != .zero) {
            // Deferred start: shimmer was requested while bounds were still zero.
            applyCurrentProperties()
        }
    }

    // MARK: - Properties

    private func applyCurrentProperties() {
        guard let vm = viewModel else { return }
        let props = vm.currentProperties

        let shouldAnimate: Bool
        if let expr = props.isAnimating {
            shouldAnimate = vm.resolvePropertyToBool(expr) ?? true
        } else {
            shouldAnimate = true
        }

        if shouldAnimate && !isShimmerAnimating {
            startShimmerAnimation()
        } else if !shouldAnimate && isShimmerAnimating {
            stopShimmerAnimation()
        }
    }

    // MARK: - Shimmer Animation

    private func startShimmerAnimation() {
        guard let vm = viewModel else { return }
        guard contentView.bounds.size != .zero else { return }
        let props = vm.currentProperties
        let duration = props.duration ?? 1.5
        let direction = props.direction ?? .leftToRight

        switch direction {
        case .leftToRight:
            shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
            shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
        case .rightToLeft:
            shimmerLayer.startPoint = CGPoint(x: 1, y: 0.5)
            shimmerLayer.endPoint = CGPoint(x: 0, y: 0.5)
        case .topToBottom:
            shimmerLayer.startPoint = CGPoint(x: 0.5, y: 0)
            shimmerLayer.endPoint = CGPoint(x: 0.5, y: 1)
        }

        shimmerLayer.frame = contentView.bounds
        shimmerLayer.cornerRadius = contentView.layer.cornerRadius
        if shimmerLayer.superlayer == nil {
            contentView.layer.addSublayer(shimmerLayer)
        }

        // Animate locations to sweep the highlight band across.
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-1.0, -0.5, 0.0]
        animation.toValue = [1.0, 1.5, 2.0]
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        shimmerLayer.add(animation, forKey: "shimmer")

        isShimmerAnimating = true
    }

    private func stopShimmerAnimation() {
        shimmerLayer.removeAnimation(forKey: "shimmer")
        shimmerLayer.removeFromSuperlayer()
        isShimmerAnimating = false
    }

    // MARK: - Content (Children)

    private func configureContent(viewModel: CShimmerViewModel, animated: Bool = false) {
        let children = viewModel.component.children

        for child in children {
            if trackedChildren[child.id] != nil { continue }

            let result = viewModel.service.renderComponent(
                child,
                superview: contentView,
                parentPath: viewModel.componentPath,
                parentVariableStore: viewModel.variableStore
            )
            trackedChildren[child.id] = (result.view, typeName(for: result.type))
        }
    }

    private func typeName(for ctype: DSL.Model.Component.CType) -> String {
        switch ctype {
        case .key(let key): return key.rawValue
        case .custom(let name): return name
        }
    }

    // MARK: - Style

    override func applyStyle(
        _ style: Content.Style?,
        animated: Bool = true,
        duration: TimeInterval = 0.25,
        options: UIView.AnimationOptions = [.curveEaseInOut],
        useSpring: Bool = false
    ) {
        super.applyStyle(style, animated: animated, duration: duration, options: options, useSpring: useSpring)
        applyBaseStyle(style, animated: animated, duration: duration, options: options, useSpring: useSpring)

        shimmerLayer.cornerRadius = contentView.layer.cornerRadius
    }
}

// MARK: - StreamingUpdatable

extension CShimmerView: StreamingUpdatable {

    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CShimmerViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }

        stopShimmerAnimation()
        self.viewModel = vm
        bindStyle(vm.style, animation: vm.animation)
        configureContent(viewModel: vm, animated: animated)
        applyCurrentProperties()

        propertiesCancellable = vm.properties
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentProperties()
            }
        variablesCancellable = vm.variablesChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentProperties()
            }
        return vm
    }
}
