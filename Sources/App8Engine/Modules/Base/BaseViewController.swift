import UIKit
import Combine

@MainActor
protocol BaseViewControllerProtocol {
    var navBarIsUnderlined: Bool { get }
    var hasPresentedViewController: CurrentValueSubject<Bool, Never> { get }
}

@MainActor
class BaseViewController: UIViewController, BaseViewControllerProtocol {

    var hasNavigationBar: Bool { false }
    var navBarIsUnderlined: Bool { false }

    private let tapGR = UITapGestureRecognizer()

    let viewDidAppear = CurrentValueSubject<Bool, Never>(false)
    lazy var hasPresentedViewController = CurrentValueSubject<Bool, Never>(presentedViewController != nil)
    private(set) lazy var viewFocused: AnyPublisher<Bool, Never> = Publishers.CombineLatest(viewDidAppear, hasPresentedViewController)
        .map { $0 && !$1 }
        .eraseToAnyPublisher()
    
    private var cancellables = Set<AnyCancellable>()
    let context: App8Context
    private var keyboardService: KeyboardHeightServiceProtocol { context.keyboardService }
    private let bottomSafeAreaKeyboard = CurrentValueSubject<(CGFloat, KeyboardHeightAnimationModel?, Bool), Never>((0, nil, false))

    init(context: App8Context) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("BaseViewController does not support init(coder:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addGestureRecognizer(tapGR)
        tapGR.publisher(for: \.state)
            .filter { $0 == .ended }
            .sink { [weak self] _ in
                self?.view.endEditing(true)
            }
            .store(in: &cancellables)
        updateTheme()
        setupSafeAreaBindings()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        updateTheme()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateNavigationBar(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppear.send(true)
        if let presentingViewController = presentingViewController as? BaseViewControllerProtocol {
            presentingViewController.hasPresentedViewController.send(true)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewDidAppear.send(false)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        if let presentingViewController = presentingViewController as? BaseViewControllerProtocol {
            presentingViewController.hasPresentedViewController.send(false)
        } else if presentedViewController != nil {
            hasPresentedViewController.send(false)
        }
        super.dismiss(animated: flag, completion: completion)
    }
    
    // MARK: Navigation bar management

    func updateNavigationBar(_ animated: Bool) {
        self.navigationController?.setNavigationBarHidden(!hasNavigationBar, animated: animated)
        adjustNavBarShadowImage(image: navBarIsUnderlined ? nil : UIImage(), animated)
    }

    private func adjustNavBarShadowImage(image: UIImage?, _ animated: Bool) {
        guard let navBar = navigationController?.navigationBar else { return }
        let animatableUpdates: (() -> Void) = {
            navBar.shadowImage = image
        }
        if animated {
            let animation = CATransition()
            animation.duration = 0.3
            animation.type = CATransitionType.fade
            animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeOut)
            navBar.layer.add(animation, forKey: nil)
            UIView.animate(withDuration: 0.3, animations: animatableUpdates)
        }
        else {
            animatableUpdates()
        }
    }
    
    /**
     */
    func updateTheme() {
        
    }
    
    /// Base bottom inset to preserve independently of keyboard state.
    /// Subclasses override to contribute a persistent bottom additionalSafeAreaInset.
    func baseAdditionalBottomInset() -> CGFloat { 0 }

    /**
     */
    private func setupSafeAreaBindings() {
        bottomSafeAreaKeyboard
            .receive(on: DispatchQueue.main)
            .sink { [weak self] keyboardData in
                let bottomInset = keyboardData.0
                let animationModel = keyboardData.1
                let keyboardExpanded = keyboardData.2

                UIView.animate(
                    withDuration: animationModel?.duration ?? 0.15,
                    delay: .zero,
                    options: [animationModel?.curve ?? .curveEaseOut, .beginFromCurrentState],
                    animations: { [weak self] in
                        self?.additionalSafeAreaInsets.bottom = bottomInset + (self?.baseAdditionalBottomInset() ?? 0)
                        self?.keyboardAlongsideAnimation(keyboardExpanded: keyboardExpanded)
                        self?.view.layoutIfNeeded()
                    },
                    completion: nil)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Keyboard

    func setupKeyboardBindings() {
        keyboardService.keyboardAnimationItem
            .receive(on: DispatchQueue.main)
            .removeDuplicates { lhs, rhs in
                return lhs.height == rhs.height
            }
            .sink { [weak self] item in
                guard let self else { return }
                
                var keyboardExpanded = false
                var originalSafeAreaBottom = (self.view.safeAreaInsets.bottom - self.additionalSafeAreaInsets.bottom)
                if originalSafeAreaBottom < 0 {
                    originalSafeAreaBottom = self.view.safeAreaInsets.bottom
                }
                var newSafeAreaInset: CGFloat = 0
                if item.height > originalSafeAreaBottom {
                    newSafeAreaInset = item.height - originalSafeAreaBottom
                    keyboardExpanded = true
                }
                
                self.prepareForKeyboardToggle(
                    originalSafeAreaBottom: originalSafeAreaBottom,
                    newSafeAreaBottom: newSafeAreaInset,
                    keyboardHeight: item.height,
                    keyboardExpanded: keyboardExpanded)
                
                self.bottomSafeAreaKeyboard.send((newSafeAreaInset, item, keyboardExpanded))
            }
            .store(in: &cancellables)
    }
    
    func prepareForKeyboardToggle(originalSafeAreaBottom: CGFloat,
                                  newSafeAreaBottom: CGFloat,
                                  keyboardHeight: CGFloat,
                                  keyboardExpanded: Bool) {}

    func keyboardAlongsideAnimation(keyboardExpanded: Bool) {}
}
