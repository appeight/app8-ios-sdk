import UIKit
import Combine

class CIconView: App8BaseView<DSL.Model.Component.Icon.C>, CViewProtocol {

    private var viewModel: CIconViewModel?
    var layoutModeId: String? { viewModel?.componentPath.split(separator: ".").last.map(String.init) }
    var layoutModeContext: App8LayoutMode? { viewModel?.service.context.layoutMode }
    weak var materialView: MaterialView?
    let contentView = UIView()
    private let imageView = UIImageView()

    override var intrinsicContentSource: UIView? { imageView }

    private var propertiesCancellable: AnyCancellable?
    private var variablesCancellable: AnyCancellable?
    private var isHiddenCancellable: AnyCancellable?

    // MARK: - isHidden Expression
    private var isHiddenExpression: String?
    private var lastIsHidden: Bool?

    // MARK: - Color expressions (per-property animation)
    private var backgroundColorAnimation: DSL.Model.Animation.Inline?
    private var tintColorAnimation: DSL.Model.Animation.Inline?
    private var lastBackgroundColor: UIColor??
    private var lastTintColor: UIColor??
    private var hasAppliedBackgroundColorOnce = false
    private var hasAppliedTintColorOnce = false

    // MARK: - Touch handling
    private var tapGesture: UITapGestureRecognizer?

    override func setup() {
        super.setup()

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()

        contentView.addSubview(imageView)
        imageView.cMakeEqualToSuperview()
    }

    func configure(viewModel: CIconViewModel, superview: UIView? = nil, animated: Bool = true) {
        self.viewModel = viewModel
        guard let superview = superview ?? self.superview else {
            return
        }
        bindLayout(viewModel.layout, in: superview, viewRegistry: viewModel.service.componentRegistry.viewRegistry, parentComponentPath: viewModel.parentPath, keyboardService: viewModel.service.context.keyboardService, animated: animated)
        bindStyle(viewModel.style, animation: viewModel.animation)
        bindProperties(viewModel: viewModel)
        bindVariables(viewModel: viewModel)
        bindIsHidden(viewModel: viewModel)
        setupTouchHandlingIfNeeded()
        configureContent(viewModel: viewModel, animated: animated)
    }

    // MARK: - isHidden Expression

    private func bindIsHidden(viewModel: CIconViewModel) {
        let props = viewModel.currentProperties
        isHiddenExpression = props.isHidden?.contains("{{") == true ? props.isHidden : nil
        guard isHiddenExpression != nil else { return }

        isHiddenCancellable = viewModel.variablesChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIsHidden()
            }
        updateIsHidden()
    }

    private func updateIsHidden() {
        guard let viewModel = viewModel,
              let expression = isHiddenExpression else { return }
        let hidden = viewModel.resolvePropertyToBool(expression) ?? false
        guard lastIsHidden != hidden else { return }
        lastIsHidden = hidden
        self.isHidden = hidden
    }

    // MARK: - Touch Handling

    private var shouldHandleTouches: Bool {
        guard let viewModel = viewModel else { return false }
        return viewModel.component.triggers != nil || viewModel.component.actions != nil
    }

    private func setupTouchHandlingIfNeeded() {
        guard shouldHandleTouches, tapGesture == nil else { return }
        isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        tapGesture = tap
    }

    @objc private func handleTap() {
        viewModel?.executeAction(for: .tap)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard shouldHandleTouches else { return }
        viewModel?.fireTrigger(.touchDown)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard shouldHandleTouches else { return }
        viewModel?.fireTrigger(.touchUp)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        guard shouldHandleTouches else { return }
        viewModel?.fireTrigger(.touchUp)
    }

    /// Subscribe to property changes (for state-driven icon changes)
    private func bindProperties(viewModel: CIconViewModel) {
        propertiesCancellable = viewModel.properties
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.configureContent(viewModel: viewModel, animated: true)
            }
    }

    /// Subscribe to "item" variable changes and reparent signals ("") —
    /// re-resolves icon content when cell data changes.
    /// Filters out unrelated variable changes (e.g. scroll offset) to avoid unnecessary work per frame.
    private func bindVariables(viewModel: CIconViewModel) {
        variablesCancellable?.cancel()
        variablesCancellable = viewModel.variablesChanged
            .filter { $0 == "item" || $0.isEmpty }
            .sink { [weak self] _ in
                guard let self, let vm = self.viewModel else { return }
                self.applyIconContent(viewModel: vm)
            }
    }

    override func applyStyle(
        _ style: Content.Style?,
        animated: Bool = true,
        duration: TimeInterval = 0.25,
        options: UIView.AnimationOptions = [.curveEaseInOut],
        useSpring: Bool = false
    ) {
        super.applyStyle(style, animated: animated, duration: duration, options: options, useSpring: useSpring)
        applyBaseStyle(style, animated: animated, duration: duration, options: options, useSpring: useSpring)
        imageView.clipsToBounds = true
        imageView.contentMode = style?.contentMode?.ui ?? .center

        guard !(viewModel?.service.context.layoutMode.isEnabled == true) else { return }

        imageView.tintColor = style?.color?.ui ?? style?.tint?.ui

        // Reconfigure content for the new symbolFontSize. Skipped during streamingUpdate,
        // which calls configureContent explicitly after bindStyle.
        if !suppressStyleContent, let viewModel {
            configureContent(viewModel: viewModel, animated: animated)
        }
    }

    /// Suppresses redundant configureContent call in applyStyle during streamingUpdate
    private var suppressStyleContent = false

    /// Last loaded icon key to skip redundant SF Symbol / asset creation on reuse
    private var lastLoadedIconKey: String?

    /// Tracks rendered children by component id → (view, type name) for diffing during reuse
    private var trackedChildren: [String: (view: UIView, typeName: String)] = [:]

    private func configureContent(viewModel: CIconViewModel, animated: Bool = false) {
        if viewModel.service.context.layoutMode.isEnabled {
            imageView.image = nil
            viewModel.component.children.forEach { c in
                viewModel.service.renderComponent(c, superview: contentView, parentPath: viewModel.componentPath, parentVariableStore: viewModel.variableStore)
            }
            return
        }

        applyIconContent(viewModel: viewModel)
        updateChildren(viewModel: viewModel, animated: animated)
    }

    private func applyIconContent(viewModel: CIconViewModel) {
        // currentProperties gives state-overridden values.
        let props = viewModel.currentProperties

        backgroundColorAnimation = props.backgroundColor?.animation?.inlineOrNil
        tintColorAnimation = props.tintColor?.animation?.inlineOrNil

        let bgHex: String? = props.backgroundColor?.value
        let bgColor: UIColor? = bgHex.flatMap { UIColor(withHexString: $0) }
        if lastBackgroundColor.map({ $0 == bgColor }) != true {
            lastBackgroundColor = .some(bgColor)
            let isFirstApply = !hasAppliedBackgroundColorOnce
            hasAppliedBackgroundColorOnce = true
            AnimationRunner.run(
                animation: isFirstApply ? nil : backgroundColorAnimation,
                additionalOptions: [.allowUserInteraction],
                viewBlock: { [self] in self.backgroundColor = bgColor }
            )
        }

        // Apply dynamic tint color from properties (overrides style color).
        // Must run before the icon-cache early returns below.
        if let tintExpr = props.tintColor?.value {
            let resolved = viewModel.resolvePropertyToString(tintExpr)
            let color = UIColor(withHexString: resolved)
            if let color, lastTintColor.map({ $0 == .some(color) }) != true {
                lastTintColor = .some(.some(color))
                let isFirstApply = !hasAppliedTintColorOnce
                hasAppliedTintColorOnce = true
                AnimationRunner.run(
                    animation: isFirstApply ? nil : tintColorAnimation,
                    additionalOptions: [.allowUserInteraction],
                    viewBlock: { [self] in self.imageView.tintColor = color }
                )
            }
        }

        switch props.model {
        case .symbol(let symbol):
            let resolvedName = viewModel.resolvePropertyToString(symbol.name)
            let symbolFontSize = viewModel.currentStyle?.symbolFontSize ?? 17
            let iconKey = "\(resolvedName)@\(symbolFontSize)"
            guard lastLoadedIconKey != iconKey else { return }
            lastLoadedIconKey = iconKey

            let config = UIImage.SymbolConfiguration(pointSize: symbolFontSize)
            let image = UIImage(systemName: resolvedName, withConfiguration: config)

            if let renderingMode = viewModel.currentStyle?.renderingMode {
                imageView.image = image?.withRenderingMode(renderingMode.ui)
            } else {
                // Default to template for SF Symbols so tint color works.
                imageView.image = image?.withRenderingMode(.alwaysTemplate)
            }

        case .asset(let asset):
            guard lastLoadedIconKey != asset.name else { return }
            lastLoadedIconKey = asset.name
            let renderingMode = viewModel.currentStyle?.renderingMode?.ui ?? .automatic
            imageView.image = UIImage(named: asset.name)?.withRenderingMode(renderingMode)

        case .remote(let remote):
            let urlString = remote.url.absoluteString
            guard lastLoadedIconKey != urlString else { return }
            lastLoadedIconKey = urlString
            imageView.image = nil
            let loader = viewModel.service.imageLoader
            let renderingMode = viewModel.currentStyle?.renderingMode?.ui ?? .alwaysTemplate
            Task { [weak self] in
                guard let decoded = await loader.loadImage(urlString: urlString) else { return }
                await MainActor.run {
                    self?.imageView.image = decoded.withRenderingMode(renderingMode)
                }
            }

        case .none:
            imageView.image = nil
        }
    }

    private func updateChildren(viewModel: CIconViewModel, animated: Bool) {
        let newChildren = viewModel.component.children

        // Remove children that are gone or whose type changed.
        var toRemove: [String] = []
        for (id, tracked) in trackedChildren {
            if let newChild = newChildren.first(where: { $0.id == id }) {
                if typeName(for: newChild.type) != tracked.typeName {
                    toRemove.append(id)
                }
            } else {
                toRemove.append(id)
            }
        }
        for id in toRemove {
            if let tracked = trackedChildren.removeValue(forKey: id) {
                tracked.view.removeFromSuperview()
            }
        }

        for child in newChildren {
            if let tracked = trackedChildren[child.id] {
                if typeName(for: child.type) == tracked.typeName,
                   let updatable = tracked.view as? StreamingUpdatable {
                    let childPath = viewModel.componentPath + "." + child.id
                    updatable.streamingUpdate(
                        component: child, service: viewModel.service,
                        parentVariableStore: viewModel.variableStore,
                        componentPath: childPath, animated: animated
                    )
                }
                continue
            }
            let result = viewModel.service.renderComponent(
                child, superview: contentView,
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
}

// MARK: - StreamingUpdatable

extension CIconView: StreamingUpdatable {

    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CIconViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }

        self.viewModel = vm
        suppressStyleContent = true
        bindStyle(vm.style, animation: vm.animation)
        suppressStyleContent = false
        bindProperties(viewModel: vm)
        bindVariables(viewModel: vm)
        configureContent(viewModel: vm, animated: animated)
        return vm
    }
}
