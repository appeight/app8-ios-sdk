import UIKit

/// Page dots in the iOS 26 style for media: a blurred dark capsule behind
/// white dots, the current dot fully white and the others at half opacity,
/// so it reads on any photo. A tint color, when set, replaces the white of
/// that kind of dot. Same metrics as the web
/// renderer: a 26 pt tall capsule, `pages * 16 + 10` wide, 7 pt dots 9 pt apart.
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

    /// Color of the other dots; nil keeps white at half opacity.
    var pageIndicatorTintColor: UIColor? {
        didSet { if pageIndicatorTintColor != oldValue { updateDotColors() } }
    }

    /// Color of the current dot; nil keeps white.
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

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let dimView = UIView()
    private var dots: [CALayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        blurView.isUserInteractionEnabled = false
        blurView.clipsToBounds = true
        addSubview(blurView)
        dimView.isUserInteractionEnabled = false
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        blurView.contentView.addSubview(dimView)
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        updateVisibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
        let currentColor = currentPageIndicatorTintColor ?? .white
        let otherColor = pageIndicatorTintColor ?? UIColor.white.withAlphaComponent(0.5)
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
