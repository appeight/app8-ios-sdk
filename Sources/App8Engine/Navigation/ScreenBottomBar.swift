//
//  ScreenBottomBar.swift
//  App8Engine
//
//  `screen.content.bottomBar`: a component pinned to the bottom of a screen
//  the way the navigation bar is pinned to the top.
//
//  - Full width. `component` sits inside `insets`; `insets.bottom` is
//    measured from the bottom safe area the screen had without the bar (home
//    indicator, or the tab bar when one is shown). The keyboard does not move
//    the bar.
//  - The bar's height (top edge to that safe area) is added to the screen's
//    bottom safe area (`additionalSafeAreaInsets.bottom`), so scroll content
//    gets the matching inset and safe-area-pinned content stays above it.
//    The screen's own `additionalSafeAreaInsets.bottom` adds on top and does
//    not move the bar.
//  - `style.background: "system"` (default): iOS 26 draws no fill — the
//    content scrolls under the bar with the system bottom scroll-edge effect
//    (`edgeEffect` soft / hard) via `UIScrollEdgeElementContainerInteraction`.
//    iOS 18–25: the toolbar look — transparent while the content ends above
//    the bar, chrome material + hairline while content is under it.
//    A `material` / `fill` style entity replaces it (no edge effect).
//  - `hidden` slides the bar down by its height while fading it, 0.33 s cubic
//    ease-out, the safe area shrinking with it. A bar that starts hidden
//    shows the first time without animation.
//

import Combine
import UIKit

@MainActor
final class ScreenBottomBar {

    static let defaultInsets = UIEdgeInsets(top: 12, left: 16, bottom: 8, right: 16)
    static let animationDuration: TimeInterval = 0.33

    let config: DSL.Model.BottomBar
    /// The bar: background + content. Bottom edge at the screen's bottom (or
    /// the top of a shown tab bar).
    let containerView = BottomBarContainerView()
    /// Holds the rendered `component`, inside the insets.
    let contentSlot = UIView()
    /// Custom (`material` / `fill`) background, or the iOS 18–25 system fill.
    private(set) var backgroundView: UIView?
    /// iOS 18–25 system look: blur + hairline, shown while content is under the bar.
    private var systemFillView: UIView?

    private(set) var isHidden = false
    /// iOS 18–25 system look: content currently scrolls under the bar.
    private(set) var hasContentUnder = false
    private weak var host: ScreenViewController?
    private weak var viewModel: ComponentViewModelAbstract?
    private var hiddenCancellable: AnyCancellable?
    private var slotBottomConstraint: NSLayoutConstraint?
    private var containerBottomConstraint: NSLayoutConstraint?
    private var edgeInteraction: AnyObject?
    private(set) weak var edgeScrollView: UIScrollView?
    private var scrollObservations: [NSKeyValueObservation] = []
    private var animator: UIViewPropertyAnimator?

    /// Bottom safe-area space the bar takes now (0 while hidden).
    private(set) var safeAreaContribution: CGFloat = 0

    var insets: UIEdgeInsets {
        let d = Self.defaultInsets
        guard let i = config.insets else { return d }
        return UIEdgeInsets(top: i.top ?? d.top, left: i.left ?? d.left, bottom: i.bottom ?? d.bottom, right: i.right ?? d.right)
    }

    var usesSystemBackground: Bool {
        guard case .style = config.style?.background else { return true }
        return false
    }

    init(config: DSL.Model.BottomBar) {
        self.config = config
    }

    // MARK: - Install

    /// Adds the bar to `host.view` above `contentView` and renders the
    /// component in the screen's scope.
    func install(
        in host: ScreenViewController,
        above contentView: UIView,
        service: App8Service,
        viewModel: ComponentViewModelAbstract,
        parentPath: String
    ) {
        guard var component = config.component else { return }
        self.host = host
        self.viewModel = viewModel
        let view = host.view!

        containerView.accessibilityIdentifier = "app8.bottomBar"
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(containerView, aboveSubview: contentView)
        installBackground(service: service)

        contentSlot.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(contentSlot)

        let insets = self.insets
        let guide = view.safeAreaLayoutGuide
        let slotBottom = contentSlot.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -insets.bottom)
        let containerBottom = containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        slotBottomConstraint = slotBottom
        containerBottomConstraint = containerBottom
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerBottom,
            contentSlot.topAnchor.constraint(equalTo: containerView.topAnchor, constant: insets.top),
            contentSlot.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: insets.left),
            contentSlot.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -insets.right),
            slotBottom
        ])

        if let resolver = service.styleResolver {
            component.resolveStylePointers(resolver: resolver)
        }
        service.renderComponent(
            component,
            superview: contentSlot,
            parentPath: "\(parentPath).bottomBar",
            parentVariableStore: viewModel.variableStore
        )

        if let flag = config.hidden?.trimmingCharacters(in: .whitespaces), !flag.isEmpty {
            // First value: no animation.
            setHidden(resolveHidden(flag), animated: false)
            if flag.contains("{{") {
                hiddenCancellable = viewModel.variablesChanged
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        guard let self else { return }
                        self.setHidden(self.resolveHidden(flag), animated: true)
                    }
            }
        }
    }

    private func resolveHidden(_ flag: String) -> Bool {
        guard flag.contains("{{") else { return flag.lowercased() == "true" || flag == "1" }
        return viewModel?.resolvePropertyToBool(flag) ?? false
    }

    private func installBackground(service: App8Service) {
        let background: UIView?
        switch config.style?.background ?? .system {
        case .system:
            if #available(iOS 26.0, *) {
                // No fill: the system scroll-edge effect is the bar's material.
                background = nil
            } else {
                let fill = Self.makeToolbarFill()
                fill.alpha = 0
                systemFillView = fill
                background = fill
            }
        case .style(let style):
            background = Self.makeStyleBackground(style, resolver: service.styleResolver)
        }
        guard let background else { return }
        background.isUserInteractionEnabled = false
        background.translatesAutoresizingMaskIntoConstraints = false
        containerView.insertSubview(background, at: 0)
        background.cMakeEqualToSuperview()
        backgroundView = background
    }

    /// The iOS 18–25 toolbar look: chrome material with a top hairline.
    static func makeToolbarFill() -> UIView {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        let hairline = UIView()
        hairline.backgroundColor = .separator
        hairline.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(hairline)
        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: blur.topAnchor),
            hairline.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1 / max(1, UITraitCollection.current.displayScale))
        ])
        return blur
    }

    /// A `material` or `fill` style entity (inline or pointer) as a view.
    static func makeStyleBackground(
        _ style: DSL.Model.Style.`Any`,
        resolver: ((String) -> (any DSL.Model.Style.Entity)?)?
    ) -> UIView? {
        var style = style
        if let resolver { style.resolveStylePointers(resolver: resolver) }
        let material: DSL.Model.Style.Material
        if let entity: DSL.Model.Style.Material.Entity = style.asConcreteEntity() {
            material = entity.content
        } else if style.isMaterial {
            material = DSL.Model.Style.Material(layers: [style])
        } else {
            return nil
        }
        let view = MaterialView()
        view.update(material: material)
        return view
    }

    // MARK: - Hidden

    func setHidden(_ hidden: Bool, animated: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        containerView.isUserInteractionEnabled = !hidden
        containerView.accessibilityElementsHidden = hidden
        guard animated, let host, host.viewIfLoaded?.window != nil else {
            applyHiddenAppearance()
            host?.view.setNeedsLayout()
            return
        }
        animator?.stopAnimation(true)
        // Cubic ease-out (0.33, 1, 0.68, 1): the bar and the safe area move together.
        let animator = UIViewPropertyAnimator(
            duration: Self.animationDuration,
            controlPoint1: CGPoint(x: 0.33, y: 1),
            controlPoint2: CGPoint(x: 0.68, y: 1)
        ) { [weak self] in
            guard let self, let host = self.host else { return }
            self.applyHiddenAppearance()
            self.updateSafeArea()
            host.view.layoutIfNeeded()
        }
        self.animator = animator
        animator.startAnimation()
    }

    private func applyHiddenAppearance() {
        let height = containerView.bounds.height
        containerView.transform = isHidden ? CGAffineTransform(translationX: 0, y: height) : .identity
        containerView.alpha = isHidden ? 0 : 1
    }

    // MARK: - Layout pass

    /// Runs on every screen layout: positions the bar against the screen's
    /// own safe area, publishes the bar's height into the safe area, and keeps
    /// the scroll-edge treatment attached to the screen's scroll view.
    func layoutPass(content root: UIView) {
        guard let host, let view = host.viewIfLoaded else { return }
        let base = baseBottomInset
        let tabBarCover = tabBarHeight(in: view, base: base)
        if slotBottomConstraint?.constant != -(base + insets.bottom) {
            slotBottomConstraint?.constant = -(base + insets.bottom)
        }
        if containerBottomConstraint?.constant != -tabBarCover {
            containerBottomConstraint?.constant = -tabBarCover
        }
        if isHidden, animator?.isRunning != true { applyHiddenAppearance() }
        updateSafeArea()
        attachScrollView(in: root)
        updateEdgeEffect()
        updateContentUnder()
    }

    /// The screen's bottom safe area without any additional inset: home
    /// indicator / gesture bar, plus a shown tab bar.
    var baseBottomInset: CGFloat {
        guard let host, let view = host.viewIfLoaded else { return 0 }
        let own = max(0, view.safeAreaInsets.bottom - host.additionalSafeAreaInsets.bottom)
        // In a sheet moving to an edge-attached detent, UIKit moves the sheet
        // frame by frame; the screen's last layout pass comes before the sheet
        // rests and UIKit hands the screen its safe area only on its next
        // pass, while the sheet's container already has the home-indicator
        // inset (seen: screen 19 pt, container 34 pt). Nothing else lays the
        // screen out, so the bar stayed in the display's corner until a tap.
        guard host.sheetPresentationController != nil,
              let container = host.navigationController?.view ?? host.parent?.view,
              container !== view else { return own }
        let gap = max(0, container.bounds.maxY - view.convert(view.bounds, to: container).maxY)
        return max(own, container.safeAreaInsets.bottom - gap)
    }

    /// Height of a shown tab bar over the screen's bottom (the bar's
    /// background stops at its top edge).
    private func tabBarHeight(in view: UIView, base: CGFloat) -> CGFloat {
        guard let tabBar = host?.tabBarController?.tabBar, !tabBar.isHidden, tabBar.window != nil,
              host?.hidesBottomBarWhenPushed != true else { return 0 }
        let frame = tabBar.convert(tabBar.bounds, to: view)
        guard frame.minY < view.bounds.maxY, frame.maxY > view.bounds.minY else { return 0 }
        return min(base, max(0, view.bounds.maxY - frame.minY))
    }

    /// Writes the bar's height into the host's bottom safe area. Applied as a
    /// delta so a keyboard inset already in `additionalSafeAreaInsets` stays.
    private func updateSafeArea() {
        guard let host else { return }
        let barHeight = contentSlot.bounds.height + insets.top + insets.bottom
        let contribution = (isHidden || contentSlot.bounds.height <= 0) ? 0 : barHeight
        guard contribution != safeAreaContribution else { return }
        let delta = contribution - safeAreaContribution
        safeAreaContribution = contribution
        host.additionalSafeAreaInsets.bottom = max(0, host.additionalSafeAreaInsets.bottom + delta)
    }

    // MARK: - Scroll view under the bar

    /// The screen's scroll view: the outermost vertical scroll view that
    /// reaches the bar.
    private func attachScrollView(in root: UIView) {
        guard let view = host?.viewIfLoaded else { return }
        let barTop = containerView.center.y - containerView.bounds.height / 2
        var found: UIScrollView?
        var queue: [UIView] = [root]
        while !queue.isEmpty, found == nil {
            let candidate = queue.removeFirst()
            if let scrollView = candidate as? UIScrollView, Self.scrollsVertically(scrollView) {
                let frame = scrollView.convert(scrollView.bounds, to: view)
                if frame.maxY > barTop { found = scrollView; break }
                continue
            }
            queue.append(contentsOf: candidate.subviews)
        }
        guard let found, found !== edgeScrollView else { return }
        edgeScrollView = found
        scrollObservations = [
            found.observe(\.contentOffset, options: []) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateContentUnder() }
            },
            found.observe(\.contentSize, options: []) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateContentUnder() }
            }
        ]
    }

    static func scrollsVertically(_ scrollView: UIScrollView) -> Bool {
        guard !(scrollView is UITextView), scrollView.isScrollEnabled, !scrollView.isPagingEnabled else { return false }
        if let collection = scrollView as? UICollectionView {
            // A horizontal shelf scrolls in its own orthogonal scroller.
            if let flow = collection.collectionViewLayout as? UICollectionViewFlowLayout {
                return flow.scrollDirection == .vertical
            }
            return collection.alwaysBounceVertical || collection.contentSize.height > collection.bounds.height
        }
        return true
    }

    /// iOS 26, `system` background: the bar is the bottom edge element of the
    /// screen's scroll view, which draws the soft / hard scroll-edge effect.
    private func updateEdgeEffect() {
        guard #available(iOS 26.0, *), usesSystemBackground, let scrollView = edgeScrollView else { return }
        let style: UIScrollEdgeEffect.Style = config.edgeEffect == .hard ? .hard : .soft
        let edge = scrollView.bottomEdgeEffect
        if edge.style != style { edge.style = style }
        if edge.isHidden != isHidden { edge.isHidden = isHidden }
        let interaction: UIScrollEdgeElementContainerInteraction
        if let existing = edgeInteraction as? UIScrollEdgeElementContainerInteraction {
            interaction = existing
        } else {
            interaction = UIScrollEdgeElementContainerInteraction()
            interaction.edge = .bottom
            containerView.addInteraction(interaction)
            edgeInteraction = interaction
        }
        if interaction.scrollView !== scrollView { interaction.scrollView = scrollView }
    }

    /// The scroll-edge interaction (iOS 26, `system` background), for tests.
    var scrollEdgeInteraction: AnyObject? { edgeInteraction }

    /// iOS 18–25 `system` look: fade the toolbar fill in while the scroll
    /// content reaches under the bar, out when it ends above it.
    private func updateContentUnder() {
        guard let fill = systemFillView, let view = host?.viewIfLoaded else { return }
        var under = false
        if let scrollView = edgeScrollView, scrollView.window != nil || scrollView.isDescendant(of: view) {
            let contentBottom = scrollView.convert(CGPoint(x: 0, y: scrollView.contentSize.height), to: view).y
            let barTop = containerView.center.y - containerView.bounds.height / 2
            under = contentBottom > barTop + 0.5
        }
        guard under != hasContentUnder else { return }
        hasContentUnder = under
        UIView.animate(withDuration: 0.2) { fill.alpha = under ? 1 : 0 }
    }
}

/// The bar's root view (a named type for hierarchy lookups and tests).
final class BottomBarContainerView: UIView {}

extension ScreenViewController {

    /// Renders `bottomBar` above the screen content. Once per screen; a
    /// `bottomBar` without a `component` renders nothing.
    func installBottomBar(
        _ config: DSL.Model.BottomBar,
        service: App8Service,
        viewModel: ComponentViewModelAbstract,
        parentPath: String
    ) {
        guard bottomBar == nil, config.component != nil else { return }
        let bar = ScreenBottomBar(config: config)
        bottomBar = bar
        bar.install(in: self, above: rootContainerView, service: service, viewModel: viewModel, parentPath: parentPath)
    }
}
