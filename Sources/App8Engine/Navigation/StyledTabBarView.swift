import UIKit

/// `tabBarScreen.barStyle` (tab-bar-screen.md, "Bar style"): the bar drawn by
/// the engine instead of the system items, for apps whose voice the system
/// bar does not fit.
///
/// It lives inside the system `UITabBar`, whose items are blanked: UIKit
/// keeps owning the bar's place, the screens' bottom safe area,
/// hide-on-push (`hidesTabBar`) and the slide back on pop. This view draws
/// the labels (rendered as DSL label components, so brand text styles
/// resolve like anywhere else) or the app's template, and the selection:
/// a capsule, underline or box that slides, or an opacity cross-fade.
@MainActor
final class StyledTabBarView: UIView {

    struct Item {
        let id: String
        let label: String
        let icon: String
        var badge: String?
    }

    var onSelect: ((Int) -> Void)?

    private let style: DSL.Model.TabBarContent.BarStyle
    private let service: App8Service
    private var items: [Item]
    private let tint: UIColor
    private let unselected: UIColor
    private let indicatorTint: UIColor
    private let badgeTint: UIColor
    private let badgeText: UIColor

    private let backgroundView = UIView()
    private let indicatorView = UIView()
    private let content = UIView()
    private var badgeLabels: [UILabel] = []
    private var accessibilityItems: [UIAccessibilityElement] = []
    /// The template bar's scope (`tabs`, `selectedTab`, `selectedIndex`, `selectionProgress`).
    private var scope: ScopedVariableStore?
    private var rendered = false
    /// `background` naming a fill / material style: a DSL view draws it.
    var backgroundStyleId: String?
    /// `shape: edge`: square corners, the background continued below the
    /// bar by `bottomExtension` (under the home indicator).
    var isEdge = false
    /// Corners of an engine-drawn bar (nil: the system bar's capsule on iOS 26).
    var drawnCornerRadius: CGFloat?
    var bottomExtension: CGFloat = 0 {
        didSet { if oldValue != bottomExtension { setNeedsLayout() } }
    }

    private(set) var selectedIndex: Int
    /// Fractional index the selection is drawn at (animated).
    private var progress: CGFloat
    private var animator: UIViewPropertyAnimator?
    private var progressLink: CADisplayLink?
    private var progressFrom: CGFloat = 0
    private var progressTo: CGFloat = 0
    private var progressStart: CFTimeInterval = 0
    private let haptic = UISelectionFeedbackGenerator()

    static let duration: TimeInterval = 0.3
    /// Cubic ease-out, as in the spec.
    nonisolated static func easeOut(_ t: CGFloat) -> CGFloat { 1 - pow(1 - min(1, max(0, t)), 3) }

    init(style: DSL.Model.TabBarContent.BarStyle, items: [Item], selectedIndex: Int, service: App8Service,
         tint: UIColor, unselected: UIColor, indicator: UIColor?, badge: UIColor?, badgeText: UIColor?, background: UIColor?) {
        self.style = style
        self.items = items
        self.service = service
        self.tint = tint
        self.unselected = unselected
        // Without `indicatorColor`, a capsule is a faint wash of the tint (as
        // the system's selected-item pill); underline and box use the tint.
        self.indicatorTint = indicator ?? (style.selection == .capsule ? tint.withAlphaComponent(0.12) : tint)
        self.badgeTint = badge ?? .systemRed
        self.badgeText = badgeText ?? .white
        self.selectedIndex = selectedIndex
        self.progress = CGFloat(selectedIndex)
        super.init(frame: .zero)
        isAccessibilityElement = false
        accessibilityTraits = .tabBar
        backgroundView.backgroundColor = background
        backgroundView.isUserInteractionEnabled = false
        addSubview(backgroundView)
        indicatorView.isUserInteractionEnabled = false
        indicatorView.backgroundColor = indicatorTint
        indicatorView.isHidden = style.component != nil || style.selection == .opacity
        addSubview(indicatorView)
        addSubview(content)
        if style.component == nil {
            // Text bars: the whole bar is the touch target, one slot per tab.
            content.isUserInteractionEnabled = false
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Rendering

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height + (isEdge ? bottomExtension : 0))
        // On iOS 26 the bar is a floating capsule: a solid or styled
        // background takes its shape. An edge stripe stays square.
        if let drawnCornerRadius {
            backgroundView.layer.cornerRadius = min(drawnCornerRadius, bounds.height / 2)
            backgroundView.layer.cornerCurve = .continuous
            backgroundView.clipsToBounds = true
        } else if isEdge {
            backgroundView.layer.cornerRadius = 0
        } else if #available(iOS 26.0, *) {
            backgroundView.layer.cornerRadius = bounds.height / 2
            backgroundView.layer.cornerCurve = .continuous
            backgroundView.clipsToBounds = true
        }
        content.frame = bounds
        if !rendered, bounds.width > 0 {
            rendered = true
            render()
            content.setNeedsLayout()
            content.layoutIfNeeded()
        }
        applySelection(at: progress)
        hideSystemSelection()
        layoutBadges()
        updateAccessibility()
    }

    private func render() {
        let component: DSL.Model.Component.`Any`?
        if let id = backgroundStyleId,
           let entity = service.styleResolver?(id) as? DSL.Model.Style.Material.Entity {
            // A material entity (blur + tint layers…): drawn directly, its
            // layers in order, filling the bar's background.
            let view = MaterialView()
            view.update(material: entity.content)
            view.isUserInteractionEnabled = false
            view.frame = backgroundView.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            backgroundView.addSubview(view)
        } else if let id = backgroundStyleId,
           let data = try? JSONSerialization.data(withJSONObject: ["type": "view", "id": "tabBarBackground", "content": ["style": ["material": [["id": id]]]]]),
           var fill = try? JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: data) {
            if let resolver = service.styleResolver { fill.resolveStylePointers(resolver: resolver) }
            let view = service.renderComponent(fill, superview: backgroundView, parentPath: "tabBar").view
            // The rendered view has no layout of its own: pin it to the
            // background (a bare frame is dropped when it uses Auto Layout,
            // which left the bar with no background at all).
            if view.superview !== backgroundView { backgroundView.addSubview(view) }
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: backgroundView.topAnchor),
                view.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            ])
        }
        if let name = style.component {
            component = service.resolveTemplate(named: name)
            if component == nil { service.context.logger.error("tabBar.barStyle.component: no template '\(name)'") }
        } else {
            component = Self.textBar(items: items, style: style)
        }
        guard var component else { return }
        if let resolver = service.styleResolver { component.resolveStylePointers(resolver: resolver) }
        let store = ScopedVariableStore(parent: service.appVariableStore)
        define(store, "tabs", tabsValue())
        define(store, "selectedTab", items.indices.contains(selectedIndex) ? items[selectedIndex].id : "")
        define(store, "selectedIndex", selectedIndex)
        define(store, "selectionProgress", Double(selectedIndex))
        scope = store
        let result = service.renderComponent(component, superview: content, parentPath: "tabBar", parentVariableStore: store)
        result.view.translatesAutoresizingMaskIntoConstraints = false
        if result.view.constraints.isEmpty, result.view.superview === content,
           !content.constraints.contains(where: { $0.firstItem === result.view || $0.secondItem === result.view }) {
            NSLayoutConstraint.activate([
                result.view.topAnchor.constraint(equalTo: content.topAnchor),
                result.view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                result.view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                result.view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
        }
        if style.component == nil { makeBadges() }
    }

    private func define(_ store: ScopedVariableStore, _ name: String, _ value: Any) {
        try? store.defineVariable(name: name, definition: VariableDefinition(type: VariableType.inferType(from: value), initialValue: value))
    }

    private func tabsValue() -> [[String: Any]] {
        items.enumerated().map { index, item in
            ["id": item.id, "label": item.label, "icon": item.icon, "badge": item.badge ?? "", "index": index]
        }
    }

    /// The text variant as a DSL component: one equal slot per tab, its
    /// label centred (and, with `selectedText`, a second label in that style
    /// on top, cross-faded with the first).
    static func textBar(items: [Item], style: DSL.Model.TabBarContent.BarStyle) -> DSL.Model.Component.`Any`? {
        func label(_ id: String, _ text: String, _ textStyle: Any?) -> [String: Any] {
            var s: [String: Any] = ["numberOfLines": 1]
            if let textStyle { s = ["text": textStyle] } else { s = ["text": ["fontSize": 12, "fontWeight": "semibold"]] }
            return ["type": "label", "id": id, "content": [
                "properties": ["text": text, "numberOfLines": 1], "style": s,
                "layout": ["constraints": [["type": "centerX", "target": "superview"], ["type": "centerY", "target": "superview"]]],
            ]]
        }
        let slots: [[String: Any]] = items.enumerated().map { index, item in
            var children = [label("tabText\(index)", item.label, style.text?.value)]
            if let selected = style.selectedText?.value {
                children.append(label("tabTextOn\(index)", item.label, selected))
            }
            return ["type": "view", "id": "tabSlot\(index)", "content": ["children": children]]
        }
        let json: [String: Any] = ["type": "stackView", "id": "tabBarItems", "content": [
            "properties": ["axis": "horizontal", "distribution": "fillEqually", "alignment": "fill", "spacing": 0],
            "children": slots,
        ]]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder().decode(DSL.Model.Component.`Any`.self, from: data)
    }

    /// The iOS 26 platter's selection lens (a sibling once the bar sits in
    /// the platter) is replaced by the styled selection; UIKit may show it
    /// again when the selection changes.
    private func hideSystemSelection() {
        for sibling in superview?.subviews ?? [] where sibling !== self {
            for view in [sibling] + sibling.subviews where "\(type(of: view))".contains("Lens") { view.isHidden = true }
        }
    }

    // MARK: - Selection

    func setItems(badges: [String?]) {
        for (index, badge) in badges.enumerated() where items.indices.contains(index) { items[index].badge = badge }
        if let scope { try? scope.setValue(name: "tabs", value: tabsValue()) }
        layoutBadges()
        updateAccessibility()
    }

    /// Selects `index`: instant for the screens, the indicator follows with a
    /// 0.3 s cubic ease-out from wherever it is (a new tap retargets it).
    func select(_ index: Int, animated: Bool) {
        guard items.indices.contains(index) else { return }
        let changed = index != selectedIndex
        selectedIndex = index
        if let scope {
            try? scope.setMultipleValues(["selectedIndex": index, "selectedTab": items[index].id])
        }
        updateAccessibility()
        hideSystemSelection()
        DispatchQueue.main.async { [weak self] in self?.hideSystemSelection() }
        guard animated, changed, window != nil else {
            stopAnimations()
            progress = CGFloat(index)
            applySelection(at: progress)
            try? scope?.setValue(name: "selectionProgress", value: Double(index))
            return
        }
        animate(to: CGFloat(index))
    }

    private func stopAnimations() {
        animator?.stopAnimation(true)
        animator = nil
        progressLink?.invalidate()
        progressLink = nil
    }

    private func animate(to target: CGFloat) {
        // Retarget from what is on screen now.
        let current = currentProgress()
        stopAnimations()
        progress = current
        applySelection(at: current)
        let animator = UIViewPropertyAnimator(duration: Self.duration, controlPoint1: CGPoint(x: 0.33, y: 1), controlPoint2: CGPoint(x: 0.68, y: 1)) { [weak self] in
            self?.applySelection(at: target)
        }
        animator.addCompletion { [weak self] position in
            guard position == .end else { return }
            self?.progress = target
        }
        animator.startAnimation()
        self.animator = animator
        progress = target
        // The template bar's `selectionProgress`, frame by frame.
        guard scope != nil else { return }
        progressFrom = current
        progressTo = target
        progressStart = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(stepProgress))
        link.add(to: .main, forMode: .common)
        progressLink = link
    }

    @objc private func stepProgress() {
        let t = CGFloat((CACurrentMediaTime() - progressStart) / Self.duration)
        let value = progressFrom + (progressTo - progressFrom) * Self.easeOut(t)
        try? scope?.setValue(name: "selectionProgress", value: Double(value))
        if t >= 1 { progressLink?.invalidate(); progressLink = nil }
    }

    /// The selection on screen (mid-animation included), as a fractional index.
    private func currentProgress() -> CGFloat {
        guard animator?.isRunning == true, let layer = indicatorView.layer.presentation(), slotWidth > 0, !indicatorView.isHidden else {
            return progressLink != nil ? CGFloat((try? scope?.getValue(name: "selectionProgress") as? Double) ?? Double(progress)) : progress
        }
        return (layer.position.x - slotWidth / 2) / slotWidth
    }

    private var slotWidth: CGFloat { items.isEmpty ? 0 : bounds.width / CGFloat(items.count) }

    /// Draws the selection at fractional index `p` (animatable properties only).
    private func applySelection(at p: CGFloat) {
        guard style.component == nil, !items.isEmpty, bounds.width > 0 else { return }
        let lower = Int(floor(p)), upper = min(items.count - 1, lower + 1)
        let f = p - CGFloat(lower)
        let w0 = labelWidth(lower), w1 = labelWidth(upper)
        let labelW = w0 + (w1 - w0) * f
        let centerX = slotWidth * (p + 0.5)
        let midY = bounds.height / 2
        switch style.selection {
        case .capsule:
            let w = min(slotWidth - 6, labelW + 28), h = min(bounds.height - 8, 34)
            indicatorView.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            indicatorView.layer.cornerRadius = h / 2
            indicatorView.center = CGPoint(x: centerX, y: midY)
        case .underline:
            indicatorView.bounds = CGRect(x: 0, y: 0, width: labelW, height: 2)
            indicatorView.layer.cornerRadius = 1
            indicatorView.center = CGPoint(x: centerX, y: midY + labelHeight() / 2 + 5)
        case .box:
            let w = min(slotWidth - 4, labelW + 20), h = min(bounds.height - 10, 28)
            indicatorView.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            indicatorView.layer.cornerRadius = 0
            indicatorView.center = CGPoint(x: centerX, y: midY)
        case .opacity:
            break
        }
        // Labels: selected full, others dimmed (opacity) or in their colour;
        // with `selectedText`, the two label styles cross-fade.
        for index in items.indices {
            let weight = max(0, 1 - abs(p - CGFloat(index)))
            let off = labelView("tabText\(index)"), on = labelView("tabTextOn\(index)")
            if style.selection == .opacity {
                let alpha = CGFloat(style.unselectedOpacity) + (1 - CGFloat(style.unselectedOpacity)) * weight
                (on ?? off)?.alpha = alpha
                if on != nil { off?.alpha = 0 }
            } else if let on {
                on.alpha = weight
                off?.alpha = 1 - weight
            }
        }
    }

    private func labelView(_ id: String) -> UIView? { content.descendant(withIdentifier: id) }

    private func labelWidth(_ index: Int) -> CGFloat {
        guard let view = labelView("tabText\(index)") else { return 44 }
        return max(view.bounds.width, view.intrinsicContentSize.width)
    }

    private func labelHeight() -> CGFloat { labelView("tabText0")?.bounds.height ?? 14 }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard slotWidth > 0 else { return }
        let index = min(items.count - 1, max(0, Int(gesture.location(in: self).x / slotWidth)))
        haptic.selectionChanged()
        onSelect?(index)
    }

    // MARK: - Badges

    private func makeBadges() {
        badgeLabels = items.map { _ in
            let badge = UILabel()
            badge.font = .systemFont(ofSize: 11, weight: .semibold)
            badge.textAlignment = .center
            badge.textColor = badgeText
            badge.backgroundColor = badgeTint
            badge.layer.masksToBounds = true
            badge.isUserInteractionEnabled = false
            addSubview(badge)
            return badge
        }
    }

    private func layoutBadges() {
        let inline = style.badgePlacement == .inline
        for (index, badge) in badgeLabels.enumerated() {
            let value = items[index].badge ?? ""
            let shown = !(value.isEmpty || value == "0")
            badge.isHidden = !shown
            badge.text = value
            let size = badge.intrinsicContentSize
            let h: CGFloat = 16, w = max(h, size.width + 8)
            let slotCenter = slotWidth * (CGFloat(index) + 0.5)
            if inline {
                let layout = Self.inlineBadgeLayout(slotCenterX: slotCenter, midY: bounds.height / 2,
                                                    labelWidth: labelWidth(index), badgeSize: CGSize(width: w, height: h), shown: shown)
                badge.frame = layout.badge
                // The label and its badge are centred together in the slot.
                for id in ["tabText\(index)", "tabTextOn\(index)"] {
                    labelView(id)?.transform = CGAffineTransform(translationX: layout.labelShift, y: 0)
                }
            } else {
                let centerX = slotCenter + labelWidth(index) / 2 + 2
                badge.frame = CGRect(x: centerX, y: bounds.height / 2 - labelHeight() / 2 - h + 4, width: w, height: h)
            }
            badge.layer.cornerRadius = h / 2
        }
    }

    /// `badgePlacement: inline`: the badge 4 pt after the label on its line,
    /// vertically centred; label and badge centred together in the slot
    /// (`labelShift` moves the slot-centred label left by half the badge).
    nonisolated static func inlineBadgeLayout(slotCenterX: CGFloat, midY: CGFloat, labelWidth: CGFloat,
                                              badgeSize: CGSize, shown: Bool) -> (labelShift: CGFloat, badge: CGRect) {
        guard shown else {
            return (0, CGRect(x: slotCenterX + labelWidth / 2 + inlineBadgeGap, y: midY - badgeSize.height / 2,
                              width: badgeSize.width, height: badgeSize.height))
        }
        let total = labelWidth + inlineBadgeGap + badgeSize.width
        let start = slotCenterX - total / 2
        let badge = CGRect(x: start + labelWidth + inlineBadgeGap, y: midY - badgeSize.height / 2,
                           width: badgeSize.width, height: badgeSize.height)
        return (start + labelWidth / 2 - slotCenterX, badge)
    }

    nonisolated static let inlineBadgeGap: CGFloat = 4

    // MARK: - Accessibility (each item is a tab)

    private func updateAccessibility() {
        guard style.component == nil else { return }
        if accessibilityItems.count != items.count {
            accessibilityItems = items.map { _ in UIAccessibilityElement(accessibilityContainer: self) }
        }
        for (index, element) in accessibilityItems.enumerated() {
            element.accessibilityLabel = items[index].label
            element.accessibilityValue = items[index].badge.flatMap { $0.isEmpty || $0 == "0" ? nil : $0 }
            element.accessibilityTraits = index == selectedIndex ? [.button, .selected] : .button
            element.accessibilityFrameInContainerSpace = CGRect(x: slotWidth * CGFloat(index), y: 0, width: slotWidth, height: bounds.height)
        }
        accessibilityElements = accessibilityItems
    }
}

extension UIView {
    /// The first descendant whose `accessibilityIdentifier` is `id` (DSL component ids).
    func descendant(withIdentifier id: String) -> UIView? {
        for sub in subviews {
            if sub.accessibilityIdentifier == id { return sub }
            if let found = sub.descendant(withIdentifier: id) { return found }
        }
        return nil
    }
}
