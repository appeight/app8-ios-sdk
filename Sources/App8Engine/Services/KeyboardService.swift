import UIKit
import Combine

@MainActor
protocol KeyboardHeightServiceProtocol: AnyObject {
    var keyboardFrame: AnyPublisher<CGRect, Never> { get }
    var keyboardAnimationItem: AnyPublisher<KeyboardHeightAnimationModel, Never> { get }
    var currentHeight: CGFloat { get }
    var plainAnimationItem: KeyboardHeightAnimationModel { get }

    func addViewForDismissTap(_ view: UIView)

    /// Returns a keyboard tracking view for the given container.
    /// The view's top anchor represents the keyboard top (or bottom of container when keyboard is hidden).
    func keyboardTrackingView(for container: UIView, ignoresSafeArea: Bool) -> UIView
}

struct KeyboardHeightAnimationModel {

    let height: CGFloat
    let frame: CGRect
    let duration: Double?
    let curve: UIView.AnimationOptions?

    @MainActor
    static func make(with notification: Notification) -> KeyboardHeightAnimationModel? {
        guard let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return nil }
        let height = UIScreen.main.bounds.intersection(frame).height
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        var curve: UIView.AnimationOptions?
        if let rawCurve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt {
            curve = UIView.AnimationOptions(rawValue: ((UInt(rawCurve << 16))))
        }
        return KeyboardHeightAnimationModel(height: height, frame: frame, duration: duration, curve: curve)
    }
}

@MainActor
final class KeyboardHeightService: KeyboardHeightServiceProtocol {

    var keyboardFrame: AnyPublisher<CGRect, Never> {
        keyboardAnimationItem.map(\.frame).eraseToAnyPublisher()
    }

    private(set) lazy var keyboardAnimationItem: AnyPublisher<KeyboardHeightAnimationModel, Never> = getKeyboardHeightAnimationModel()
        .share()
        .eraseToAnyPublisher()

    private(set) var currentHeight: CGFloat = .zero
    private(set) var currentFrame: CGRect = .zero

    var plainAnimationItem: KeyboardHeightAnimationModel {
        return KeyboardHeightAnimationModel(height: currentHeight, frame: currentFrame, duration: .zero, curve: [])
    }

    private let tapGR = UITapGestureRecognizer()
    private var cancellables = Set<AnyCancellable>()

    /// Keyboard tracking views keyed by container view's object identifier.
    private var trackingViews: [ObjectIdentifier: KeyboardTrackingView] = [:]

    init() {
        setup()
        setupBindings()
    }
    
    // MARK: - Public
    
    func addViewForDismissTap(_ view: UIView) {
        view.addGestureRecognizer(tapGR)
    }
    
    // MARK: - Private
    
    private func getKeyboardHeightAnimationModel() -> AnyPublisher<KeyboardHeightAnimationModel, Never> {
        let keyboardWillShow = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { KeyboardHeightAnimationModel.make(with: $0) }
        
        let keyboardWillHide = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillHideNotification)
            .compactMap { KeyboardHeightAnimationModel.make(with: $0) }
        
        let keyboardWillChangeFrame = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .compactMap { KeyboardHeightAnimationModel.make(with: $0) }
        
        return Publishers.Merge3(keyboardWillShow, keyboardWillHide, keyboardWillChangeFrame)
            .eraseToAnyPublisher()
    }
    
    private func setup() {
        tapGR.cancelsTouchesInView = false
    }
    
    private func setupBindings() {
        tapGR.publisher(for: \.state)
            .filter { $0 == .ended }
            .sink { [weak self] _ in
                self?.tapGR.view?.endEditing(true)
            }
            .store(in: &cancellables)

        keyboardAnimationItem
            .sink { [weak self] animationItem in
                self?.currentFrame = animationItem.frame
                self?.currentHeight = animationItem.height
            }
            .store(in: &cancellables)
    }

    // MARK: - Keyboard Tracking View

    func keyboardTrackingView(for container: UIView, ignoresSafeArea: Bool) -> UIView {
        // Purge stale entries (container deallocated or tracking view removed).
        trackingViews = trackingViews.filter { $0.value.superview != nil }

        let key = ObjectIdentifier(container)

        if let existing = trackingViews[key], existing.superview === container {
            return existing
        }

        let trackingView = KeyboardTrackingView(ignoresSafeArea: ignoresSafeArea)
        trackingView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(trackingView)

        NSLayoutConstraint.activate([
            trackingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            trackingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            trackingView.heightAnchor.constraint(equalToConstant: 0)
        ])

        let bottomAnchor = ignoresSafeArea ? container.bottomAnchor : container.safeAreaLayoutGuide.bottomAnchor
        trackingView.bottomConstraint = trackingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        trackingView.bottomConstraint?.isActive = true

        trackingView.subscribe(to: keyboardAnimationItem, container: container)

        trackingViews[key] = trackingView
        return trackingView
    }
}

/// A zero-height view that tracks keyboard position.
/// Its top anchor represents the top of the keyboard (or bottom of container when hidden).
@MainActor
final class KeyboardTrackingView: UIView {

    var bottomConstraint: NSLayoutConstraint?
    private let ignoresSafeArea: Bool
    private var cancellable: AnyCancellable?

    init(ignoresSafeArea: Bool) {
        self.ignoresSafeArea = ignoresSafeArea
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func subscribe(to publisher: AnyPublisher<KeyboardHeightAnimationModel, Never>, container: UIView) {
        cancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak container] animationItem in
                guard let self, let container else { return }
                self.updatePosition(animationItem: animationItem, container: container)
            }
    }

    private func updatePosition(animationItem: KeyboardHeightAnimationModel, container: UIView) {
        // Offset from bottom: keyboard height minus safe area (unless ignoring it).
        let safeAreaBottom = ignoresSafeArea ? 0 : container.safeAreaInsets.bottom
        let offset = max(0, animationItem.height - safeAreaBottom)

        bottomConstraint?.isActive = false

        let bottomAnchor = ignoresSafeArea ? container.bottomAnchor : container.safeAreaLayoutGuide.bottomAnchor
        bottomConstraint = self.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -offset)
        bottomConstraint?.isActive = true

        let duration = animationItem.duration ?? 0.25
        let options = animationItem.curve ?? [.curveEaseInOut]

        UIView.animate(withDuration: duration, delay: 0, options: options) {
            container.layoutIfNeeded()
        }
    }
}
