import UIKit
import Combine

@MainActor
final class CCollectionView: App8BaseView<CollectionContent>, CViewProtocol {

    // MARK: - CViewProtocol

    weak var materialView: MaterialView?
    let contentView = UIView()

    // MARK: - UI

    private lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: createLayout())
        cv.backgroundColor = .clear
        cv.delegate = self
        cv.dataSource = self
        return cv
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        return rc
    }()

    private var emptyStateView: UIView?
    private var loadingStateView: UIView?
    private var errorStateView: UIView?

    // MARK: - State

    private var viewModel: CCollectionViewModel?
    var layoutModeId: String? { viewModel?.componentPath.split(separator: ".").last.map(String.init) }
    var layoutModeContext: App8LayoutMode? { viewModel?.service.context.layoutMode }
    private var sections: [CCollectionViewModel.Section] = []
    private var cancellables = Set<AnyCancellable>()
    private var isViewHierarchySetup = false
    private var lastReportedPageIndex: Int = -1
    private var isSelfSizing = false             // true when scrollEnabled == false
    private var selfSizingHeightConstraint: NSLayoutConstraint?
    private var cellsSelfSizeWidth = false       // true when horizontal + estimatedItemWidth

    // MARK: - Setup

    override func setup() {
        super.setup()
        // Views are added in applyStyle for correct z-order after materialView.
    }

    private func setupViewHierarchyIfNeeded() {
        guard !isViewHierarchySetup else { return }
        isViewHierarchySetup = true

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()

        contentView.addSubview(collectionView)
        collectionView.cMakeEqualToSuperview()
    }

    // MARK: - Configuration

    func configure(viewModel: CCollectionViewModel, superview: UIView? = nil, animated: Bool = true) {
        self.viewModel = viewModel
        guard let superview = superview ?? self.superview else { return }

        bindLayout(
            viewModel.layout,
            in: superview,
            viewRegistry: viewModel.service.componentRegistry.viewRegistry,
            parentComponentPath: viewModel.parentPath,
            keyboardService: viewModel.service.context.keyboardService,
            animated: animated
        )
        bindStyle(viewModel.style, animation: viewModel.animation)

        registerReusableComponents()
        configureRefreshControl()
        configureLayout()

        bindSections()
        bindEmptyState()
        bindLoadingState()
        bindErrorState()
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

        // Set up view hierarchy after materialView is inserted.
        setupViewHierarchyIfNeeded()

        if let bgColorName = style?.backgroundColor, !(viewModel?.service.context.layoutMode.isEnabled == true) {
            collectionView.backgroundColor = UIColor(withHexString: bgColorName)
        }
    }

    // MARK: - Features Configuration

    private func registerReusableComponents() {
        guard let viewModel = viewModel else { return }

        collectionView.register(CCollectionCell.self, forCellWithReuseIdentifier: CCollectionCell.reuseId)

        // Cell templates use template IDs as reuse identifiers.
        if let template = viewModel.component.template {
            collectionView.register(CCollectionCell.self, forCellWithReuseIdentifier: template.id)
        }
        if let templateRef = viewModel.component.properties.templateName {
            collectionView.register(CCollectionCell.self, forCellWithReuseIdentifier: templateRef)
        }
        if let templates = viewModel.component.templates {
            for (_, templateRef) in templates {
                let reuseId: String
                switch templateRef {
                case .reference(let name):
                    reuseId = name
                case .inline(let component):
                    reuseId = component.id
                }
                collectionView.register(CCollectionCell.self, forCellWithReuseIdentifier: reuseId)
            }
        }

        if let sectionHeader = viewModel.component.defaultSectionHeader {
            collectionView.register(
                CCollectionHeaderView.self,
                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                withReuseIdentifier: sectionHeader.templateId ?? sectionHeader.id
            )
        }

        if let sectionHeaders = viewModel.component.sectionHeaders {
            for (_, template) in sectionHeaders {
                collectionView.register(
                    CCollectionHeaderView.self,
                    forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                    withReuseIdentifier: template.templateId ?? template.id
                )
            }
        }
    }
    
    private func configureRefreshControl() {
        guard viewModel?.component.properties.pullToRefresh == true else { return }
        collectionView.refreshControl = refreshControl
    }

    private func configureLayout() {
        collectionView.setCollectionViewLayout(createLayout(), animated: false)

        if viewModel?.component.properties.inverted == true {
            collectionView.transform = CGAffineTransform(scaleX: 1, y: -1)
        }

        let showIndicator = viewModel?.component.properties.layout?.showsScrollIndicator ?? true
        let isHorizontal = viewModel?.component.properties.layout?.type == .horizontal
        if isHorizontal {
            collectionView.showsHorizontalScrollIndicator = showIndicator
            collectionView.showsVerticalScrollIndicator = false
        } else {
            collectionView.showsVerticalScrollIndicator = showIndicator
            collectionView.showsHorizontalScrollIndicator = false
        }

        // Horizontal scrolling is handled by orthogonal section behavior, not the
        // collection view itself, so disable its main-axis scrolling.
        if isHorizontal {
            collectionView.alwaysBounceVertical = false
            collectionView.isScrollEnabled = false
        } else {
            let scrollEnabled = viewModel?.component.properties.layout?.scrollEnabled ?? true
            collectionView.isScrollEnabled = scrollEnabled
            collectionView.alwaysBounceVertical = scrollEnabled
            collectionView.alwaysBounceHorizontal = false
            selfSizingHeightConstraint?.isActive = false
            selfSizingHeightConstraint = nil
            isSelfSizing = !scrollEnabled
            if isSelfSizing {
                let hc = heightAnchor.constraint(equalToConstant: 0)
                hc.priority = UILayoutPriority(999)
                hc.isActive = true
                selfSizingHeightConstraint = hc
            }
        }

        // clipsToBounds: explicit control over UICollectionView clipping.
        // Default: true (UIScrollView native behavior). Set to false on collections
        // where cell shadows need to render beyond collection bounds (e.g. carousels with avatars).
        collectionView.clipsToBounds = viewModel?.component.properties.clipsToBounds ?? true
        // Apply only TOP to UICollectionView.contentInset (for scroll offset/collapsing headers)
        // Left/right/bottom are applied to section.contentInsets in layout creation
        // TODO: proper support of contentInsets
        if let insets = viewModel?.component.properties.layout?.contentInsets {
            collectionView.contentInset = UIEdgeInsets(top: insets.top ?? 0, left: 0, bottom: insets.bottom ?? 0, right: 0)
        }
    }

    // MARK: - Layout Creation

    private func createLayout() -> UICollectionViewLayout {
        guard let props = viewModel?.component.properties,
              let layoutConfig = props.layout else {
            return createVerticalListLayout()
        }

        switch layoutConfig.type {
        case .vertical, .none:
            return createVerticalListLayout(config: layoutConfig)
        case .horizontal:
            return createHorizontalLayout(config: layoutConfig)
        case .grid:
            return createGridLayout(config: layoutConfig)
        }
    }

    private func createVerticalListLayout(config: DSL.Model.Component.Collection.Layout? = nil) -> UICollectionViewCompositionalLayout {
        // Per-section layout is needed when there are overrides or per-section headers.
        if viewModel?.component.properties.defaultSectionLayout != nil ||
           viewModel?.component.properties.sectionLayouts != nil ||
           viewModel?.component.sectionHeaders != nil {
            return createMixedSectionsLayout(outerConfig: config)
        }

        // Swipe actions require list configuration (UIKit native path)
        if viewModel?.component.properties.swipeActions != nil {
            return createSwipeableListLayout(config: config)
        }

        let estimatedHeight = config?.estimatedItemHeight ?? 44

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(estimatedHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(estimatedHeight)
        )
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = config?.itemSpacing ?? 0

        // Apply left/right/bottom to section insets (top is handled by UICollectionView.contentInset for scroll offset)
        if let insets = config?.contentInsets {
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 0,
                leading: insets.left ?? 0,
                bottom: insets.bottom ?? 0,
                trailing: insets.right ?? 0
            )
        }

        if viewModel?.component.defaultSectionHeader != nil {
            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(44)
            )
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            header.pinToVisibleBounds = viewModel?.component.properties.stickyHeaders == true
            section.boundarySupplementaryItems = [header]
        }

        return UICollectionViewCompositionalLayout(section: section)
    }

    /// Builds a list-configuration-based vertical layout that supports leading/trailing swipe actions.
    /// Uses UICollectionLayoutListConfiguration which provides the native iOS swipe action animations.
    private func createSwipeableListLayout(config: DSL.Model.Component.Collection.Layout?) -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { [weak self] _, environment in
            var listConfig = UICollectionLayoutListConfiguration(appearance: .plain)
            // Transparent background + no separators so cells render identically to the
            // custom vertical layout. The DSL handles separators/styling via the cell itself.
            listConfig.backgroundColor = .clear
            listConfig.showsSeparators = false

            listConfig.leadingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                self?.swipeActionsConfiguration(for: indexPath, leading: true)
            }
            listConfig.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                self?.swipeActionsConfiguration(for: indexPath, leading: false)
            }

            let section = NSCollectionLayoutSection.list(using: listConfig, layoutEnvironment: environment)
            section.interGroupSpacing = config?.itemSpacing ?? 0

            if let insets = config?.contentInsets {
                section.contentInsets = NSDirectionalEdgeInsets(
                    top: 0,
                    leading: insets.left ?? 0,
                    bottom: insets.bottom ?? 0,
                    trailing: insets.right ?? 0
                )
            }

            if self?.viewModel?.component.defaultSectionHeader != nil {
                let headerSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .estimated(44)
                )
                let header = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: headerSize,
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                )
                header.pinToVisibleBounds = self?.viewModel?.component.properties.stickyHeaders == true
                section.boundarySupplementaryItems = [header]
            }

            return section
        }
    }

    /// Build a UISwipeActionsConfiguration from the DSL swipeActions definition.
    private func swipeActionsConfiguration(for indexPath: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? {
        guard let swipeActions = viewModel?.component.properties.swipeActions else { return nil }
        let actions = leading ? swipeActions.leading : swipeActions.trailing
        guard let actions = actions, !actions.isEmpty else { return nil }

        let contextualActions: [UIContextualAction] = actions.map { swipe in
            let style: UIContextualAction.Style = (swipe.style == .destructive) ? .destructive : .normal
            let action = UIContextualAction(style: style, title: swipe.title) { [weak self] _, _, completion in
                guard let self = self else { completion(true); return }
                let oldSections = self.sections
                if let dslAction = swipe.action {
                    self.viewModel?.handleSwipeAction(at: indexPath, action: dslAction)
                }
                // Reactive chain is synchronous up to currentSections, so check if the
                // swipe caused deletions and drive a native animated delete immediately.
                // This aligns the data source update with UIKit's swipe-commit animation,
                // instead of waiting for the async bindSections tick.
                if let newSections = self.viewModel?.currentSections,
                   let deletions = self.computeDeletions(from: oldSections, to: newSections),
                   !deletions.isEmpty {
                    self.sections = newSections
                    self.collectionView.performBatchUpdates {
                        self.collectionView.deleteItems(at: deletions)
                    }
                }
                completion(true)
            }
            if let hex = swipe.backgroundColor, let color = UIColor(withHexString: hex) {
                action.backgroundColor = color
            }
            if let symbolName = swipe.systemImage {
                action.image = UIImage(systemName: symbolName)
            }
            return action
        }

        let config = UISwipeActionsConfiguration(actions: contextualActions)
        config.performsFirstActionWithFullSwipe = swipeActions.allowFullSwipe ?? true
        return config
    }

    private func createHorizontalLayout(config: DSL.Model.Component.Collection.Layout) -> UICollectionViewCompositionalLayout {
        let itemHeight = config.itemHeight ?? 100

        // Item width: absolute (fixed), estimated (self-sizing from data), or full width
        let widthDimension: NSCollectionLayoutDimension
        if let itemWidth = config.itemWidth {
            widthDimension = .absolute(itemWidth)
            cellsSelfSizeWidth = false
        } else if let estimatedWidth = config.estimatedItemWidth {
            widthDimension = .estimated(estimatedWidth)
            cellsSelfSizeWidth = true
        } else {
            widthDimension = .fractionalWidth(1.0)
            cellsSelfSizeWidth = false
        }

        let itemSize = NSCollectionLayoutSize(
            widthDimension: widthDimension,
            heightDimension: .absolute(itemHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: widthDimension,
            heightDimension: .absolute(itemHeight)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = orthogonalBehavior(for: config)
        section.interGroupSpacing = config.itemSpacing ?? 0

        // Apply left/right/bottom to section insets (top handled by UICollectionView.contentInset)
        if let insets = config.contentInsets {
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 0,
                leading: insets.left ?? 0,
                bottom: insets.bottom ?? 0,
                trailing: insets.right ?? 0
            )
        }

        if config.currentPageVariable != nil {
            section.visibleItemsInvalidationHandler = { [weak self] items, offset, environment in
                self?.handlePageChange(offset: offset, containerWidth: environment.container.effectiveContentSize.width)
            }
        }

        return UICollectionViewCompositionalLayout(section: section)
    }

    /// Handles page change detection for horizontal paging collections
    private func handlePageChange(offset: CGPoint, containerWidth: CGFloat) {
        guard let config = viewModel?.component.properties.layout,
              let varName = config.currentPageVariable,
              containerWidth > 0 else { return }

        let currentPage = Int(round(offset.x / containerWidth))
        guard currentPage != lastReportedPageIndex else { return }
        lastReportedPageIndex = currentPage
        try? viewModel?.variableStore.setValue(name: varName, value: currentPage)
    }

    private func orthogonalBehavior(for config: DSL.Model.Component.Collection.Layout?) -> UICollectionLayoutSectionOrthogonalScrollingBehavior {
        // New pagingStyle takes priority
        if let style = config?.pagingStyle {
            switch style {
            case .continuous: return .continuous
            case .paging: return .groupPaging
            case .pagingCentered: return .groupPagingCentered
            }
        }
        // Fallback to legacy snapToItem
        return config?.snapToItem == true ? .groupPaging : .continuous
    }

    private func createGridLayout(config: DSL.Model.Component.Collection.Layout) -> UICollectionViewCompositionalLayout {
        let columns = config.columns ?? 2

        let itemSize: NSCollectionLayoutSize
        if let aspectRatio = config.aspectRatio {
            itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                heightDimension: .fractionalWidth(1.0 / CGFloat(columns) / aspectRatio)
            )
        } else if let height = config.itemHeight {
            itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                heightDimension: .absolute(height)
            )
        } else {
            itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                heightDimension: .estimated(config.estimatedItemHeight ?? 100)
            )
        }

        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let spacing = (config.itemSpacing ?? 0) / 2
        item.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: spacing,
            bottom: 0,
            trailing: spacing
        )

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: itemSize.heightDimension
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, repeatingSubitem: item, count: columns)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = config.lineSpacing ?? 0

        // Apply left/right/bottom to section insets (top handled by UICollectionView.contentInset)
        if let insets = config.contentInsets {
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 0,
                leading: insets.left ?? 0,
                bottom: insets.bottom ?? 0,
                trailing: insets.right ?? 0
            )
        }

        return UICollectionViewCompositionalLayout(section: section)
    }

    private func createMixedSectionsLayout(
        outerConfig: DSL.Model.Component.Collection.Layout?
    ) -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            guard let self = self else {
                return self?.buildVerticalSection(config: nil) ?? NSCollectionLayoutSection(
                    group: .vertical(
                        layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44)),
                        subitems: [.init(layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44)))]
                    )
                )
            }

            let props = self.viewModel?.component.properties

            // Resolve effective layout: sectionLayouts[key] → sectionLayout → nil
            var effectiveLayout: DSL.Model.Component.Collection.Layout?
            if let viewModel = self.viewModel,
               sectionIndex < viewModel.currentSections.count {
                let sectionKey = viewModel.currentSections[sectionIndex].key
                effectiveLayout = props?.sectionLayouts?[sectionKey] ?? props?.defaultSectionLayout
            } else {
                effectiveLayout = props?.defaultSectionLayout
            }

            let section: NSCollectionLayoutSection
            var gridOuterSpacing: CGFloat = 0
            switch effectiveLayout?.type {
            case .horizontal:
                section = self.buildHorizontalSection(config: effectiveLayout!, sectionIndex: sectionIndex)
            case .grid:
                section = self.buildGridSection(config: effectiveLayout!)
                gridOuterSpacing = (effectiveLayout?.itemSpacing ?? 0) / 2
            default:
                section = self.buildVerticalSection(config: effectiveLayout)
            }

            // Apply inter-section spacing from outer layout's itemSpacing
            self.applySectionInsets(to: section, config: effectiveLayout, outerConfig: outerConfig, sectionIndex: sectionIndex)
            self.addSectionHeader(to: section, sectionIndex: sectionIndex, gridOuterSpacing: gridOuterSpacing)

            return section
        }
    }

    // MARK: - Section Builders

    private func buildHorizontalSection(
        config: DSL.Model.Component.Collection.Layout,
        sectionIndex: Int
    ) -> NSCollectionLayoutSection {
        // Determine item size: template dimensions take priority, then config values, then defaults
        var itemWidth: CGFloat?
        var itemHeight: CGFloat?

        // Priority 1: Get template dimensions (if available)
        if let viewModel = viewModel,
           sectionIndex < viewModel.currentSections.count,
           let firstItem = viewModel.currentSections[sectionIndex].items.first,
           let template = viewModel.resolveTemplate(for: firstItem),
           let templateLayout = template.extractContent()?.layout {
            if let templateWidth = templateLayout.width,
               case .fixed(let w) = templateWidth {
                itemWidth = CGFloat(w)
            }
            if let templateHeight = templateLayout.height,
               case .fixed(let h) = templateHeight {
                itemHeight = CGFloat(h)
            }
        }

        // Priority 2: Fall back to sectionLayout config
        itemWidth = itemWidth ?? config.itemWidth
        itemHeight = itemHeight ?? config.itemHeight

        // Priority 3: Use defaults
        let resolvedWidth = itemWidth ?? 120
        let resolvedHeight = itemHeight ?? 160

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(resolvedWidth),
            heightDimension: .absolute(resolvedHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let rows = config.rows ?? 1
        let lineSpacing = config.lineSpacing ?? config.itemSpacing ?? 0

        let group: NSCollectionLayoutGroup
        if rows > 1 {
            // Multi-row: vertical group of N items, scrolled horizontally
            let groupHeight = resolvedHeight * CGFloat(rows) + lineSpacing * CGFloat(rows - 1)
            let columnSize = NSCollectionLayoutSize(
                widthDimension: .absolute(resolvedWidth),
                heightDimension: .absolute(groupHeight)
            )
            group = NSCollectionLayoutGroup.vertical(layoutSize: columnSize, repeatingSubitem: item, count: rows)
            group.interItemSpacing = .fixed(lineSpacing)
        } else {
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .absolute(resolvedWidth),
                heightDimension: .absolute(resolvedHeight)
            )
            group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        }

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = orthogonalBehavior(for: config)
        section.interGroupSpacing = config.itemSpacing ?? 0

        return section
    }

    private func buildGridSection(
        config: DSL.Model.Component.Collection.Layout
    ) -> NSCollectionLayoutSection {
        let columns = config.columns ?? 2

        let heightDimension: NSCollectionLayoutDimension
        if let aspectRatio = config.aspectRatio {
            heightDimension = .fractionalWidth(1.0 / CGFloat(columns) / aspectRatio)
        } else if let height = config.itemHeight {
            heightDimension = .absolute(height)
        } else {
            heightDimension = .estimated(config.estimatedItemHeight ?? 100)
        }

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
            heightDimension: heightDimension
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let spacing = (config.itemSpacing ?? 0) / 2
        item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: spacing, bottom: 0, trailing: spacing)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: heightDimension
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, repeatingSubitem: item, count: columns)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = config.lineSpacing ?? 0

        return section
    }

    private func buildVerticalSection(
        config: DSL.Model.Component.Collection.Layout?
    ) -> NSCollectionLayoutSection {
        let heightDimension: NSCollectionLayoutDimension
        if let itemHeight = config?.itemHeight {
            heightDimension = .absolute(itemHeight)
        } else {
            heightDimension = .estimated(config?.estimatedItemHeight ?? 44)
        }

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: heightDimension
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: heightDimension
        )
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = config?.itemSpacing ?? 0

        return section
    }

    private func addSectionHeader(to section: NSCollectionLayoutSection, sectionIndex: Int = -1, gridOuterSpacing: CGFloat = 0) {
        // Global default header applies to all sections
        let hasGlobalHeader = viewModel?.component.defaultSectionHeader != nil
        // Per-section header only applies if this section's key has a matching template
        let sectionKey = (sectionIndex >= 0 && sectionIndex < (viewModel?.currentSections.count ?? 0))
            ? viewModel?.currentSections[sectionIndex].key
            : nil
        let hasPerSectionHeader = sectionKey.flatMap { viewModel?.component.sectionHeaders?[$0] } != nil
        guard hasGlobalHeader || hasPerSectionHeader else { return }

        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(44)
        )
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        // Re-apply the spacing that was removed from section insets to keep the header
        // aligned with the section content edge (not the wider grid content area)
        if gridOuterSpacing > 0 {
            header.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: gridOuterSpacing, bottom: 0, trailing: gridOuterSpacing)
        }
        header.pinToVisibleBounds = viewModel?.component.properties.stickyHeaders == true
        section.boundarySupplementaryItems = [header]
    }

    private func applySectionInsets(
        to section: NSCollectionLayoutSection,
        config: DSL.Model.Component.Collection.Layout?,
        outerConfig: DSL.Model.Component.Collection.Layout?,
        sectionIndex: Int
    ) {
        var sectionInsets = config?.contentInsets?.nsDirectionalEdgeInsets ?? .zero

        // For grid layouts, the item spacing is split evenly across each item's leading/trailing
        // insets, which adds unwanted outer padding on the first and last columns.
        // Compensate by reducing section insets so items align with the content edge.
        if config?.type == .grid {
            let outerSpacing = (config?.itemSpacing ?? 0) / 2
            sectionInsets.leading = max(0, sectionInsets.leading - outerSpacing)
            sectionInsets.trailing = max(0, sectionInsets.trailing - outerSpacing)
        }

        // Add inter-section spacing from outer layout's itemSpacing
        // Apply as bottom padding so space appears between sections,
        // not between a section header and its items
        let interSectionSpacing = outerConfig?.itemSpacing ?? 0
        sectionInsets.bottom += interSectionSpacing

        section.contentInsets = sectionInsets
    }

    // MARK: - Bindings

    private func bindSections() {
        viewModel?.sections
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSections in
                guard let self else { return }
                guard !self.sectionsStructurallyEqual(self.sections, newSections) else { return }
                let oldSections = self.sections
                self.sections = newSections

                // Self-sizing: set estimated height before reloadData so the collection view
                // gets a non-zero frame on the first layout pass (needed to compute contentSize).
                if self.isSelfSizing {
                    let layoutConfig = self.viewModel?.component.properties.layout
                    let itemCount = newSections.reduce(0) { $0 + $1.items.count }
                    let estimatedItemHeight: CGFloat = layoutConfig?.estimatedItemHeight ?? 44
                    let spacing: CGFloat = layoutConfig?.itemSpacing ?? 0
                    let insetsHeight: CGFloat = (layoutConfig?.contentInsets?.top ?? 0) + (layoutConfig?.contentInsets?.bottom ?? 0)
                    let itemsHeight: CGFloat = CGFloat(itemCount) * estimatedItemHeight
                    let gapsHeight: CGFloat = CGFloat(max(0, itemCount - 1)) * spacing
                    let estimatedHeight: CGFloat = itemsHeight + gapsHeight + insetsHeight
                    self.selfSizingHeightConstraint?.constant = estimatedHeight
                    self.superview?.setNeedsLayout()
                }

                // When swipe actions are defined, try to animate deletions via performBatchUpdates
                // instead of hard reload. This makes swipe-to-delete look native (the cell slides out
                // smoothly as UIKit's swipe commit animation completes).
                let hasSwipeActions = self.viewModel?.component.properties.swipeActions != nil
                if hasSwipeActions, let deletions = self.computeDeletions(from: oldSections, to: newSections), !deletions.isEmpty {
                    self.collectionView.performBatchUpdates {
                        self.collectionView.deleteItems(at: deletions)
                    }
                } else {
                    self.collectionView.reloadData()
                }

                // HACK: Force layout invalidation for self-sizing horizontal cells.
                // UICollectionViewCompositionalLayout with .estimated() group dimensions
                // intermittently fails to call preferredLayoutAttributesFitting on cells,
                // leaving them stuck at the estimated width. This happens on both simulator
                // and device, especially after tab switches. Root cause unknown — likely a
                // UIKit timing issue with orthogonal scrolling sections.
                //
                // Two invalidations as a band-aid: the first runs on the next runloop tick
                // (handles the common case); the second runs 50ms later as a safety net for
                // cells that missed the first pass. The 50ms delay is arbitrary and may cause
                // a brief visual snap on slow devices. A proper fix would require understanding
                // why UIKit skips cell measurement after invalidation in certain timing windows.
                if self.cellsSelfSizeWidth {
                    DispatchQueue.main.async { [weak self] in
                        self?.collectionView.collectionViewLayout.invalidateLayout()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                        self?.collectionView.collectionViewLayout.invalidateLayout()
                    }
                }

                // Refine height from actual contentSize after cells lay out.
                if self.isSelfSizing {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        let actual = self.collectionView.contentSize.height
                        if actual > 0, actual != self.selfSizingHeightConstraint?.constant {
                            self.selfSizingHeightConstraint?.constant = actual
                            self.superview?.setNeedsLayout()
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Fingerprint an item for the diff in `computeDeletions`. Prefers the item's `id`
    /// field (stable identity) and falls back to full value stringification.
    /// The "id:" / "val:" prefix prevents accidental collisions between the two paths.
    private static func itemFingerprint(_ item: CCollectionViewModel.ItemWrapper) -> String {
        if let dict = item.data.value as? [String: Any], let id = dict["id"] {
            return "id:" + String(describing: id)
        }
        return "val:" + String(describing: item.data.value)
    }

    /// Compute deleted index paths between old and new sections for the delete-only case.
    /// Returns nil if the change is NOT a pure deletion (insertion, reorder, or section change).
    /// Used to drive native delete animations via performBatchUpdates when swipe actions are active.
    private func computeDeletions(
        from old: [CCollectionViewModel.Section],
        to new: [CCollectionViewModel.Section]
    ) -> [IndexPath]? {
        guard old.count == new.count else { return nil }
        var deletions: [IndexPath] = []
        for (sIdx, (oldSection, newSection)) in zip(old, new).enumerated() {
            guard oldSection.key == newSection.key else { return nil }
            // Only handle shrinking sections
            guard oldSection.items.count >= newSection.items.count else { return nil }

            // Fingerprint items: prefer the `id` field when present (stable across content edits),
            // fall back to stringifying the entire value.
            let oldIds = oldSection.items.map { Self.itemFingerprint($0) }
            let newIds = newSection.items.map { Self.itemFingerprint($0) }

            // Walk both arrays; new must be a subsequence of old.
            var oi = 0, ni = 0
            while oi < oldIds.count && ni < newIds.count {
                if oldIds[oi] == newIds[ni] {
                    oi += 1; ni += 1
                } else {
                    deletions.append(IndexPath(item: oi, section: sIdx))
                    oi += 1
                }
            }
            // Any remaining old items are deletions at the tail
            while oi < oldIds.count {
                deletions.append(IndexPath(item: oi, section: sIdx))
                oi += 1
            }
            // If we didn't consume all new items, it's a reorder/replace → fall back to reload
            guard ni == newIds.count else { return nil }
        }
        return deletions
    }

    /// Compare sections by structure (count, keys, item counts) to avoid redundant reloadData().
    /// Does NOT compare item data — only structural identity.
    private func sectionsStructurallyEqual(
        _ old: [CCollectionViewModel.Section],
        _ new: [CCollectionViewModel.Section]
    ) -> Bool {
        guard old.count == new.count else { return false }
        for (oldSection, newSection) in zip(old, new) {
            if oldSection.key != newSection.key { return false }
            if oldSection.items.count != newSection.items.count { return false }
        }
        return true
    }

    private func bindEmptyState() {
        viewModel?.isEmpty
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEmpty in
                self?.updateEmptyState(isEmpty: isEmpty)
            }
            .store(in: &cancellables)
    }

    private func updateEmptyState(isEmpty: Bool) {
        if isEmpty, let emptyTemplate = viewModel?.component.emptyState {
            if emptyStateView == nil, let viewModel = viewModel {
                let result = viewModel.service.renderComponent(
                    emptyTemplate,
                    superview: contentView,
                    parentPath: viewModel.componentPath,
                    parentVariableStore: viewModel.variableStore
                )
                emptyStateView = result.view
            }
            emptyStateView?.isHidden = false
            collectionView.isHidden = true
        } else {
            emptyStateView?.isHidden = true
            collectionView.isHidden = false
        }
    }

    private func bindLoadingState() {
        viewModel?.isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.updateLoadingState(isLoading: isLoading)
            }
            .store(in: &cancellables)
    }

    private func updateLoadingState(isLoading: Bool) {
        if isLoading, let loadingTemplate = viewModel?.component.loadingState {
            if loadingStateView == nil, let viewModel = viewModel {
                let result = viewModel.service.renderComponent(
                    loadingTemplate,
                    superview: contentView,
                    parentPath: viewModel.componentPath + ".loading",
                    parentVariableStore: viewModel.variableStore
                )
                loadingStateView = result.view
            }
            loadingStateView?.isHidden = false
            collectionView.isHidden = true
            emptyStateView?.isHidden = true
            errorStateView?.isHidden = true
        } else {
            loadingStateView?.isHidden = true
        }
    }

    private func bindErrorState() {
        viewModel?.error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.updateErrorState(error: error)
            }
            .store(in: &cancellables)
    }

    private func updateErrorState(error: Error?) {
        if error != nil, let errorTemplate = viewModel?.component.errorState {
            if errorStateView == nil, let viewModel = viewModel {
                let result = viewModel.service.renderComponent(
                    errorTemplate,
                    superview: contentView,
                    parentPath: viewModel.componentPath + ".error",
                    parentVariableStore: viewModel.variableStore
                )
                errorStateView = result.view
            }
            errorStateView?.isHidden = false
            collectionView.isHidden = true
            emptyStateView?.isHidden = true
            loadingStateView?.isHidden = true
        } else {
            errorStateView?.isHidden = true
        }
    }

    // MARK: - Actions

    @objc private func handleRefresh() {
        viewModel?.handleRefresh()
        refreshControl.endRefreshing()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - UICollectionViewDataSource

extension CCollectionView: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[safe: section]?.items.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        // UIKit may call this with a stale IndexPath if `sections` changed
        // out of sync with reloadData.
        guard let item = sections[safe: indexPath.section]?.items[safe: indexPath.item] else {
            return collectionView.dequeueReusableCell(withReuseIdentifier: CCollectionCell.reuseId, for: indexPath)
        }

        guard let template = viewModel?.resolveTemplate(for: item),
              let viewModel = viewModel else {
            return collectionView.dequeueReusableCell(withReuseIdentifier: CCollectionCell.reuseId, for: indexPath)
        }

        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: template.id,
            for: indexPath
        ) as? CCollectionCell else {
            viewModel.service.context.logger.error("CCollectionView: dequeued cell for template '\(template.id)' is not a CCollectionCell — returning empty placeholder")
            return collectionView.dequeueReusableCell(withReuseIdentifier: CCollectionCell.reuseId, for: indexPath)
        }
        cell.selfSizesWidth = cellsSelfSizeWidth

        let parentPath = viewModel.componentPath + ".cell[\(item.index)]"

        // Check for cached ViewModel
        if let cachedVM = viewModel.getCachedViewModel(section: indexPath.section, item: indexPath.item) {
            viewModel.updateItemVariable(in: cachedVM, with: item)
            cell.configure(
                reusingViewModel: cachedVM,
                template: template,
                service: viewModel.service,
                parentPath: parentPath
            )
        } else {
            let cellStore = viewModel.createCellVariableStore(for: item)
            cell.configure(
                template: template,
                variableStore: cellStore,
                service: viewModel.service,
                parentPath: parentPath,
                onViewModelCreated: { vm in
                    viewModel.cacheViewModel(vm, section: indexPath.section, item: indexPath.item)
                }
            )
        }

        if viewModel.component.properties.inverted == true {
            cell.contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
        }

        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader,
              let viewModel = viewModel else {
            return UICollectionReusableView()
        }

        let section = sections[indexPath.section]
        let sectionKey = section.key
        let headerTemplate = viewModel.component.sectionHeaders?[sectionKey]
                          ?? viewModel.component.defaultSectionHeader

        guard let headerTemplate else { return UICollectionReusableView() }

        guard let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: headerTemplate.templateId ?? headerTemplate.id,
            for: indexPath
        ) as? CCollectionHeaderView else {
            viewModel.service.context.logger.error("CCollectionView: dequeued header for template '\(headerTemplate.templateId ?? headerTemplate.id)' is not a CCollectionHeaderView — returning empty placeholder")
            return UICollectionReusableView()
        }

        // "section" is defined as a dictionary so {{section.key}} works via member access.
        let sectionStore = ScopedVariableStore(parent: viewModel.variableStore)
        do {
            let sectionData: [String: Any] = [
                "key": section.key,
                "$index": indexPath.section
            ]
            try sectionStore.defineVariable(
                name: "section",
                definition: VariableDefinition(type: .object, initialValue: sectionData)
            )
        } catch {
            viewModel.service.context.logger.error("Failed to inject section variables: \(error)")
        }

        header.configure(
            template: headerTemplate,
            variableStore: sectionStore,
            service: viewModel.service,
            parentPath: viewModel.componentPath + ".header[\(indexPath.section)]"
        )

        return header
    }
}

// MARK: - UICollectionViewDelegate

extension CCollectionView: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        viewModel?.handleSelection(at: indexPath)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Offset is adjusted for contentInset so it reads 0 at the rest position.
        if let outputVar = viewModel?.component.properties.scrollOffsetVariable {
            let isHorizontal = viewModel?.component.properties.layout?.type == .horizontal
            let rawOffset = isHorizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y
            let inset = isHorizontal ? scrollView.contentInset.left : scrollView.contentInset.top
            let offset = rawOffset + inset
            try? viewModel?.variableStore.setValue(name: outputVar, value: offset)
        }

        guard let pagination = viewModel?.component.properties.pagination,
              pagination.enabled == true else { return }

        let threshold = CGFloat(pagination.threshold ?? 5) * 44 // rough estimate
        let contentHeight = scrollView.contentSize.height
        let scrollPosition = scrollView.contentOffset.y + scrollView.bounds.height

        if scrollPosition > contentHeight - threshold {
            viewModel?.handleLoadMore()
        }
    }
}
