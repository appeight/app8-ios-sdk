import Combine
import ObjectiveC
import UIKit

/// Applies the universal, expression-reactive props that live on every
/// component's `content` (`interaction` + `accessibility`) to its rendered
/// `UIView`. Called once per component from `App8Service.renderComponent`, after
/// the component's own `configure()` has run — so an explicit
/// `interaction.enabled` overrides the derived `isUserInteractionEnabled`
/// default (see `CView.shouldHandleTouches`).
///
/// Also owns `properties.isHidden` for every component (`bindHidden`). Pattern:
/// cache the expression, subscribe once to `viewModel.variablesChanged`, re-resolve on each tick. The
/// subscription is retained via an associated object on the view so it lives
/// exactly as long as the view.
@MainActor
enum CommonComponentProps {

    private static var cancellableKey: UInt8 = 0

    static func bind(view: UIView, viewModel: ComponentViewModelAbstract) {
        bindHidden(view: view, viewModel: viewModel)

        let interaction = viewModel.interactionProps
        let accessibility = viewModel.accessibilityProps

        let hasInteraction = interaction?.hasBindings ?? false
        let hasAccessibility = accessibility?.hasBindings ?? false
        guard hasInteraction || hasAccessibility else { return }

        // Static (non-expression) accessibility traits — applied once.
        if let traits = accessibility?.combinedTraits {
            view.accessibilityTraits = traits
        }

        // Initial apply runs synchronously (like `bindHidden`'s first update)
        // so the props are in effect the moment the view
        // is rendered — not deferred to the next run-loop turn.
        apply(interaction: interaction, accessibility: accessibility, to: view, viewModel: viewModel)

        // Reactive apply: re-resolve every expression-backed field whenever a
        // variable in scope changes.
        let cancellable = viewModel.variablesChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak view, weak viewModel] _ in
                guard let view, let viewModel else { return }
                apply(interaction: interaction, accessibility: accessibility, to: view, viewModel: viewModel)
            }

        objc_setAssociatedObject(view, &cancellableKey, cancellable, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static var hiddenCancellableKey: UInt8 = 0
    private static var hiddenRefreshKey: UInt8 = 0

    /// Re-applies a view's `isHidden` binding.
    private final class HiddenRefresher {
        let refresh: (_ animated: Bool) -> Void
        init(_ refresh: @escaping (_ animated: Bool) -> Void) { self.refresh = refresh }
    }

    /// `properties.isHidden` on any component: hidden views are not drawn,
    /// get no touches, are skipped by accessibility and take no space in a
    /// stack view (UIStackView collapses hidden arranged subviews). The
    /// wrapped form's `animation` animates later changes (`HiddenTransition`).
    private static func bindHidden(view: UIView, viewModel: ComponentViewModelAbstract) {
        let hasStateFlag = viewModel.declaresStateHiddenFlag
        guard hasStateFlag || !(viewModel.hiddenFlag ?? "").isEmpty else { return }
        func update(_ view: UIView, _ viewModel: ComponentViewModelAbstract, animated: Bool) {
            let hidden: Bool
            if let flag = viewModel.hiddenFlag?.trimmingCharacters(in: .whitespaces), !flag.isEmpty {
                hidden = flag.contains("{{")
                    ? viewModel.resolvePropertyToBool(flag) ?? false
                    : flag.lowercased() == "true" || flag == "1"
            } else {
                // A state without `isHidden` keeps the base value (none: shown).
                hidden = false
            }
            HiddenTransition.apply(hidden, to: view, animation: viewModel.hiddenAnimation, animated: animated)
        }
        update(view, viewModel, animated: false)
        objc_setAssociatedObject(view, &hiddenRefreshKey, HiddenRefresher { [weak view, weak viewModel] animated in
            guard let view, let viewModel else { return }
            update(view, viewModel, animated: animated)
        }, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        // Re-resolve on variable changes (expressions) and state changes
        // (a state override may set or clear `isHidden`).
        let cancellable = viewModel.variablesChanged.map { _ in () }
            .merge(with: viewModel.stateChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak view, weak viewModel] _ in
                guard let view, let viewModel else { return }
                update(view, viewModel, animated: true)
            }
        objc_setAssociatedObject(view, &hiddenCancellableKey, cancellable, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Collection cell bind / reuse: apply the item's `isHidden` now and at
    /// once (never animated), so the cell is measured with what it shows.
    static func refreshHiddenForReuse(_ view: UIView) {
        (objc_getAssociatedObject(view, &hiddenRefreshKey) as? HiddenRefresher)?.refresh(false)
    }

    private static func apply(
        interaction: DSL.Model.Interaction?,
        accessibility: DSL.Model.Accessibility?,
        to view: UIView,
        viewModel: ComponentViewModelAbstract
    ) {
        if let enabled = interaction?.enabled,
           let value = viewModel.resolvePropertyToBool(enabled) {
            view.isUserInteractionEnabled = value
        }
        if let clips = interaction?.clipsToBounds,
           let value = viewModel.resolvePropertyToBool(clips) {
            view.clipsToBounds = value
        }
        if let zIndex = interaction?.zIndex,
           let value = viewModel.resolvePropertyToFloat(zIndex) {
            view.layer.zPosition = value
        }

        guard let accessibility else { return }
        // Marking any a11y field implies this is an accessibility element unless
        // the author says otherwise.
        if accessibility.label != nil || accessibility.value != nil || accessibility.hint != nil {
            view.isAccessibilityElement = true
        }
        if let label = accessibility.label {
            view.accessibilityLabel = viewModel.resolvePropertyToString(label)
        }
        if let hint = accessibility.hint {
            view.accessibilityHint = viewModel.resolvePropertyToString(hint)
        }
        if let value = accessibility.value {
            view.accessibilityValue = viewModel.resolvePropertyToString(value)
        }
        if let isElement = accessibility.isElement,
           let value = viewModel.resolvePropertyToBool(isElement) {
            view.isAccessibilityElement = value
        }
        if let hidden = accessibility.hidden,
           let value = viewModel.resolvePropertyToBool(hidden) {
            view.accessibilityElementsHidden = value
        }
    }
}
