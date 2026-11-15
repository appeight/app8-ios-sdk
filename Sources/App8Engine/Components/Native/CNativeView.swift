//
//  CNativeView.swift
//  App8Engine
//

import Combine
import UIKit

/// Hosts a `native` component: the host factory's view when one is
/// registered for the module, else the DSL `fallback`, else nothing.
final class CNativeView: App8BaseView<NativeContent>, CViewProtocol {

    weak var materialView: MaterialView?
    let contentView = UIView()

    private var viewModel: CNativeViewModel?
    private(set) var nativeContext: App8NativeContext?
    private(set) var hostedView: UIView?
    private var lastProps: NSDictionary?
    private var variablesCancellable: AnyCancellable?
    private var visibilityTracker: NativeVisibilityTracker?

    /// Whether the component is on screen (see `NativeVisibility`).
    var isComponentVisible: Bool { visibilityTracker?.isVisible ?? false }

    var layoutModeId: String? { viewModel?.componentPath.split(separator: ".").last.map(String.init) }
    var layoutModeContext: App8LayoutMode? { viewModel?.service.context.layoutMode }

    override func setup() {
        super.setup()
        addSubview(contentView)
        contentView.cMakeEqualToSuperview()
    }

    func configure(viewModel: CNativeViewModel, superview: UIView? = nil, animated: Bool = true) {
        guard let superview = superview ?? self.superview else { return }
        self.viewModel = viewModel

        bindLayout(
            viewModel.layout,
            in: superview,
            viewRegistry: viewModel.service.componentRegistry.viewRegistry,
            parentComponentPath: viewModel.parentPath,
            keyboardService: viewModel.service.context.keyboardService,
            animated: animated
        )
        bindStyle(viewModel.style, animation: viewModel.animation)
        configureContent(viewModel: viewModel)
        visibilityTracker = NativeVisibilityTracker(view: self) { [weak self] visible in
            self?.visibilityChanged(visible)
        }
        if window != nil { NativeVisibility.invalidate() }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        // Leaving the window (screen torn down, re-render, cell removed):
        // `false` while the view is still intact.
        if newWindow == nil { visibilityTracker?.setNotVisible() }
        super.willMove(toWindow: newWindow)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Joining a window: wait for the screen lifecycle (screens are built
        // before they show); the next pass decides.
        if window != nil { NativeVisibility.invalidate() }
    }

    private func visibilityChanged(_ visible: Bool) {
        nativeContext?.updateVisibility(visible)
        viewModel?.handleVisibilityChange(visible)
    }

    private func configureContent(viewModel: CNativeViewModel) {
        let module = viewModel.module
        if let factory = NativeComponentRegistry.shared.factory(for: module) {
            let context = viewModel.makeNativeContext()
            nativeContext = context
            lastProps = context.props as NSDictionary
            let view = factory(context)
            contentView.addSubview(view)
            view.cMakeEqualToSuperview()
            hostedView = view

            variablesCancellable = viewModel.variablesChanged
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshProps() }
        } else if let fallback = viewModel.component.fallback {
            viewModel.service.renderComponent(
                fallback,
                superview: contentView,
                parentPath: viewModel.componentPath,
                parentVariableStore: viewModel.variableStore
            )
        } else {
            viewModel.service.context.logger.warning(
                "native.module.missing: no native component registered for '\(module)' and no fallback at '\(viewModel.componentPath)' — rendering an empty view"
            )
        }
    }

    /// Re-resolves props and pushes them to the host view when they changed.
    private func refreshProps() {
        guard let viewModel, let context = nativeContext else { return }
        let props = viewModel.resolvedProps()
        let dict = props as NSDictionary
        guard dict != lastProps else { return }
        lastProps = dict
        context.updateProps(props)
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
    }
}
