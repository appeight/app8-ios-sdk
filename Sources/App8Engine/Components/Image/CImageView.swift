import UIKit
import Combine

class CImageView: App8BaseView<DSL.Model.Component.Image.C>, CViewProtocol {

    private var viewModel: CImageViewModel?
    var layoutModeId: String? { viewModel?.componentPath.split(separator: ".").last.map(String.init) }
    var layoutModeContext: App8LayoutMode? { viewModel?.service.context.layoutMode }
    weak var materialView: MaterialView?
    let contentView = UIView()
    private let imageView = UIImageView()

    override var intrinsicContentSource: UIView? { imageView }

    private var variablesCancellable: AnyCancellable?

    override func setup() {
        super.setup()
        
        addSubview(contentView)
        contentView.cMakeEqualToSuperview()
        
        contentView.addSubview(imageView)
        imageView.cMakeEqualToSuperview()
    }
    
    func configure(viewModel: CImageViewModel, superview: UIView? = nil, animated: Bool = true) {
        self.viewModel = viewModel
        guard let superview = superview ?? self.superview else {
            return
        }
        bindLayout(viewModel.layout, in: superview, viewRegistry: viewModel.service.componentRegistry.viewRegistry, parentComponentPath: viewModel.parentPath, keyboardService: viewModel.service.context.keyboardService, animated: animated)
        bindStyle(viewModel.style, animation: viewModel.animation)
        bindVariables(viewModel: viewModel)
        configureContent(viewModel: viewModel, animated: animated)
    }

    /// Subscribe to "item" variable changes and reparent signals ("") —
    /// re-resolves image URL when cell data changes.
    /// Filters out unrelated variable changes (e.g. scroll offset) that would trigger
    /// expensive resolvePropertyToString calls on every scroll frame for no reason.
    private func bindVariables(viewModel: CImageViewModel) {
        variablesCancellable?.cancel()
        variablesCancellable = viewModel.variablesChanged
            .filter { $0 == "item" || $0.isEmpty }
            .prepend("")
            .sink { [weak self] _ in
                guard let self, let vm = self.viewModel else { return }
                self.applyImageContent(viewModel: vm, animated: false)
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

        guard !(viewModel?.service.context.layoutMode.isEnabled == true) else {
            imageView.image = nil
            return
        }

        imageView.contentMode = style?.contentMode?.ui ?? .scaleAspectFill
        imageView.tintColor = style?.tintColor?.ui

        // Corner radius: direct corner takes precedence over the material's corner.
        // Register the corner so a `fraction` radius is re-resolved on resize.
        if let corner = style?.corner {
            imageView.layer.apply(cornerStyle: corner)
            trackRelativeCorner(corner, on: imageView.layer)
        } else if let material = style?.material,
                  let cornerStyle = MaterialView.cornerStyle(inMaterial: material) {
            imageView.layer.apply(cornerStyle: cornerStyle.content)
            trackRelativeCorner(cornerStyle.content, on: imageView.layer)
        } else {
            imageView.layer.cornerRadius = 0
            trackRelativeCorner(.none, on: imageView.layer)
        }
    }
    
    /// Tracks rendered children by component id → (view, type name) for diffing during reuse
    private var trackedChildren: [String: (view: UIView, typeName: String)] = [:]

    /// Last loaded image key to skip redundant loads on reuse
    private var lastLoadedImageKey: String?

    // TODO: take 'animated' flag into account
    private func configureContent(viewModel: CImageViewModel, animated: Bool = false) {
        if viewModel.service.context.layoutMode.isEnabled {
            imageView.image = nil
            viewModel.component.children.forEach { c in
                viewModel.service.renderComponent(c, superview: contentView, parentPath: viewModel.componentPath, parentVariableStore: viewModel.variableStore)
            }
            return
        }

        applyImageContent(viewModel: viewModel, animated: animated)
        updateChildren(viewModel: viewModel, animated: animated)
    }

    private func applyImageContent(viewModel: CImageViewModel, animated: Bool) {
        let props = viewModel.component.properties
        switch props.model {
        case .asset(let asset):
            guard lastLoadedImageKey != asset.name else { return }
            lastLoadedImageKey = asset.name
            imageView.image = UIImage(named: asset.name)?
                .withRenderingMode(viewModel.currentStyle?.renderingMode?.ui ?? .automatic)

        case .remoteAsset(let remoteAsset):
            let resolvedUrl: String?
            if let url = remoteAsset.url {
                let resolved = viewModel.resolvePropertyToString(url)
                resolvedUrl = resolved.isEmpty ? nil : resolved
            } else {
                resolvedUrl = nil
            }
            let resolvedName: String?
            if let name = remoteAsset.name {
                resolvedName = viewModel.resolvePropertyToString(name)
            } else {
                resolvedName = nil
            }
            // Effective URL: explicit url field, or name if it looks like a URL.
            let effectiveUrl = resolvedUrl
                ?? (resolvedName.flatMap { $0.hasPrefix("http://") || $0.hasPrefix("https://") ? $0 : nil })

            let imageKey = effectiveUrl ?? resolvedName ?? remoteAsset.id
            guard lastLoadedImageKey != imageKey else { return }
            lastLoadedImageKey = imageKey

            imageView.image = nil
            // Prefer the data source: it owns prefetched assets and resolves
            // them by id/name from a cache the host app populates. Only fall
            // back to URL when the asset isn't in the data source — typically
            // because the DSL hard-codes an external URL.
            let dataSource = viewModel.service.dataSource
            let loader = viewModel.service.imageLoader
            let assetId = remoteAsset.id
            Task { [weak self] in
                if let imageData = try? await dataSource.getAsset(assetId: assetId, assetName: resolvedName),
                   let decoded = await UIImage(data: imageData)?.byPreparingForDisplay() {
                    await MainActor.run { self?.imageView.image = decoded }
                    return
                }
                if let effectiveUrl,
                   let decoded = await loader.loadImage(urlString: effectiveUrl) {
                    await MainActor.run { self?.imageView.image = decoded }
                }
            }

        case .none:
            guard lastLoadedImageKey != nil else { return }
            lastLoadedImageKey = nil
            imageView.image = nil
        }
    }

    private func updateChildren(viewModel: CImageViewModel, animated: Bool) {
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

extension CImageView: StreamingUpdatable {

    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CImageViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }

        self.viewModel = vm
        bindStyle(vm.style, animation: vm.animation)
        bindVariables(viewModel: vm)
        configureContent(viewModel: vm, animated: animated)
        return vm
    }
}
