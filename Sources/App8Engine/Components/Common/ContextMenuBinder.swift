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
            previewProvider = { [weak self] in
                guard let self, let viewModel = self.viewModel else { return nil }
                return ContextMenuPreviewController(preview: preview, viewModel: viewModel, hostView: self.host)
            }
        } else {
            previewProvider = nil
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: previewProvider) { [weak self] _ in
            self?.makeMenu()
        }
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionCommitAnimating
    ) {
        guard let menu, !menu.onPreviewTap.isEmpty else { return }
        animator.preferredCommitStyle = .pop
        animator.addCompletion { [weak self] in
            self?.viewModel?.executeContextMenuActions(menu.onPreviewTap)
        }
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
/// `width` × `height` (defaults: screen width − 32; fitting height, ≤ 70%).
@MainActor
final class ContextMenuPreviewController: UIViewController {

    private let preview: DSL.Model.ContextMenu.Preview
    private weak var viewModel: ComponentViewModelAbstract?
    private weak var hostView: UIView?
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

    /// Union of the visible leaf views' frames in `container`, ignoring views
    /// stretched to the tall measuring frame.
    static func contentExtent(in container: UIView, tall: CGFloat) -> CGRect? {
        var result: CGRect?
        var stack: [UIView] = container.subviews
        while let v = stack.popLast() {
            if v.isHidden || v.alpha < 0.01 { continue }
            let frame = v.convert(v.bounds, to: container)
            if frame.height >= tall - 1 {
                stack.append(contentsOf: v.subviews)
                continue
            }
            if v.subviews.isEmpty || v is UILabel || v is UIImageView {
                if frame.width > 0, frame.height > 0 { result = result.map { $0.union(frame) } ?? frame }
            } else {
                stack.append(contentsOf: v.subviews)
            }
        }
        return result
    }

    private func render() {
        guard let viewModel, let service = viewModel.componentService else { return }
        let screen = hostView?.window?.windowScene?.screen.bounds.size
            ?? hostView?.window?.bounds.size
            ?? CGSize(width: 390, height: 844)
        let width = CGFloat(preview.width ?? Double(screen.width - 32))

        view.backgroundColor = .systemBackground
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
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        renderResult = service.renderComponent(
            component,
            superview: container,
            parentPath: viewModel.componentPath + ".contextMenuPreview",
            parentVariableStore: viewModel.variableStore,
            reuseViewModel: nil
        )
        // A root with only a width sits at the top; let its content grow past
        // the container while measuring (low priority, below compression).
        if let root = renderResult?.view {
            let bottom = root.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
            bottom.priority = UILayoutPriority(249)
            NSLayoutConstraint.activate([
                root.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor),
                bottom,
            ])
        }

        previewWidth = width
        maxHeight = screen.height * 0.7
        if let fixed = preview.height {
            preferredContentSize = CGSize(width: width, height: CGFloat(fixed))
        } else {
            remeasure()
            // Bound text and `isHidden` arrive on the next main-queue turns;
            // measure again so the preview grows to its full fitting height.
            DispatchQueue.main.async { [weak self] in self?.remeasure() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.remeasure() }
        }
    }

    private var previewWidth: CGFloat = 0
    private var maxHeight: CGFloat = 600

    /// The height of the laid-out content at the preview width (its visible
    /// extent plus the same margin below as above), capped at 70% of the screen.
    private func remeasure() {
        let width = previewWidth
        if view.window == nil {
            // Before presentation: lay out in a tall frame at the preview width.
            view.frame = CGRect(x: 0, y: 0, width: width, height: max(maxHeight * 3, 2000))
        }
        view.setNeedsLayout()
        view.layoutIfNeeded()
        view.layoutIfNeeded()
        var measured: CGFloat = 0
        // Content may overflow the shown container (low-priority bottom), so
        // its extent is the full content height either way.
        if let extent = Self.contentExtent(in: container, tall: container.bounds.height) {
            measured = extent.maxY + max(0, extent.minY)
        }
        if measured <= 1 { measured = width }
        let height = min(ceil(measured), maxHeight)
        if abs(preferredContentSize.height - height) > 0.5 || preferredContentSize.width != width {
            preferredContentSize = CGSize(width: width, height: height)
        }
    }
}
