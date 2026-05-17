import UIKit

@MainActor
final class CCollectionCell: UICollectionViewCell {

    static let reuseId = "CCollectionCell"

    private weak var renderedView: UIView?
    private weak var currentViewModel: ComponentViewModelAbstract?

    /// The root variable store of the view's internal VM tree.
    /// Used for fast reparenting: swapping the parent store triggers reactive
    /// updates in all child views (labels via propertiesWithVariables, images/icons
    /// via variablesChanged subscriptions) without recreating any VMs.
    private var rootViewVariableStore: ScopedVariableStore?

    /// Whether this cell should self-size its width (horizontal collections with estimatedItemWidth)
    var selfSizesWidth = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Allow shadows from MaterialView to render beyond cell bounds.
        // Child clipping is handled by contentView.layer.masksToBounds (via cornerStyle).
        clipsToBounds = false
        contentView.clipsToBounds = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        setNeedsLayout()
        layoutIfNeeded()

        let size = contentView.systemLayoutSizeFitting(
            layoutAttributes.size,
            withHorizontalFittingPriority: selfSizesWidth ? .fittingSizeLevel : .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        var frame = layoutAttributes.frame
        if selfSizesWidth { frame.size.width = ceil(size.width) }
        frame.size.height = ceil(size.height)
        layoutAttributes.frame = frame

        return layoutAttributes
    }

    // MARK: - Configure (reuse path — cached VM exists)

    /// The cached VM is always a CellVariableStoreWrapper whose variableStore is the cellStore.
    func configure(
        reusingViewModel viewModel: ComponentViewModelAbstract,
        template: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentPath: String
    ) {
        // Fast path: reparent existing VM tree to the cached cellStore;
        // all views update via their existing variable-store subscriptions.
        if let rootStore = rootViewVariableStore, renderedView != nil {
            rootStore.reparent(to: viewModel.variableStore)
            currentViewModel = viewModel
            return
        }

        // Slow path: build VM tree via streamingUpdate (first time for this cell)
        if renderedView != nil, let updatable = renderedView as? StreamingUpdatable {
            let componentPath = parentPath + "." + template.id
            let vm = updatable.streamingUpdate(
                component: template,
                service: service,
                parentVariableStore: viewModel.variableStore,
                componentPath: componentPath,
                animated: false
            )
            if let vm = vm {
                rootViewVariableStore = vm.variableStore
                currentViewModel = viewModel
                return
            }
        }

        // Fallback: no existing view — full render
        renderedView?.removeFromSuperview()
        rootViewVariableStore = nil

        let result = service.renderComponent(
            template,
            superview: contentView,
            parentPath: parentPath,
            parentVariableStore: viewModel.variableStore
        )
        renderedView = result.view
        currentViewModel = viewModel
        if let vm = result.viewModel {
            rootViewVariableStore = vm.variableStore
        }
        setupConstraints()
    }

    // MARK: - Configure (new path — no cached VM)

    func configure(
        template: DSL.Model.Component.`Any`,
        variableStore: ScopedVariableStore,
        service: ComponentService,
        parentPath: String,
        onViewModelCreated: ((ComponentViewModelAbstract) -> Void)? = nil
    ) {
        // Fast path: reparent existing VM tree to the new cellStore
        if let rootStore = rootViewVariableStore, renderedView != nil {
            rootStore.reparent(to: variableStore)
            let wrapper = CellVariableStoreWrapper(store: variableStore, path: "")
            currentViewModel = wrapper
            onViewModelCreated?(wrapper)
            return
        }

        // Slow path: build VM tree via streamingUpdate
        if let updatable = renderedView as? StreamingUpdatable {
            let componentPath = parentPath + "." + template.id
            let vm = updatable.streamingUpdate(
                component: template,
                service: service,
                parentVariableStore: variableStore,
                componentPath: componentPath,
                animated: false
            )
            if let vm = vm {
                rootViewVariableStore = vm.variableStore
                let wrapper = CellVariableStoreWrapper(store: variableStore, path: "")
                currentViewModel = wrapper
                onViewModelCreated?(wrapper)
                return
            }
        }

        // Fallback: full render (no existing view)
        renderedView?.removeFromSuperview()
        rootViewVariableStore = nil

        let result = service.renderComponent(
            template,
            superview: contentView,
            parentPath: parentPath,
            parentVariableStore: variableStore
        )

        renderedView = result.view
        if let vm = result.viewModel {
            rootViewVariableStore = vm.variableStore
        }
        setupConstraints()

        let wrapper = CellVariableStoreWrapper(store: variableStore, path: "")
        currentViewModel = wrapper
        onViewModelCreated?(wrapper)
    }

    private func setupConstraints() {
        guard let view = renderedView else { return }
        view.translatesAutoresizingMaskIntoConstraints = false

        let bottomConstraint = view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        bottomConstraint.priority = .defaultHigh

        let trailingConstraint = view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)

        if selfSizesWidth {
            // Let content determine width: low-priority trailing lets the rendered view be wider
            // than the initial estimated cell frame while labels/icons keep their intrinsic sizes.
            // propagateContentHugging(…) pins every subview's hugging + compression to .required
            // so labels never wrap and icons never clip during initial layout at the estimated
            // width. The internal stack trailing constraints are lowered to 999 so the hugging
            // at 1000 wins the conflict cleanly, allowing the chip to grow past the estimated
            // cell frame. `preferredLayoutAttributesFitting` then reports the natural size and
            // the compositional layout's .estimated() group resizes to match.
            trailingConstraint.priority = .defaultLow
            propagateContentHugging(in: view)
        }

        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentView.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            trailingConstraint,
            bottomConstraint
        ])
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// Walks the view hierarchy and forces every view's content hugging + compression resistance
    /// to .required (1000), and lowers any .required trailing constraints created by
    /// `cMakeEqualToSuperview` to 999. This gives labels/icons rigid intrinsic sizing that beats
    /// the lowered internal trailing constraints, letting the chip size to its natural content
    /// width even when the cell frame is initially at the estimated width.
    private func propagateContentHugging(in view: UIView) {
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)

        for constraint in view.constraints {
            if constraint.firstAttribute == .trailing || constraint.secondAttribute == .trailing {
                if constraint.priority == .required {
                    constraint.priority = UILayoutPriority(999)
                }
            }
        }

        for subview in view.subviews {
            propagateContentHugging(in: subview)
        }
    }
}

// MARK: - CellVariableStoreWrapper

/// Lightweight VM wrapper around a cellStore for caching.
/// The cellStore has "item" defined, so updateItemVariable works directly on it.
/// The cellStore's parent is the collection's variableStore — never a descendant of the view's internal stores.
@MainActor
final class CellVariableStoreWrapper: ComponentViewModelAbstract {
    let variableStore: ScopedVariableStore
    let componentPath: String

    init(store: ScopedVariableStore, path: String) {
        self.variableStore = store
        self.componentPath = path
    }
}

// MARK: - CCollectionHeaderView

@MainActor
final class CCollectionHeaderView: UICollectionReusableView {

    static let reuseId = "CCollectionHeaderView"

    private var renderedView: UIView?

    override func prepareForReuse() {
        super.prepareForReuse()
    }

    func configure(
        template: DSL.Model.Component.`Any`,
        variableStore: ScopedVariableStore,
        service: ComponentService,
        parentPath: String
    ) {
        renderedView?.removeFromSuperview()

        let result = service.renderComponent(
            template,
            superview: self,
            parentPath: parentPath,
            parentVariableStore: variableStore
        )

        renderedView = result.view
        renderedView?.translatesAutoresizingMaskIntoConstraints = false

        if let view = renderedView {
            let bottomConstraint = view.bottomAnchor.constraint(equalTo: bottomAnchor)
            bottomConstraint.priority = .defaultHigh

            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                bottomConstraint
            ])
        }

        setNeedsLayout()
        layoutIfNeeded()
    }
}
