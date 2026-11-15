import UIKit
import Combine

@MainActor
final class CCollectionView: App8BaseView<CollectionContent>, CViewProtocol {

    // MARK: - CViewProtocol

    weak var materialView: MaterialView?
    let contentView = UIView()

    // MARK: - UI

    private lazy var collectionView: App8CollectionView = {
        let cv = App8CollectionView(frame: .zero, collectionViewLayout: createLayout())
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
    /// The page this pager itself shows, as last observed from its offset (or
    /// set when it follows the variable). `nil` until the first report. The
    /// pager writes `currentPageVariable` only when this changes, never just
    /// because the variable holds another value: two pagers bound to one
    /// variable with different page counts would otherwise write their own
    /// pages back and forth.
    private var ownPageIndex: Int?
    /// Last offset seen by the page tracker. Compositional layout calls the
    /// visible-items handler on every layout pass; only a real offset change
    /// is a page report.
    private var lastPageTrackingOffset: CGPoint?
    /// Page requested by a write to `currentPageVariable` that could not be
    /// applied yet (no layout / width). Applied in `layoutSubviews`.
    private var pendingPageIndex: Int?
    /// True while an animated scroll started by a `currentPageVariable` write
    /// runs: its in-between pages are not written back. It expires after a
    /// second, so a pager never waits forever for an animation end that UIKit
    /// does not report, and a user drag takes over at once.
    private var isScrollingFromVariable = false
    private var variableScrollToken = 0
    private var isSelfSizing = false             // true when scrollEnabled == false
    private var selfSizingHeightConstraint: NSLayoutConstraint?
    private var cellsSelfSizeWidth = false       // true when horizontal + estimatedItemWidth
    /// Items whose cells measured a new size after the layout placed them;
    /// relaid out together on the next main-queue turn (`scheduleRemeasure`).
    private var pendingRemeasure: Set<IndexPath> = []
    /// Layout invalidations this collection asked for (tests: none per frame
    /// while scrolling over measured items).
    private(set) var layoutInvalidationCount = 0
    /// Natural heights of self-sizing grid items, by item identity (template,
    /// data, width; see `gridRowHeight`), not index path: a reused cell or a
    /// row scrolled back into view gets the height measured the first time.
    private var gridNaturalHeights: [String: CGFloat] = [:]
    /// `gridHeightKey` memo by index path, rebuilt when the sections change.
    private var gridHeightKeys: [IndexPath: String] = [:]
    /// Column width each section's cells last measured at; part of the
    /// height key, so a rotation or resize measures again.
    private var gridSectionWidths: [Int: CGFloat] = [:]
    /// A grid row's height became known after the layout was built: rebuild
    /// it (once per main-queue turn) so the row is placed at a fixed height.
    private var gridLayoutRebuildScheduled = false
    /// A cell's deferred remeasure ran while off-window; redo it on the next
    /// `didMoveToWindow` with a window.
    private var remeasureOnWindow = false
    /// Offsets of scrollables nested in this collection's cells (e.g. horizontal shelves
    /// in a vertical list), so they survive cell reuse.
    private var nestedScrollCache = NestedScrollOffsetCache()
    /// Token of the latest offset restore requested by the parent collection; the
    /// deferred re-apply runs only if it is still current. Cleared when the user drags.
    private var pendingRestoreToken: Int?
    private var restoreTokenCounter = 0

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
        renderSuperview = superview

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
        bindCurrentPageVariable()
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
            collectionView.backgroundColor = viewModel?.resolveColor(bgColorName)
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
        // Each section definition may name its own template.
        for definition in viewModel.component.properties.sectionDefinitions ?? [] {
            if let templateRef = definition.templateName {
                collectionView.register(CCollectionCell.self, forCellWithReuseIdentifier: templateRef)
            }
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
    
    /// True when an ancestor (through stacks and views) is a vertical DSL
    /// `scrollView`. Walks from the render superview, which is in place when
    /// `configure` runs.
    private var isInsideVerticalScrollView: Bool {
        var view = renderSuperview ?? superview
        while let current = view {
            if let scroll = current as? CScrollViewView {
                return scroll.scrollsVertically
            }
            if current is UICollectionView || current is UITableView { return false }
            view = current.superview
        }
        return false
    }

    /// `layout.height`, a `top` + `bottom` pair or a height constraint.
    private var hasOwnHeight: Bool {
        guard let layout = viewModel?.component.layout else { return false }
        if layout.height != nil { return true }
        if layout.top != nil && layout.bottom != nil { return true }
        let attributes = Set((layout.constraints ?? []).map(\.type))
        return attributes.contains(.height) || (attributes.contains(.top) && attributes.contains(.bottom))
    }

    /// The superview handed to `configure` (the view may not be added yet).
    private weak var renderSuperview: UIView?

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
        // collection view itself, so disable its main-axis scrolling — except a
        // full-width paged carousel, which scrolls the collection view natively.
        if isHorizontal {
            let nativePaging = usesNativeHorizontalPaging
            collectionView.alwaysBounceVertical = false
            collectionView.isScrollEnabled = nativePaging
            collectionView.isPagingEnabled = nativePaging
            // A pager scrolls sideways only; safe-area insets would shift its
            // full-height pages down (e.g. a gallery under the status bar).
            if nativePaging { collectionView.contentInsetAdjustmentBehavior = .never }
            // A vertical drag on a sideways pager belongs to what encloses it
            // (a zoom transition's interactive dismiss, an outer scroll view).
            collectionView.refusesVerticalPans = nativePaging
        } else {
            // A vertical / grid collection inside a vertical scroll view, with no
            // height of its own, lets the outer scroll view scroll: it sizes to
            // its content like `scrollEnabled: false`.
            let scrollEnabled = viewModel?.component.properties.layout?.scrollEnabled
                ?? !(isInsideVerticalScrollView && !hasOwnHeight)
            collectionView.isScrollEnabled = scrollEnabled
            collectionView.keepsTopRestOnInsetChange = scrollEnabled && viewModel?.component.properties.inverted != true
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
            if let color = viewModel?.swipeActionColor(at: indexPath, swipe.backgroundColor) {
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

    /// A top-level horizontal collection of full-width pages (`pagingStyle:
    /// paging`, no item width): a photo-gallery pager. It scrolls the collection
    /// view itself with `isPagingEnabled`, like UIKit's own pagers, instead of
    /// an orthogonal section — whose private scroll view rounds any offset set
    /// from outside its own pan to a page and loads cells only for that page,
    /// so a host-driven drag (Mac pointer drag, programmatic scroll) broke.
    private var usesNativeHorizontalPaging: Bool {
        guard let config = viewModel?.component.properties.layout, config.type == .horizontal else { return false }
        return config.pagingStyle == .paging
            && config.itemWidth == nil
            && config.estimatedItemWidth == nil
            && (config.rows ?? 1) <= 1
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
        let nativePaging = usesNativeHorizontalPaging
        section.orthogonalScrollingBehavior = nativePaging ? .none : orthogonalBehavior(for: config)
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

        if config.currentPageVariable != nil, !nativePaging {
            section.visibleItemsInvalidationHandler = { [weak self] items, offset, environment in
                self?.handlePageChange(offset: offset, containerWidth: environment.container.effectiveContentSize.width)
            }
        }

        if !nativePaging, config.itemHeightFill {
            // `itemHeight: "fill"`: items as tall as the collection's frame minus
            // vertical insets, re-measured when the collection resizes.
            let spacing = section.interGroupSpacing
            let insets = section.contentInsets
            let behavior = section.orthogonalScrollingBehavior
            let handler = section.visibleItemsInvalidationHandler
            let topInset = config.contentInsets?.top ?? 0
            return UICollectionViewCompositionalLayout { _, environment in
                let available = environment.container.contentSize.height - topInset - insets.bottom
                let height = max(1, available)
                let size = NSCollectionLayoutSize(widthDimension: widthDimension, heightDimension: .absolute(height))
                let fillItem = NSCollectionLayoutItem(layoutSize: size)
                let fillGroup = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [fillItem])
                let fillSection = NSCollectionLayoutSection(group: fillGroup)
                fillSection.orthogonalScrollingBehavior = behavior
                fillSection.interGroupSpacing = spacing
                fillSection.contentInsets = insets
                fillSection.visibleItemsInvalidationHandler = handler
                return fillSection
            }
        }

        guard nativePaging else { return UICollectionViewCompositionalLayout(section: section) }
        let layoutConfig = UICollectionViewCompositionalLayoutConfiguration()
        layoutConfig.scrollDirection = .horizontal
        // Pages fill the collection's bounds, not its safe area.
        layoutConfig.contentInsetsReference = .none
        section.contentInsetsReference = .none
        // Pages are as tall as the collection (`itemHeight` until measured), re-laid
        // out when its height changes — e.g. a gallery in a stretchy header.
        let spacing = section.interGroupSpacing
        let sectionInsets = section.contentInsets
        return UICollectionViewCompositionalLayout(sectionProvider: { _, environment in
            let containerHeight = environment.container.contentSize.height
            let height = containerHeight > 0 ? max(1, containerHeight - sectionInsets.bottom) : itemHeight
            let size = NSCollectionLayoutSize(widthDimension: widthDimension, heightDimension: .absolute(height))
            let pageItem = NSCollectionLayoutItem(layoutSize: size)
            let pageGroup = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [pageItem])
            let pageSection = NSCollectionLayoutSection(group: pageGroup)
            pageSection.interGroupSpacing = spacing
            pageSection.contentInsets = sectionInsets
            pageSection.contentInsetsReference = .none
            return pageSection
        }, configuration: layoutConfig)
    }

    // MARK: - currentPageVariable (two-way)

    /// A write to `currentPageVariable` from elsewhere scrolls to that page:
    /// animated while visible, without animation while off screen.
    private func bindCurrentPageVariable() {
        guard let viewModel,
              let config = viewModel.component.properties.layout,
              config.type == .horizontal,
              let varName = config.currentPageVariable else { return }
        if let initial = Self.pageIndex(viewModel.variableStore.getValue(name: varName)), initial > 0 {
            pendingPageIndex = initial
        }
        viewModel.variableStore.anyVariableChanged
            .filter { $0 == varName }
            .compactMap { [weak viewModel] _ in Self.pageIndex(viewModel?.variableStore.getValue(name: varName)) }
            .sink { [weak self] page in
                // Already there (or this pager's own write coming back).
                guard let self, page != self.ownPageIndex else { return }
                self.pendingPageIndex = page
                self.applyPendingPage(animated: self.window != nil)
            }
            .store(in: &cancellables)
    }

    private static func pageIndex(_ value: Any?) -> Int? {
        switch value {
        case let i as Int: return i
        case let d as Double where d.isFinite: return Int(d.rounded())
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }

    private func applyPendingPage(animated: Bool) {
        guard let page = pendingPageIndex,
              collectionView.bounds.width > 0,
              collectionView.numberOfSections > 0 else { return }
        let count = collectionView.numberOfItems(inSection: 0)
        guard count > 0 else { return }
        // A pager with fewer pages than the variable asks for goes to its last
        // page and stays quiet: the page it shows is a follow, not a change of
        // its own, so it is not written back.
        let clamped = max(0, min(page, count - 1))
        pendingPageIndex = nil
        let alreadyThere = ownPageIndex == clamped
        ownPageIndex = clamped
        guard !alreadyThere else { return }
        if animated {
            isScrollingFromVariable = true
            variableScrollToken += 1
            let token = variableScrollToken
            // Orthogonal sections report no scroll-animation end; time it out.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.variableScrollToken == token else { return }
                self.isScrollingFromVariable = false
            }
        }
        if usesNativeHorizontalPaging {
            let width = collectionView.bounds.width
            var x = CGFloat(clamped) * width
            // Never past the content's end, so the scroll can finish.
            let maxX = collectionView.contentSize.width - width
            if maxX >= 0 { x = min(x, maxX) }
            collectionView.setContentOffset(CGPoint(x: max(0, x), y: collectionView.contentOffset.y), animated: animated)
        } else {
            collectionView.layoutIfNeeded()
            collectionView.scrollToItem(at: IndexPath(item: clamped, section: 0), at: .centeredHorizontally, animated: animated)
        }
    }

    /// Self-sizing (`scrollEnabled: false`): the height follows the content
    /// size whenever it changes — new data, a variable change, a width change
    /// (e.g. a grid that was laid out while hidden).
    private var contentSizeObservation: NSKeyValueObservation?

    private func observeContentSizeIfNeeded() {
        guard contentSizeObservation == nil else { return }
        contentSizeObservation = collectionView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.syncSelfSizingHeight() }
        }
    }

    private func syncSelfSizingHeight() {
        guard isSelfSizing, let constraint = selfSizingHeightConstraint else { return }
        let actual = collectionView.contentSize.height + collectionView.contentInset.top + collectionView.contentInset.bottom
        guard actual > 0, abs(actual - constraint.constant) > 0.5 else { return }
        constraint.constant = actual
        superview?.setNeedsLayout()
        remeasureEnclosingCell()
    }

    /// A self-sizing collection inside a collection or table cell: the cell
    /// was measured before this height was known, so ask the enclosing list
    /// to measure its cells again (the cell grows with the content).
    private func remeasureEnclosingCell() {
        var view = superview
        var inCell = false
        var cell: UICollectionViewCell?
        while let current = view {
            if current is UICollectionViewCell || current is UITableViewCell { inCell = true }
            if cell == nil, let found = current as? UICollectionViewCell { cell = found }
            if inCell, let outer = current as? CCollectionView {
                if let cell { outer.remeasure(cell) }
                return
            }
            if inCell, let table = current as? UITableView {
                DispatchQueue.main.async { [weak table] in
                    UIView.performWithoutAnimation { table?.performBatchUpdates(nil) }
                }
                return
            }
            view = current.superview
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, remeasureOnWindow else { return }
        remeasureOnWindow = false
        // Only the cells on screen measured before their text bound.
        scheduleRemeasure(collectionView.indexPathsForVisibleItems)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if isSelfSizing {
            observeContentSizeIfNeeded()
        }
        if pendingPageIndex != nil {
            collectionView.layoutIfNeeded()
            applyPendingPage(animated: false)
        }
        recordRestingPageIfNeeded()
    }

    /// Once the pager has pages and a width, the page it rests on is its own
    /// page, so the first scroll the user makes is a change from there.
    private func recordRestingPageIfNeeded() {
        guard ownPageIndex == nil, pendingPageIndex == nil,
              viewModel?.component.properties.layout?.currentPageVariable != nil,
              collectionView.bounds.width > 0,
              collectionView.numberOfSections > 0,
              collectionView.numberOfItems(inSection: 0) > 0 else { return }
        ownPageIndex = Int((collectionView.contentOffset.x / collectionView.bounds.width).rounded())
    }

    /// Handles page change detection for horizontal paging collections
    private func handlePageChange(offset: CGPoint, containerWidth: CGFloat) {
        guard let config = viewModel?.component.properties.layout,
              let varName = config.currentPageVariable,
              containerWidth > 0 else { return }

        guard offset.x.isFinite, offset != lastPageTrackingOffset else { return }
        lastPageTrackingOffset = offset
        guard !isScrollingFromVariable else { return }
        let currentPage = Int((offset.x / containerWidth).rounded())
        // The first report only records where the pager is.
        guard let previous = ownPageIndex else {
            ownPageIndex = currentPage
            return
        }
        guard currentPage != previous else { return }
        ownPageIndex = currentPage
        guard let store = viewModel?.variableStore,
              Self.pageIndex(store.getValue(name: varName)) != currentPage else { return }
        try? store.setValue(name: varName, value: currentPage)
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
        if columns > 1, config.aspectRatio == nil, config.itemHeight == nil {
            // Self-sizing grid rows: rebuilt from the measured heights on every pass.
            return UICollectionViewCompositionalLayout { [weak self] sectionIndex, _ in
                let section = self?.selfSizingGridSection(config: config, sectionIndex: sectionIndex)
                    ?? NSCollectionLayoutSection(group: .vertical(
                        layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44)),
                        subitems: [.init(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44)))]))
                if let insets = config.contentInsets {
                    section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: insets.left ?? 0, bottom: insets.bottom ?? 0, trailing: insets.right ?? 0)
                }
                return section
            }
        }

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

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: itemSize.heightDimension
        )
        // `count` sizes the items to fill the row with the spacing BETWEEN them
        // only, so the outer columns sit flush with the collection's edges
        // (per-item half-spacing insets left them inset by itemSpacing / 2).
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, repeatingSubitem: item, count: columns)
        group.interItemSpacing = .fixed(config.itemSpacing ?? 0)

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
                section = self.buildGridSection(config: effectiveLayout!, sectionIndex: sectionIndex)
                gridOuterSpacing = (effectiveLayout?.itemSpacing ?? 0) / 2
            default:
                if effectiveLayout?.itemHeight == nil,
                   let rows = self.selfSizingRowsSection(
                       columns: 1,
                       estimated: effectiveLayout?.estimatedItemHeight ?? 44,
                       interItemSpacing: 0,
                       lineSpacing: effectiveLayout?.itemSpacing ?? 0,
                       sectionIndex: sectionIndex
                   ) {
                    section = rows
                } else {
                    section = self.buildVerticalSection(config: effectiveLayout)
                }
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
        config: DSL.Model.Component.Collection.Layout,
        sectionIndex: Int
    ) -> NSCollectionLayoutSection {
        let columns = config.columns ?? 2
        if columns > 1, config.aspectRatio == nil, config.itemHeight == nil,
           let section = selfSizingGridSection(config: config, sectionIndex: sectionIndex) {
            return section
        }

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

    /// A self-sizing grid section (collections.md, "Self-sizing grid rows")
    /// as one vertical group of rows: a row whose items have all been
    /// measured has a fixed (`.absolute`) height, the rest `.estimated`.
    ///
    /// The compositional layout does not keep the heights cells self-size
    /// to: an item scrolled out of view drops back to `estimatedItemHeight`
    /// whenever the layout is invalidated. Every row scrolled back into view
    /// then resized above the viewport, UIKit shifted the offset to
    /// compensate (content moving faster than the finger, a jump after
    /// deceleration) and the content size changed while bouncing at the end.
    /// Rows built from the engine's own height cache never move.
    private func selfSizingGridSection(
        config: DSL.Model.Component.Collection.Layout,
        sectionIndex: Int
    ) -> NSCollectionLayoutSection? {
        selfSizingRowsSection(
            columns: config.columns ?? 2,
            estimated: config.estimatedItemHeight ?? 100,
            interItemSpacing: config.itemSpacing ?? 0,
            lineSpacing: config.lineSpacing ?? 0,
            sectionIndex: sectionIndex
        )
    }

    /// Rows of `columns` items (a vertical section: rows of one), each row
    /// `.absolute` once all its items have a cached natural height.
    private func selfSizingRowsSection(
        columns: Int,
        estimated: CGFloat,
        interItemSpacing: CGFloat,
        lineSpacing: CGFloat,
        sectionIndex: Int
    ) -> NSCollectionLayoutSection? {
        let count = sections[safe: sectionIndex]?.items.count ?? 0
        guard count > 0 else { return nil }
        let rows = (count + columns - 1) / columns
        var rowGroups: [NSCollectionLayoutItem] = []
        var total: CGFloat = 0
        rowGroups.reserveCapacity(rows)
        for row in 0..<rows {
            let known = knownGridRowHeight(section: sectionIndex, row: row, columns: columns, count: count)
            let dimension: NSCollectionLayoutDimension = known.map { .absolute($0) } ?? .estimated(estimated)
            total += known ?? estimated
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1.0 / CGFloat(columns)), heightDimension: dimension))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: dimension),
                repeatingSubitem: item,
                count: columns
            )
            group.interItemSpacing = .fixed(interItemSpacing)
            rowGroups.append(group)
        }
        total += CGFloat(max(0, rows - 1)) * lineSpacing
        let column = NSCollectionLayoutGroup.vertical(
            layoutSize: .init(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(total)),
            subitems: rowGroups
        )
        column.interItemSpacing = .fixed(lineSpacing)
        let section = NSCollectionLayoutSection(group: column)
        section.interGroupSpacing = lineSpacing
        return section
    }

    /// The row's height when every item in it has a cached natural height.
    private func knownGridRowHeight(section: Int, row: Int, columns: Int, count: Int) -> CGFloat? {
        var height: CGFloat = 0
        for item in (row * columns)..<min(row * columns + columns, count) {
            guard let key = gridHeightKey(at: IndexPath(item: item, section: section)),
                  let natural = gridNaturalHeights[key] else { return nil }
            height = max(height, natural)
        }
        return height
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
                // Different items → saved nested offsets no longer belong to them.
                if Self.itemScrollKeys(self.sections) != Self.itemScrollKeys(newSections) {
                    self.nestedScrollCache.reset()
                }
                self.gridHeightKeys.removeAll()
                // Heights are keyed by item content: they stay valid across
                // emissions. Only drop entries no item can use anymore.
                if self.gridNaturalHeights.count > 4 * max(64, newSections.reduce(0) { $0 + $1.items.count }) {
                    self.gridNaturalHeights.removeAll()
                }
                guard !self.sectionsStructurallyEqual(self.sections, newSections) else {
                    // Same shape, new item data (e.g. a cart line's quantity):
                    // push it into the live cells instead of a full reload.
                    self.sections = newSections
                    self.refreshVisibleItemData()
                    return
                }
                let oldSections = self.sections
                self.sections = newSections

                // Self-sizing: set estimated height before reloadData so the collection view
                // gets a non-zero frame on the first layout pass (needed to compute contentSize).
                if self.isSelfSizing {
                    let layoutConfig = self.viewModel?.component.properties.layout
                    let itemCount = newSections.reduce(0) { $0 + $1.items.count }
                    let estimatedItemHeight: CGFloat = layoutConfig?.itemHeight ?? layoutConfig?.estimatedItemHeight ?? 44
                    let isGrid = layoutConfig?.type == .grid
                    // A grid stacks rows of `columns` items, separated by `lineSpacing`.
                    let rows = isGrid ? Int(ceil(Double(itemCount) / Double(max(1, layoutConfig?.columns ?? 2)))) : itemCount
                    let spacing: CGFloat = isGrid ? (layoutConfig?.lineSpacing ?? 0) : (layoutConfig?.itemSpacing ?? 0)
                    let insetsHeight: CGFloat = (layoutConfig?.contentInsets?.top ?? 0) + (layoutConfig?.contentInsets?.bottom ?? 0)
                    let itemsHeight: CGFloat = CGFloat(rows) * estimatedItemHeight
                    let gapsHeight: CGFloat = CGFloat(max(0, rows - 1)) * spacing
                    let estimatedHeight: CGFloat = itemsHeight + gapsHeight + insetsHeight
                    self.selfSizingHeightConstraint?.constant = estimatedHeight
                    self.superview?.setNeedsLayout()
                    self.remeasureEnclosingCell()
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

                // Fewer items: keep the offset inside the shorter content.
                let oldCount = oldSections.reduce(0) { $0 + $1.items.count }
                let newCount = newSections.reduce(0) { $0 + $1.items.count }
                if newCount < oldCount, self.collectionView.window != nil {
                    self.collectionView.layoutIfNeeded()
                    self.collectionView.clampOffsetToContent()
                }

                // A page requested before the items arrived (gallery opened at page N).
                if self.pendingPageIndex != nil {
                    DispatchQueue.main.async { [weak self] in
                        self?.collectionView.layoutIfNeeded()
                        self?.applyPendingPage(animated: false)
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in self?.recordRestingPageIfNeeded() }
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
                        self?.collectionView.layoutIfNeeded()
                        self?.syncSelfSizingHeight()
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

    /// Stable identity of an item for nested-scroll memory: section key + the item's `id`
    /// when it has one, else its index path.
    static func itemScrollKey(_ item: CCollectionViewModel.ItemWrapper, sectionKey: String, indexPath: IndexPath) -> String {
        if let dict = item.data.value as? [String: Any], let id = dict["id"] {
            return sectionKey + "/id:" + String(describing: id)
        }
        return sectionKey + "/#\(indexPath.section).\(indexPath.item)"
    }

    static func itemScrollKeys(_ sections: [CCollectionViewModel.Section]) -> [String] {
        sections.enumerated().flatMap { sIdx, section in
            section.items.enumerated().map { iIdx, item in
                itemScrollKey(item, sectionKey: section.key, indexPath: IndexPath(item: iIdx, section: sIdx))
            }
        }
    }

    /// Restore the offsets of scrollables nested in `cell` for the item it now shows.
    private func restoreNestedScrollState(in cell: CCollectionCell, itemKey: String) {
        cell.scrollStateItemKey = itemKey
        cell.scrollStateGeneration = nestedScrollCache.generation
        for nested in NestedScrollOffsetCache.restorables(in: cell.contentView) {
            guard let nestedId = nested.nestedScrollStateId else { continue }
            nested.restoreNestedScrollOffset(nestedScrollCache.offset(itemKey: itemKey, nestedId: nestedId))
        }
    }

    /// Capture the offsets of scrollables nested in `cell` before it is reused.
    private func saveNestedScrollState(from cell: CCollectionCell) {
        guard let itemKey = cell.scrollStateItemKey else { return }
        for nested in NestedScrollOffsetCache.restorables(in: cell.contentView) {
            guard let nestedId = nested.nestedScrollStateId,
                  let offset = nested.nestedScrollOffset else { continue }
            nestedScrollCache.save(offset, itemKey: itemKey, nestedId: nestedId, generation: cell.scrollStateGeneration)
        }
    }

    /// The surface that actually scrolls: a horizontal shelf scrolls inside the
    /// compositional layout's orthogonal section scroller, not the collection view.
    private var primaryScrollView: UIScrollView? {
        let isHorizontal = viewModel?.component.properties.layout?.type == .horizontal
        guard isHorizontal, !usesNativeHorizontalPaging else { return collectionView }
        // UIKit embeds one scroll view per orthogonal section as a direct subview.
        return collectionView.subviews.lazy.compactMap { $0 as? UIScrollView }.first
    }

    private func applyRestoredOffset(_ offset: CGPoint?) {
        guard let scrollView = primaryScrollView else { return }
        scrollView.app8SetClampedContentOffset(offset ?? scrollView.app8RestOffset)
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

    /// Re-binds `item` in every visible cell to its current data. Off-screen
    /// cached cells pick theirs up on reuse (`cellForItemAt`).
    private func refreshVisibleItemData() {
        guard let viewModel else { return }
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let item = sections[safe: indexPath.section]?.items[safe: indexPath.item],
                  let cellVM = viewModel.getCachedViewModel(section: indexPath.section, item: indexPath.item) else { continue }
            viewModel.updateItemVariable(in: cellVM, with: item)
        }
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
        cell.gridRowHeight = selfSizingGridColumns(inSection: indexPath.section) != nil
            ? { [weak self] indexPath, natural, width in self?.gridRowHeight(at: indexPath, natural: natural, width: width) ?? natural }
            : nil

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

        // Bound text / visibility normally lands a main-queue hop later, after
        // UIKit measured the cell: apply it now, so the first measure is final.
        cell.applyBoundValuesNow()

        if viewModel.component.properties.inverted == true {
            cell.contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
        }

        restoreNestedScrollState(
            in: cell,
            itemKey: Self.itemScrollKey(item, sectionKey: sections[indexPath.section].key, indexPath: indexPath)
        )

        // Text and isHidden bind on a later main-queue hop, after UIKit has
        // measured the cell: measure again then, and relayout if it changed.
        DispatchQueue.main.async { [weak self, weak cell] in
            guard let self, let cell else { return }
            // Off-window (a tab not selected yet, a screen rendered before it
            // is shown): measure once the collection is on a window again,
            // else the cell keeps the size it had before its text bound.
            guard cell.window != nil else {
                self.remeasureOnWindow = true
                return
            }
            guard cell.needsRemeasure() else { return }
            self.remeasure(cell)
        }

        return cell
    }

    // MARK: - Self-sizing grid rows

    /// Columns of a self-sizing grid section (a `grid` layout without
    /// `itemHeight` or `aspectRatio`, more than one column); nil otherwise.
    private func selfSizingGridColumns(inSection section: Int) -> Int? {
        guard let props = viewModel?.component.properties else { return nil }
        let config: DSL.Model.Component.Collection.Layout?
        switch props.layout?.type {
        case .grid:
            config = props.layout
        case .vertical, .none:
            // createMixedSectionsLayout: sectionLayouts[key] → defaultSectionLayout.
            let key = sections[safe: section]?.key
            config = key.flatMap { props.sectionLayouts?[$0] } ?? props.defaultSectionLayout
        case .horizontal:
            config = nil
        }
        if props.layout?.type == nil || props.layout?.type == .vertical, usesMixedSectionsLayout,
           config?.type == nil || config?.type == .vertical, config?.itemHeightValue == nil {
            // A self-sizing vertical section of a mixed layout: rows of one.
            return 1
        }
        guard let config, config.type == .grid, config.itemHeightValue == nil, config.aspectRatio == nil else { return nil }
        let columns = config.columns ?? 2
        return columns > 1 ? columns : nil
    }

    /// `createVerticalListLayout` builds one section per data section.
    private var usesMixedSectionsLayout: Bool {
        guard let viewModel else { return false }
        return viewModel.component.properties.defaultSectionLayout != nil
            || viewModel.component.properties.sectionLayouts != nil
            || viewModel.component.sectionHeaders != nil
    }

    /// The height of the grid row holding `indexPath`: the tallest natural
    /// height among its items (collections.md, "Self-sizing grid rows").
    ///
    /// The row's other items are measured right here (cached, else with an
    /// off-screen sizing cell), so the row is final on its first layout pass.
    /// The compositional layout forgets the self-sized heights of off-screen
    /// items whenever its layout is invalidated wholesale and falls back to
    /// `estimatedItemHeight`; relaying out each new row used to do exactly
    /// that, so every row scrolled back into view resized above the viewport
    /// and UIKit moved the offset under the finger. Only a height that
    /// changes after its first measure (the item's content changed) relays
    /// out, and only that row's items.
    private func gridRowHeight(at indexPath: IndexPath, natural: CGFloat, width: CGFloat) -> CGFloat {
        guard let columns = selfSizingGridColumns(inSection: indexPath.section) else { return natural }
        // Heights hold for one column width (a rotation or resize remeasures).
        gridSectionWidths[indexPath.section] = width
        guard let key = gridHeightKey(at: indexPath) else { return natural }
        let count = sections[safe: indexPath.section]?.items.count ?? 0
        let row = indexPath.item / columns
        let wasKnown = knownGridRowHeight(section: indexPath.section, row: row, columns: columns, count: count)
        gridNaturalHeights[key] = natural
        var rowHeight = natural
        for item in (row * columns)..<min(row * columns + columns, count) where item != indexPath.item {
            if let siblingKey = gridHeightKey(at: IndexPath(item: item, section: indexPath.section)),
               let height = gridNaturalHeights[siblingKey] {
                rowHeight = max(rowHeight, height)
            }
        }
        // The row's items come into view together. Once all of them have
        // measured (or the content changed), place the row at its fixed
        // height. A row already placed at this height needs nothing.
        let isKnown = knownGridRowHeight(section: indexPath.section, row: row, columns: columns, count: count)
        if let isKnown, wasKnown.map({ abs($0 - isKnown) > 0.5 }) ?? true {
            scheduleGridLayoutRebuild()
        }
        return rowHeight
    }

    /// One wholesale relayout per main-queue turn. Harmless to the rows
    /// already measured: they come back at their cached heights.
    private func scheduleGridLayoutRebuild() {
        guard !gridLayoutRebuildScheduled else { return }
        gridLayoutRebuildScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.gridLayoutRebuildScheduled = false
            self.layoutInvalidationCount += 1
            self.collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    /// Identity of the item at `indexPath` for the height cache: section,
    /// template, the item's data and the column width.
    private func gridHeightKey(at indexPath: IndexPath) -> String? {
        guard let width = gridSectionWidths[indexPath.section] else { return nil }
        let base: String
        if let memo = gridHeightKeys[indexPath] {
            base = memo
        } else {
            guard let section = sections[safe: indexPath.section],
                  let item = section.items[safe: indexPath.item] else { return nil }
            let template = viewModel?.resolveTemplate(for: item)?.id ?? ""
            base = section.key + "|" + template + "|" + Self.contentFingerprint(item.data)
            gridHeightKeys[indexPath] = base
        }
        return base + "|" + String(Int((width * 2).rounded()))
    }


    /// The item's data, order-independent (dictionary order is not stable).
    private static func contentFingerprint(_ value: AnyCodableValue) -> String {
        if JSONSerialization.isValidJSONObject(value.value),
           let data = try? JSONSerialization.data(withJSONObject: value.value, options: [.sortedKeys, .fragmentsAllowed]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value.value)
    }

    /// `cell`'s content changed size after it was laid out: measure it again.
    /// Self-sizing rows are placed from the height cache, so update the cache
    /// (which relays out that row); other cells relayout on their own.
    func remeasure(_ cell: UICollectionViewCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        if let cell = cell as? CCollectionCell, selfSizingGridColumns(inSection: indexPath.section) != nil {
            let width = cell.bounds.width
            _ = gridRowHeight(at: indexPath, natural: cell.measureNaturalHeight(width: width), width: width)
        } else {
            scheduleRemeasure([indexPath])
        }
    }

    /// Relayout `indexPaths` on the next main-queue turn, together, without
    /// invalidating the rest of the layout (a wholesale invalidation drops
    /// every off-screen self-sized height back to the estimate).
    func scheduleRemeasure(_ indexPaths: [IndexPath]) {
        guard !indexPaths.isEmpty else { return }
        let wasEmpty = pendingRemeasure.isEmpty
        pendingRemeasure.formUnion(indexPaths)
        guard wasEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let counts = (0..<self.collectionView.numberOfSections).map { self.collectionView.numberOfItems(inSection: $0) }
            let valid = self.pendingRemeasure.filter { $0.section < counts.count && $0.item < counts[$0.section] }
            self.pendingRemeasure.removeAll()
            guard !valid.isEmpty else { return }
            self.layoutInvalidationCount += 1
            let context = UICollectionViewLayoutInvalidationContext()
            context.invalidateItems(at: Array(valid))
            self.collectionView.collectionViewLayout.invalidateLayout(with: context)
        }
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

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard let cell = cell as? CCollectionCell else { return }
        saveNestedScrollState(from: cell)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isScrollingFromVariable = false
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // The user took over from a variable-driven scroll.
        isScrollingFromVariable = false
        // The user took over; don't snap back to a restored offset.
        pendingRestoreToken = nil
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Native pager: the page index comes from the collection view's own offset.
        if usesNativeHorizontalPaging {
            handlePageChange(offset: scrollView.contentOffset, containerWidth: scrollView.bounds.width)
        }
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

// MARK: - NestedScrollStateRestorable

extension CCollectionView: NestedScrollStateRestorable {

    var nestedScrollStateId: String? { layoutModeId }

    var nestedScrollOffset: CGPoint? { primaryScrollView?.contentOffset }

    func restoreNestedScrollOffset(_ offset: CGPoint?) {
        // Apply now (same-shape data: the layout is already valid), then once more
        // after the reparent-triggered sections delivery, which `bindSections`
        // receives on a later main-queue turn and may reload / resize the content.
        restoreTokenCounter += 1
        let token = restoreTokenCounter
        pendingRestoreToken = token
        applyRestoredOffset(offset)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pendingRestoreToken == token else { return }
            self.pendingRestoreToken = nil
            self.collectionView.layoutIfNeeded()
            self.applyRestoredOffset(offset)
        }
    }
}

// MARK: - App8CollectionView

/// A collection view that, as a horizontal pager, does not begin its pan for a
/// mostly vertical drag, so an enclosing gesture (zoom dismiss) can take it.
final class App8CollectionView: UICollectionView {
    var refusesVerticalPans = false

    /// A vertical list that should stay at its top rest position when its
    /// adjusted inset changes while nobody scrolled it: a tab's screen is laid
    /// out off-window (no safe area, offset 0) or with its navigation bar still
    /// hidden, and only then gets the status bar + bar (+ large title) inset.
    /// UIKit keeps the old offset, so the first ~100pt (the screen's header)
    /// sat under the bar until the user nudged the list.
    var keepsTopRestOnInsetChange = false
    /// Adjusted top inset, and its safe-area part, last seen.
    private var lastAdjustedTop: CGFloat = 0
    private var lastSystemTop: CGFloat = 0

    override func adjustedContentInsetDidChange() {
        super.adjustedContentInsetDidChange()
        let newTop = adjustedContentInset.top
        // Only a safe-area change (bars, status bar): a DSL `contentInsets.top`
        // change keeps the offset it always had.
        let systemTop = newTop - contentInset.top
        defer { lastAdjustedTop = newTop; lastSystemTop = systemTop }
        guard keepsTopRestOnInsetChange, abs(systemTop - lastSystemTop) > 0.5,
              !isTracking, !isDragging, !isDecelerating,
              abs(contentOffset.y + lastAdjustedTop) < 0.5 else { return }
        contentOffset.y = -newTop
    }

    /// Bring the offset back inside the content after it shrank (items
    /// removed while scrolled down): otherwise the list shows an empty
    /// stretch past its end, or nothing at all, until the user scrolls.
    func clampOffsetToContent() {
        guard keepsTopRestOnInsetChange, !isTracking, !isDragging, !isDecelerating else { return }
        let inset = adjustedContentInset
        let maxY = max(-inset.top, contentSize.height + inset.bottom - bounds.height)
        if contentOffset.y > maxY + 0.5 {
            contentOffset.y = maxY
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if refusesVerticalPans, gestureRecognizer === panGestureRecognizer {
            let v = panGestureRecognizer.velocity(in: self)
            if contentSize.height <= bounds.height + 1, abs(v.y) > abs(v.x) { return false }
            // A pan from the leading screen edge is the back / dismiss gesture,
            // even over a pager (spec: native zoom, leading-edge swipe).
            if v.x > 0, let window, isLeadingEdgeTouch(in: window), screenCanGoBack { return false }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    static let edgeWidth: CGFloat = 20

    private func isLeadingEdgeTouch(in window: UIWindow) -> Bool {
        let x = panGestureRecognizer.location(in: window).x
        let start = x - panGestureRecognizer.translation(in: window).x
        if effectiveUserInterfaceLayoutDirection == .rightToLeft {
            return start > window.bounds.width - Self.edgeWidth
        }
        return start < Self.edgeWidth
    }

    /// Whether the screen showing this view can be popped or dismissed.
    private var screenCanGoBack: Bool {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController {
                if let nav = vc.navigationController, nav.viewControllers.count > 1, nav.topViewController === vc { return true }
                if vc.presentingViewController != nil { return true }
            }
            responder = r.next
        }
        return false
    }
}
