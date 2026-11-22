//
//  ContextMenuBinder.swift
//  App8Engine
//
//  `content.contextMenu` → `UIContextMenuInteraction` on the component's view.
//  The preview renders `preview.component` through the normal render path in
//  the owning component's scope (a collection cell's scope includes `item`);
//  item titles / icons / flags are evaluated when the menu opens.
//

import ObjectiveC
import UIKit

/// A component view that can own a context menu. Returns its *current* view
/// model, which changes when a collection cell is reused or streamed.
@MainActor
protocol ContextMenuHost: UIView {
    var contextMenuViewModel: ComponentViewModelAbstract? { get }
}

@MainActor
final class ContextMenuBinder: NSObject, UIContextMenuInteractionDelegate {

    private static var key: UInt8 = 0

    private weak var host: ContextMenuHost?
    private var interaction: UIContextMenuInteraction?

    /// Installs the interaction once per view. Later renders / streaming
    /// updates read the menu from the host's current view model.
    static func bind(view: UIView, viewModel: ComponentViewModelAbstract) {
        guard let host = view as? ContextMenuHost, viewModel.contextMenuProps != nil else { return }
        if objc_getAssociatedObject(view, &key) is ContextMenuBinder { return }
        let binder = ContextMenuBinder()
        binder.host = host
        let interaction = UIContextMenuInteraction(delegate: binder)
        view.addInteraction(interaction)
        view.isUserInteractionEnabled = true
        binder.interaction = interaction
        objc_setAssociatedObject(view, &key, binder, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        binder.updateAccessibilityActions()
    }

    private var viewModel: ComponentViewModelAbstract? { host?.contextMenuViewModel }
    private var menu: DSL.Model.ContextMenu? { viewModel?.contextMenuProps }

    // MARK: - UIContextMenuInteractionDelegate

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let viewModel, let menu else { return nil }
        if let enabled = menu.isEnabled, viewModel.resolvePropertyToBool(enabled) == false { return nil }
        updateAccessibilityActions()

        let previewProvider: UIContextMenuContentPreviewProvider?
        if let preview = menu.preview {
            // Built and measured now, at the start of the press: its bound
            // text and `isHidden` are applied at once and again on the next
            // main-queue turns, all before UIKit asks for the preview at the
            // end of the lift. The platter then appears at its final size in
            // one piece; a size that changed after it was shown made UIKit
            // draw it twice (the first frame, then the resize).
            let controller = ContextMenuPreviewController(preview: preview, viewModel: viewModel, hostView: host)
            previewProvider = {
                controller.prepareForPresentation()
                return controller
            }
        } else {
            previewProvider = nil
        }
        // An identifier, so UIKit asks for the item's highlight and dismissal
        // previews (`preview.cornerRadius`) through the per-item delegate calls.
        return UIContextMenuConfiguration(identifier: "app8.contextMenu" as NSString, previewProvider: previewProvider) { [weak self] _ in
            self?.makeMenu()
        }
    }

    /// `preview.cornerRadius`: the lift and the shrink back onto the
    /// component use the same corners as the platter.
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configuration: UIContextMenuConfiguration,
        highlightPreviewForItemWithIdentifier identifier: any NSCopying
    ) -> UITargetedPreview? {
        targetedPreview()
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configuration: UIContextMenuConfiguration,
        dismissalPreviewForItemWithIdentifier identifier: any NSCopying
    ) -> UITargetedPreview? {
        targetedPreview()
    }

    private func targetedPreview() -> UITargetedPreview? {
        guard let host, host.window != nil, let radius = menu?.preview?.cornerRadius else { return nil }
        let parameters = UIPreviewParameters()
        parameters.visiblePath = Self.previewPath(in: host.bounds, cornerRadius: CGFloat(radius))
        return UITargetedPreview(view: host, parameters: parameters)
    }

    static func previewPath(in rect: CGRect, cornerRadius: CGFloat) -> UIBezierPath {
        cornerRadius <= 0 ? UIBezierPath(rect: rect) : UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
    }

    /// `onPreviewTap` runs as the preview starts to expand (the system's
    /// `.pop` commit), and a push it starts has no transition of its own: the
    /// expanding preview is the transition and dissolves straight into the
    /// new screen. Before, it ran once the expansion had ended and the old
    /// screen was showing again, then pushed with its own zoom.
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionCommitAnimating
    ) {
        guard let menu, !menu.onPreviewTap.isEmpty else { return }
        animator.preferredCommitStyle = .pop
        let actions = menu.onPreviewTap
        animator.addAnimations { [weak self] in
            self?.runPreviewTap(actions)
        }
    }

    private func runPreviewTap(_ actions: [DSL.Model.Action]) {
        guard let viewModel else { return }
        let context = viewModel.componentService?.context
        let previous = context?.suppressesNavigationTransitions ?? false
        context?.suppressesNavigationTransitions = true
        defer { context?.suppressesNavigationTransitions = previous }
        viewModel.executeContextMenuActions(actions)
    }

    // MARK: - Menu

    /// Builds the menu from the items, evaluated now (menu open).
    func makeMenu() -> UIMenu? {
        guard let viewModel, let menu, !menu.items.isEmpty else { return nil }
        var children: [UIMenuElement] = []
        for item in menu.items {
            if let hidden = item.hidden, viewModel.resolvePropertyToBool(hidden) == true { continue }
            let title = viewModel.resolvePropertyToString(item.title)
            let image = item.icon
                .map { viewModel.resolvePropertyToString($0) }
                .flatMap { $0.isEmpty ? nil : UIImage(systemName: $0) }
            let actions = item.actions
            let action = UIAction(title: title, image: image, identifier: UIAction.Identifier(item.id)) { [weak self] _ in
                self?.viewModel?.executeContextMenuActions(actions)
            }
            if let subtitle = item.subtitle {
                let resolved = viewModel.resolvePropertyToString(subtitle)
                if !resolved.isEmpty { action.subtitle = resolved }
            }
            var attributes: UIMenuElement.Attributes = []
            if item.destructive { attributes.insert(.destructive) }
            if let enabled = item.isEnabled, viewModel.resolvePropertyToBool(enabled) == false {
                attributes.insert(.disabled)
            }
            action.attributes = attributes
            children.append(action)
        }
        return children.isEmpty ? nil : UIMenu(children: children)
    }

    /// VoiceOver: each visible item as a custom action on the element.
    private func updateAccessibilityActions() {
        guard let host, let viewModel, let menu else { return }
        host.accessibilityCustomActions = menu.items.compactMap { item in
            if let hidden = item.hidden, viewModel.resolvePropertyToBool(hidden) == true { return nil }
            if let enabled = item.isEnabled, viewModel.resolvePropertyToBool(enabled) == false { return nil }
            let actions = item.actions
            return UIAccessibilityCustomAction(name: viewModel.resolvePropertyToString(item.title)) { [weak self] _ in
                self?.viewModel?.executeContextMenuActions(actions)
                return true
            }
        }
    }
}

// MARK: - Preview

/// Renders `preview.component` as its own root, non-interactive, sized to
/// `width` × `height` (defaults: screen width − 32; the content's own fitting
/// height at that width, ≤ 70% of the screen).
@MainActor
final class ContextMenuPreviewController: UIViewController {

    private let preview: DSL.Model.ContextMenu.Preview
    private weak var viewModel: ComponentViewModelAbstract?
    private weak var hostView: UIView?
    /// Pinned to the top and sides only: its height is the content's own, so
    /// nothing inside is stretched to a measuring frame (a stack pinned to
    /// the root's bottom spread its labels apart to fill 70% of the screen).
    private let container = UIView()
    /// Keeps the rendered preview's view models alive.
    private var renderResult: ComponentRenderResult?

    init(preview: DSL.Model.ContextMenu.Preview, viewModel: ComponentViewModelAbstract, hostView: UIView?) {
        self.preview = preview
        self.viewModel = viewModel
        self.hostView = hostView
        super.init(nibName: nil, bundle: nil)
        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var previewWidth: CGFloat = 0
    private var maxHeight: CGFloat = 600

    private func render() {
        guard let viewModel, let service = viewModel.componentService else { return }
        let screen = hostView?.window?.windowScene?.screen.bounds.size
            ?? hostView?.window?.bounds.size
            ?? CGSize(width: 390, height: 844)
        let width = CGFloat(preview.width ?? Double(screen.width - 32))

        view.backgroundColor = .systemBackground
        view.clipsToBounds = true
        container.isUserInteractionEnabled = false
        container.translatesAutoresizingMaskIntoConstraints = false

        var component = preview.component
        if let templateId = component.templateId, component.asPointer() != nil,
           let resolved = service.resolveTemplate(named: templateId) {
            component = resolved
        }
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        renderResult = service.renderComponent(
            component,
            superview: container,
            parentPath: viewModel.componentPath + ".contextMenuPreview",
            parentVariableStore: viewModel.variableStore,
            reuseViewModel: nil
        )
        // A root laid out with only a width (no bottom) still gives the
        // container its height.
        if let root = renderResult?.view {
            let bottom = root.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            bottom.priority = .defaultLow
            NSLayoutConstraint.activate([bottom, root.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)])
        }

        previewWidth = width
        maxHeight = screen.height * 0.7
        applyCornerRadius()
        if let fixed = preview.height {
            preferredContentSize = CGSize(width: width, height: CGFloat(fixed))
        } else {
            remeasure()
            // Bindings that still arrive on the next main-queue turns land
            // before the preview is shown (see `prepareForPresentation`).
            DispatchQueue.main.async { [weak self] in self?.remeasureBeforePresentation() }
        }
    }

    /// Called by the preview provider right before UIKit shows the preview:
    /// the last measurement, with every binding applied.
    func prepareForPresentation() {
        guard preview.height == nil else { return }
        remeasure()
    }

    private func remeasureBeforePresentation() {
        guard view.window == nil else { return }
        remeasure()
    }

    /// The content's height at the preview width: bound text and `isHidden`
    /// applied now (not on a later main-queue hop), multi-line labels settled,
    /// then the container's own height, capped at 70% of the screen.
    private func remeasure() {
        let width = previewWidth
        CCollectionCell.refreshForReuse(container)
        if view.window == nil {
            view.frame = CGRect(x: 0, y: 0, width: width, height: max(maxHeight * 3, 2000))
        }
        view.setNeedsLayout()
        view.layoutIfNeeded()
        container.settleWrappingLabels()
        view.layoutIfNeeded()
        let height = Self.previewHeight(content: container.bounds.height, width: width, maxHeight: maxHeight)
        if abs(preferredContentSize.height - height) > 0.5 || preferredContentSize.width != width {
            preferredContentSize = CGSize(width: width, height: height)
        }
    }

    /// The fitting height, capped; an empty measurement falls back to a square.
    nonisolated static func previewHeight(content: CGFloat, width: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let measured = content > 1 ? content : width
        return min(ceil(measured), maxHeight)
    }

    // MARK: - Corner radius

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        applyCornerRadius()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyCornerRadius()
    }

    /// `preview.cornerRadius`: this view's corners, and those of the system
    /// platter around it (its clipping ancestors with rounded corners).
    private func applyCornerRadius() {
        guard let radius = preview.cornerRadius.map({ CGFloat($0) }) else { return }
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        var ancestor = view.superview
        for _ in 0..<4 {
            guard let current = ancestor, !(current is UIWindow) else { break }
            if current.layer.cornerRadius > 0.5, abs(current.layer.cornerRadius - radius) > 0.01 {
                current.layer.cornerRadius = radius
            }
            ancestor = current.superview
        }
    }
}
