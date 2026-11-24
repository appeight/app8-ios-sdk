import UIKit

/// Page dots in the iOS 26 style for media: a blurred capsule behind the
/// dots, the current dot solid and the others at half opacity, so it reads on
/// any photo. Dark look: a dark capsule with white dots; light look: a light
/// capsule with black dots (`look`; `automatic` follows the trait collection's
/// `userInterfaceStyle`). A tint color, when set, replaces the default color
/// of that kind of dot. Same metrics as the web renderer: a 26 pt tall
/// capsule, `pages * 16 + 10` wide, 7 pt dots 9 pt apart.
final class MediaPageControl: UIControl {

    static let dotSize: CGFloat = 7
    static let dotGap: CGFloat = 9
    static let height: CGFloat = 26

    var numberOfPages = 0 {
        didSet {
            guard numberOfPages != oldValue else { return }
            numberOfPages = max(0, numberOfPages)
            rebuildDots()
            invalidateIntrinsicContentSize()
            updateVisibility()
        }
    }

    var currentPage = 0 {
        didSet {
            guard currentPage != oldValue else { return }
            updateDotColors()
            accessibilityValue = pageDescription
        }
    }

    /// `automatic` (light or dark by the trait collection), `light` or `dark`.
    var look: DSL.Model.Component.PageControl.Look = .automatic {
        didSet { if look != oldValue { applyLook() } }
    }

    /// Whether the capsule and default dots currently draw dark.
    private(set) var drawsDark = false

    /// Color of the other dots; nil keeps the look's color at half opacity.
    var pageIndicatorTintColor: UIColor? {
        didSet { if pageIndicatorTintColor != oldValue { updateDotColors() } }
    }

    /// Color of the current dot; nil keeps the look's color (white on dark, black on light).
    var currentPageIndicatorTintColor: UIColor? {
        didSet { if currentPageIndicatorTintColor != oldValue { updateDotColors() } }
    }

    var hidesForSinglePage = true {
        didSet { updateVisibility() }
    }

    /// The page the dots show, kept within the page count.
    private var displayedPage: Int {
        numberOfPages > 0 ? max(0, min(currentPage, numberOfPages - 1)) : 0
    }

    private let blurView = UIVisualEffectView(effect: nil)
    private let dimView = UIView()
    private var dots: [CALayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        blurView.isUserInteractionEnabled = false
        blurView.clipsToBounds = true
        addSubview(blurView)
        dimView.isUserInteractionEnabled = false
        blurView.contentView.addSubview(dimView)
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        applyLook(force: true)
        updateVisibility()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (control: MediaPageControl, _: UITraitCollection) in
            control.applyLook()
        }
    }

    /// The dark look is today's media capsule (ultra-thin dark material under
    /// a 28 % black dim, white dots); the light one its mirror (ultra-thin
    /// light material under a 40 % white wash, black dots).
    private func applyLook(force: Bool = false) {
        let dark = look.isDark(for: traitCollection.userInterfaceStyle)
        guard force || dark != drawsDark else { return }
        drawsDark = dark
        blurView.effect = UIBlurEffect(style: dark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight)
        dimView.backgroundColor = dark ? UIColor.black.withAlphaComponent(0.28) : UIColor.white.withAlphaComponent(0.4)
        updateDotColors()
    }

    /// The look's dot color: white on the dark capsule, black on the light one.
    private var lookDotColor: UIColor { drawsDark ? .white : .black }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyLook()
    }

    override var intrinsicContentSize: CGSize {
        guard numberOfPages > 0 else { return CGSize(width: 0, height: Self.height) }
        return CGSize(width: CGFloat(numberOfPages) * 16 + 10, height: Self.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        dimView.frame = blurView.contentView.bounds
        blurView.layer.cornerRadius = bounds.height / 2
        blurView.layer.cornerCurve = .continuous

        let span = CGFloat(dots.count) * Self.dotSize + CGFloat(max(0, dots.count - 1)) * Self.dotGap
        var x = (bounds.width - span) / 2
        let y = (bounds.height - Self.dotSize) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for dot in dots {
            dot.frame = CGRect(x: x, y: y, width: Self.dotSize, height: Self.dotSize)
            x += Self.dotSize + Self.dotGap
        }
        CATransaction.commit()
    }

    private func rebuildDots() {
        dots.forEach { $0.removeFromSuperlayer() }
        dots = (0..<numberOfPages).map { _ in
            let dot = CALayer()
            dot.cornerRadius = Self.dotSize / 2
            layer.addSublayer(dot)
            return dot
        }
        updateDotColors()
        setNeedsLayout()
        accessibilityValue = pageDescription
    }

    private func updateDotColors() {
        let current = displayedPage
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        let currentColor = currentPageIndicatorTintColor ?? lookDotColor
        let otherColor = pageIndicatorTintColor ?? lookDotColor.withAlphaComponent(0.5)
        for (index, dot) in dots.enumerated() {
            dot.backgroundColor = (index == current ? currentColor : otherColor).cgColor
        }
        CATransaction.commit()
    }

    private func updateVisibility() {
        isHidden = numberOfPages == 0 || (hidesForSinglePage && numberOfPages <= 1)
    }

    private var pageDescription: String {
        numberOfPages > 0 ? "\(displayedPage + 1) / \(numberOfPages)" : ""
    }

    // MARK: - Interaction

    /// Like `UIPageControl`: a tap on the leading half goes back one page, on
    /// the trailing half forward one.
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        guard let touch, bounds.contains(touch.location(in: self)) else { return }
        let forward = touch.location(in: self).x > bounds.midX
        step(forward != (effectiveUserInterfaceLayoutDirection == .rightToLeft))
    }

    override func accessibilityIncrement() { step(true) }
    override func accessibilityDecrement() { step(false) }

    private func step(_ forward: Bool) {
        guard numberOfPages > 1 else { return }
        let target = max(0, min(numberOfPages - 1, displayedPage + (forward ? 1 : -1)))
        guard target != displayedPage else { return }
        currentPage = target
        sendActions(for: .valueChanged)
    }
}
