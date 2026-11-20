import UIKit
import Combine

class CPageControlView: App8BaseView<DSL.Model.Component.PageControl.C>, CViewProtocol {

    weak var materialView: MaterialView?
    let contentView = UIView()
    /// The iOS 26 media look (dark blurred capsule, white dots) for every
    /// page control; the DSL tint colors, when set, color the dots.
    private let pageControl = MediaPageControl()

    override var intrinsicContentSource: UIView? { pageControl }

    private var viewModel: CPageControlViewModel?
    private var propertiesCancellable: AnyCancellable?
    private var variablesCancellable: AnyCancellable?

    // MARK: - Setup

    override func setup() {
        super.setup()

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()

        contentView.addSubview(pageControl)
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageControl.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            pageControl.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        pageControl.addTarget(self, action: #selector(pageValueChanged), for: .valueChanged)
    }

    // MARK: - Configure

    func configure(viewModel: CPageControlViewModel, superview: UIView? = nil, animated: Bool = true) {
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
        applyCurrentProperties()

        propertiesCancellable = viewModel.properties
            .receiveOnMain()
            .sink { [weak self] _ in
                self?.applyCurrentProperties()
            }

        variablesCancellable = viewModel.variablesChanged
            .receiveOnMain()
            .sink { [weak self] _ in
                self?.applyCurrentProperties()
            }
    }

    // MARK: - Properties

    private func applyCurrentProperties() {
        guard let vm = viewModel else { return }
        let props = vm.currentProperties

        if let expr = props.numberOfPages {
            if let val = vm.resolvePropertyToFloat(expr), val.isFinite {
                pageControl.numberOfPages = max(0, min(Int(saturating: val), EngineLimits.maxPageControlPages))
            }
        }

        if let expr = props.currentPage {
            if let val = vm.resolvePropertyToFloat(expr), val.isFinite {
                pageControl.currentPage = Int(saturating: val.rounded())
            }
        }

        pageControl.hidesForSinglePage = props.hidesForSinglePage ?? true
    }

    // MARK: - Interaction

    @objc private func pageValueChanged() {
        viewModel?.pageChanged.send(pageControl.currentPage)
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

        // A hex or a color expression resolved in this component's scope; an
        // unset or invalid value keeps the default white dots.
        pageControl.pageIndicatorTintColor = viewModel?.resolveColor(style?.pageIndicatorTintColor)
        pageControl.currentPageIndicatorTintColor = viewModel?.resolveColor(style?.currentPageIndicatorTintColor)
    }
}

// MARK: - StreamingUpdatable

extension CPageControlView: StreamingUpdatable {

    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CPageControlViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }

        self.viewModel = vm
        bindStyle(vm.style, animation: vm.animation)
        applyCurrentProperties()

        propertiesCancellable = vm.properties
            .receiveOnMain()
            .sink { [weak self] _ in
                self?.applyCurrentProperties()
            }
        variablesCancellable = vm.variablesChanged
            .receiveOnMain()
            .sink { [weak self] _ in
                self?.applyCurrentProperties()
            }
        return vm
    }
}
