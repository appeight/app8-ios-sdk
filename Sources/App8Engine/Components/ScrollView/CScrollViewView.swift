//
//  CScrollViewView.swift
//  App8Engine
//

import UIKit
import Combine

class CScrollViewView: App8BaseView<DSL.Model.Component.ScrollView.C>, CViewProtocol {

    private var viewModel: CScrollViewViewModel?
    weak var materialView: MaterialView?
    /// contentView is used by CViewProtocol for corner masking - contains scrollView
    let contentView = UIView()
    private let scrollView = UIScrollView()
    /// scrollContentView is the actual container for scroll content children
    private let scrollContentView = UIView()

    // nonisolated(unsafe): a slight race in scroll-update throttling is harmless.
    nonisolated(unsafe) private static var lastUpdateTime: [ObjectIdentifier: CFTimeInterval] = [:]
    private static let updateInterval: CFTimeInterval = 0.016

    /// Last known state for the scroll threshold. Initialized to false (below threshold)
    /// so the first scroll event doesn't spuriously fire .onScrollThreshold with $crossed=false.
    /// Fires only when crossing (state changes).
    private var lastScrollThresholdCrossed: Bool = false

    private var focusCancellable: AnyCancellable?
    private var keyboardCancellable: AnyCancellable?

    // MARK: - Auto-scroll (marquee)

    private var autoScrollDisplayLink: CADisplayLink?
    /// Timestamp of the previous tick — used for deltaTime so motion is
    /// independent of refresh rate (60 / 90 / 120 Hz).
    private var autoScrollLastTimestamp: CFTimeInterval?
    /// Length of the original (un-duplicated) content along the scroll axis;
    /// the offset wraps modulo this value when `infinite` is true.
    private var autoScrollOriginalLength: CGFloat = 0
    private var autoScrollSnapshot: UIView?
    /// Whether marquee setup has run for the current configuration; resets on `configureContent`.
    private var autoScrollDidInstall: Bool = false
    private var marqueeContainer: UIView?
    /// Trailing/bottom constraint pinning the marquee container to scrollContentView.
    /// Deactivated when the snapshot is installed so the snapshot can take over the trailing edge.
    private var marqueeContainerEndConstraint: NSLayoutConstraint?

    deinit {
        Self.lastUpdateTime.removeValue(forKey: ObjectIdentifier(self))
        // The auto-scroll CADisplayLink isn't invalidated here: it retains self,
        // so deinit can only run after the link was already invalidated (via
        // willMove(toWindow: nil)). Touching it from a nonisolated deinit would
        // also break Swift 6 strict concurrency since CADisplayLink isn't Sendable.
    }

    override func setup() {
        super.setup()
        // Views added in applyStyle to ensure correct z-order after materialView.
    }

    private var isViewHierarchySetup = false

    private func setupViewHierarchyIfNeeded() {
        guard !isViewHierarchySetup else { return }
        isViewHierarchySetup = true

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()

        contentView.addSubview(scrollView)
        scrollView.cMakeEqualToSuperview()
        scrollView.clipsToBounds = true
        scrollView.contentInsetAdjustmentBehavior = .automatic  // overridden per-configure
        scrollView.delegate = self

        scrollView.addSubview(scrollContentView)
    }

    func configure(viewModel: CScrollViewViewModel, superview: UIView? = nil, animated: Bool = true) {
        self.viewModel = viewModel
        guard let superview = superview ?? self.superview else {
            return
        }
        bindLayout(viewModel.layout, in: superview, viewRegistry: viewModel.service.componentRegistry.viewRegistry, parentComponentPath: viewModel.parentPath, keyboardService: viewModel.service.context.keyboardService, animated: animated)
        bindStyle(viewModel.style, animation: viewModel.animation)
        configureContent(viewModel: viewModel, animated: animated)
        setupAutoScrollToFocus()
    }

    // MARK: - Auto-scroll to Focused Input

    private func setupAutoScrollToFocus() {
        guard let focusManager = viewModel?.service.context.focusManager else { return }
        focusCancellable = focusManager.focusChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] focusedId in
                guard let self, let focusedId else { return }
                self.scrollToFocusedView(id: focusedId)
            }
    }

    private func scrollToFocusedView(id: String) {
        guard let viewModel else { return }

        guard let focusedView = viewModel.service.componentRegistry.viewRegistry.view(forId: id),
              focusedView.isDescendant(of: scrollContentView) else {
            return
        }

        let keyboardHeight = viewModel.service.context.keyboardService.currentHeight
        let frameInScrollView = focusedView.convert(focusedView.bounds, to: scrollView)

        let visibleHeight = scrollView.bounds.height - keyboardHeight
        let visibleRect = CGRect(
            x: scrollView.contentOffset.x,
            y: scrollView.contentOffset.y,
            width: scrollView.bounds.width,
            height: visibleHeight
        )

        if visibleRect.contains(frameInScrollView) {
            return
        }

        let padding: CGFloat = 20
        var targetRect = frameInScrollView
        targetRect.size.height += padding

        // Delay lets the keyboard animation start before scrolling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.scrollView.scrollRectToVisible(targetRect, animated: true)
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
        // Set up view hierarchy after materialView is inserted.
        setupViewHierarchyIfNeeded()
    }

    private func configureContent(viewModel: CScrollViewViewModel, animated: Bool = false) {
        setupViewHierarchyIfNeeded()

        scrollContentView.subviews.forEach {
            $0.rfs(animatables: { $0?.alpha = .zero }, animated: animated)
        }

        scrollContentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.deactivate(scrollContentView.constraints.filter { $0.firstItem === scrollContentView || $0.secondItem === scrollContentView })

        let direction = viewModel.component.properties.direction ?? .vertical
        let showsIndicator = viewModel.component.properties.showsIndicator ?? true
        let insetAdjustment = viewModel.component.properties.contentInsetAdjustment ?? .automatic
        scrollView.contentInsetAdjustmentBehavior = insetAdjustment == .automatic ? .automatic : .never

        switch direction {
        case .vertical:
            scrollView.showsVerticalScrollIndicator = showsIndicator
            scrollView.showsHorizontalScrollIndicator = false
        case .horizontal:
            scrollView.showsHorizontalScrollIndicator = showsIndicator
            scrollView.showsVerticalScrollIndicator = false
        }

        if let inset = viewModel.component.properties.contentInset {
            scrollView.contentInset = UIEdgeInsets(
                top: inset.top ?? 0,
                left: inset.left ?? 0,
                bottom: inset.bottom ?? 0,
                right: inset.right ?? 0
            )
        }

        // scrollContentView edges pinned to scrollView's content layout guide
        scrollContentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor).isActive = true
        scrollContentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor).isActive = true
        scrollContentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor).isActive = true
        scrollContentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor).isActive = true

        // Match frame layout guide for non-scrolling axis
        switch direction {
        case .vertical:
            scrollContentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor).isActive = true
        case .horizontal:
            scrollContentView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor).isActive = true
        }

        // Tear down any previous marquee state before re-rendering — clears
        // snapshot, display link, and container so the new content gets a
        // fresh setup. Idempotent: no-op when not in marquee mode.
        teardownAutoScroll()
        autoScrollDidInstall = false

        let autoScrollProps = viewModel.component.properties.autoScroll
        if autoScrollProps != nil {
            // Marquee mode: render children into a dedicated container pinned to
            // scrollContentView's leading/top/bottom and trailing (initially, so
            // layout can compute the intrinsic length). Once the snapshot installs,
            // its trailing constraint is deactivated so scrollContentView ends up
            // at exactly 2× the original length without stretching anything.
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            scrollContentView.addSubview(container)
            let endConstraint: NSLayoutConstraint
            switch direction {
            case .horizontal:
                endConstraint = container.trailingAnchor.constraint(equalTo: scrollContentView.trailingAnchor)
                NSLayoutConstraint.activate([
                    container.leadingAnchor.constraint(equalTo: scrollContentView.leadingAnchor),
                    container.topAnchor.constraint(equalTo: scrollContentView.topAnchor),
                    container.bottomAnchor.constraint(equalTo: scrollContentView.bottomAnchor),
                    endConstraint,
                ])
            case .vertical:
                endConstraint = container.bottomAnchor.constraint(equalTo: scrollContentView.bottomAnchor)
                NSLayoutConstraint.activate([
                    container.topAnchor.constraint(equalTo: scrollContentView.topAnchor),
                    container.leadingAnchor.constraint(equalTo: scrollContentView.leadingAnchor),
                    container.trailingAnchor.constraint(equalTo: scrollContentView.trailingAnchor),
                    endConstraint,
                ])
            }
            marqueeContainer = container
            marqueeContainerEndConstraint = endConstraint

            viewModel.component.children.forEach { child in
                viewModel.service.renderComponent(child, superview: container, parentPath: viewModel.componentPath, parentVariableStore: viewModel.variableStore)
            }

            // Marquee: user shouldn't drag the auto-scrolling carousel.
            scrollView.isScrollEnabled = false

            // Defer snapshot creation until autolayout has measured the children —
            // we need the real intrinsic length before sizing the duplicate.
            DispatchQueue.main.async { [weak self] in
                self?.installAutoScrollIfNeeded()
            }
        } else {
            scrollView.isScrollEnabled = true
            viewModel.component.children.forEach { child in
                viewModel.service.renderComponent(child, superview: scrollContentView, parentPath: viewModel.componentPath, parentVariableStore: viewModel.variableStore)
            }
        }
    }

    // MARK: - Auto-scroll lifecycle

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Resume animation when reattached to a window.
        if window != nil, viewModel?.component.properties.autoScroll != nil {
            if !autoScrollDidInstall {
                DispatchQueue.main.async { [weak self] in
                    self?.installAutoScrollIfNeeded()
                }
            } else {
                startAutoScrollDisplayLink()
            }
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        // Stop the display link on detach so it doesn't keep firing or retain self.
        if newWindow == nil {
            stopAutoScrollDisplayLink()
        }
    }

    /// Installs the duplicated marquee content (if `infinite`) and starts the
    /// display link. Safe to call multiple times — guarded by `autoScrollDidInstall`.
    ///
    /// We re-render the children into a fresh duplicate container rather than
    /// taking a `snapshotView`: a snapshot captures only what's drawn, so
    /// async-loaded images would be blank. The duplicate runs its own load
    /// lifecycle and fills in independently of the original's timing.
    private func installAutoScrollIfNeeded() {
        guard let viewModel,
              let autoScroll = viewModel.component.properties.autoScroll,
              let container = marqueeContainer,
              !autoScrollDidInstall else { return }

        scrollView.layoutIfNeeded()

        let direction = viewModel.component.properties.direction ?? .vertical
        let originalLength: CGFloat = direction == .horizontal ? container.bounds.width : container.bounds.height
        guard originalLength > 0 else { return }

        autoScrollOriginalLength = originalLength

        let infinite = autoScroll.infinite ?? true
        let loopGap = autoScroll.loopGap ?? 0
        if infinite {
            // Build the duplicate as a sibling of `container`. Detaching the
            // container's trailing/bottom constraint lets the duplicate claim
            // the trailing edge; `container.width = duplicate.width` makes
            // scrollContentView span exactly 2× the original length (+ loopGap).
            let duplicate = UIView()
            duplicate.translatesAutoresizingMaskIntoConstraints = false
            scrollContentView.addSubview(duplicate)
            autoScrollSnapshot = duplicate

            marqueeContainerEndConstraint?.isActive = false

            switch direction {
            case .horizontal:
                NSLayoutConstraint.activate([
                    duplicate.leadingAnchor.constraint(equalTo: container.trailingAnchor, constant: loopGap),
                    duplicate.topAnchor.constraint(equalTo: scrollContentView.topAnchor),
                    duplicate.bottomAnchor.constraint(equalTo: scrollContentView.bottomAnchor),
                    duplicate.trailingAnchor.constraint(equalTo: scrollContentView.trailingAnchor),
                    duplicate.widthAnchor.constraint(equalTo: container.widthAnchor),
                ])
            case .vertical:
                NSLayoutConstraint.activate([
                    duplicate.topAnchor.constraint(equalTo: container.bottomAnchor, constant: loopGap),
                    duplicate.leadingAnchor.constraint(equalTo: scrollContentView.leadingAnchor),
                    duplicate.trailingAnchor.constraint(equalTo: scrollContentView.trailingAnchor),
                    duplicate.bottomAnchor.constraint(equalTo: scrollContentView.bottomAnchor),
                    duplicate.heightAnchor.constraint(equalTo: container.heightAnchor),
                ])
            }

            // Unique parentPath suffix so duplicate child paths don't collide
            // with the originals in the view registry.
            let duplicatePath = viewModel.componentPath + ".marqueeClone"
            viewModel.component.children.forEach { child in
                viewModel.service.renderComponent(
                    child,
                    superview: duplicate,
                    parentPath: duplicatePath,
                    parentVariableStore: viewModel.variableStore
                )
            }

            // Wrap cycle includes the gap so the seam stays invisible: at
            // offset (originalLength + loopGap) the viewport shows the duplicate
            // at its start, identical to resetting offset to 0.
            autoScrollOriginalLength = originalLength + loopGap
        }

        autoScrollDidInstall = true
        if window != nil {
            startAutoScrollDisplayLink()
        }
    }

    private func startAutoScrollDisplayLink() {
        guard autoScrollDisplayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(autoScrollTick(_:)))
        link.add(to: .main, forMode: .common)
        autoScrollDisplayLink = link
        autoScrollLastTimestamp = nil
    }

    private func stopAutoScrollDisplayLink() {
        autoScrollDisplayLink?.invalidate()
        autoScrollDisplayLink = nil
        autoScrollLastTimestamp = nil
    }

    private func teardownAutoScroll() {
        stopAutoScrollDisplayLink()
        autoScrollSnapshot?.removeFromSuperview()
        autoScrollSnapshot = nil
        marqueeContainer?.removeFromSuperview()
        marqueeContainer = nil
        marqueeContainerEndConstraint = nil
        autoScrollOriginalLength = 0
    }

    /// Per-frame tick. Advances `contentOffset` by `speed * deltaTime`; when
    /// `infinite`, wraps modulo the original content length for a seamless loop.
    @objc private func autoScrollTick(_ link: CADisplayLink) {
        guard let viewModel,
              let autoScroll = viewModel.component.properties.autoScroll else {
            stopAutoScrollDisplayLink()
            return
        }
        let now = link.timestamp
        guard let last = autoScrollLastTimestamp else {
            autoScrollLastTimestamp = now
            return
        }
        let dt = now - last
        autoScrollLastTimestamp = now

        let advance = autoScroll.speed * CGFloat(dt)
        let direction = viewModel.component.properties.direction ?? .vertical
        let infinite = autoScroll.infinite ?? true

        // Wrap length is recomputed live from the marquee container's current
        // main-axis size rather than the value measured once at install. The
        // duplicate is pinned by constraints (`duplicate.leading == container.trailing
        // + loopGap`, `duplicate.width == container.width`), so its start always
        // sits at `container.length + loopGap` from the origin. If the content
        // resizes after install (async image loads, layout compression, a corner
        // re-resolve, …) a cached length would no longer match that seam — the
        // loop would jump by the stale-vs-current delta on every wrap. Reading
        // the live container size keeps the seam exact and self-correcting.
        let containerLength: CGFloat = marqueeContainer.map {
            direction == .horizontal ? $0.bounds.width : $0.bounds.height
        } ?? 0
        let loopGap = autoScroll.loopGap ?? 0
        let length = containerLength > 0
            ? (infinite ? containerLength + loopGap : containerLength)
            : autoScrollOriginalLength

        var offset = scrollView.contentOffset
        switch direction {
        case .horizontal:
            offset.x += advance
            if infinite, length > 0 {
                if offset.x >= length {
                    offset.x -= length
                } else if offset.x < 0 {
                    offset.x += length
                }
            }
        case .vertical:
            offset.y += advance
            if infinite, length > 0 {
                if offset.y >= length {
                    offset.y -= length
                } else if offset.y < 0 {
                    offset.y += length
                }
            }
        }
        scrollView.contentOffset = offset
    }
}

// MARK: - StreamingUpdatable

extension CScrollViewView: StreamingUpdatable {

    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CScrollViewViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }

        self.viewModel = vm
        bindStyle(vm.style, animation: vm.animation)
        configureContent(viewModel: vm, animated: animated)
        return vm
    }
}

// MARK: - UIScrollViewDelegate

extension CScrollViewView: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let props = viewModel?.component.properties
        let hasOutputVar = props?.outputVariable != nil
        let hasThreshold = props?.scrollThreshold != nil

        guard hasOutputVar || hasThreshold else { return }

        let now = CACurrentMediaTime()
        let key = ObjectIdentifier(self)
        if let lastTime = Self.lastUpdateTime[key], now - lastTime < Self.updateInterval {
            return
        }
        Self.lastUpdateTime[key] = now

        let direction = props?.direction ?? .vertical
        // Normalize so 0 = resting position, accounting for content inset adjustment.
        let rawOffset = direction == .horizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y
        let inset = direction == .horizontal ? scrollView.adjustedContentInset.left : scrollView.adjustedContentInset.top
        let offset = rawOffset + inset

        if let outputVar = props?.outputVariable {
            try? viewModel?.variableStore.setValue(name: outputVar, value: offset)
        }

        checkScrollThreshold(offset: offset)
    }

    /// Fires .onScrollThreshold action when the scroll offset crosses the configured threshold.
    /// Injects `$crossed` (true when past threshold) and `$offset` overlays into the action context.
    private func checkScrollThreshold(offset: CGFloat) {
        guard let threshold = viewModel?.component.properties.scrollThreshold,
              let viewModel = viewModel,
              let action = viewModel.component.actions?[.onScrollThreshold] else { return }

        let crossed = offset >= threshold
        guard crossed != lastScrollThresholdCrossed else { return }
        lastScrollThresholdCrossed = crossed

        // Defer firing so sync side-effects don't interfere with the active scroll gesture.
        DispatchQueue.main.async { [weak viewModel] in
            guard let viewModel = viewModel else { return }
            let context = VariableContext(store: viewModel.variableStore)
                .overlaying("$crossed", value: crossed)
                .overlaying("$offset", value: Double(offset))
            do {
                try VariableActionHandler().execute(action: action, store: viewModel.variableStore, context: context)
            } catch {
                viewModel.service.context.logger.error("Failed to execute onScrollThreshold action: \(error)")
            }
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateOutputVariable(scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            updateOutputVariable(scrollView)
        }
    }

    private func updateOutputVariable(_ scrollView: UIScrollView) {
        guard let outputVar = viewModel?.component.properties.outputVariable else { return }
        let direction = viewModel?.component.properties.direction ?? .vertical
        let rawOffset = direction == .horizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y
        let inset = direction == .horizontal ? scrollView.adjustedContentInset.left : scrollView.adjustedContentInset.top
        let offset = rawOffset + inset
        try? viewModel?.variableStore.setValue(name: outputVar, value: offset)
    }
}
