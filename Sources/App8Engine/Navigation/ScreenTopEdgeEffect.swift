import UIKit

/// The top scroll-edge effect under the status and navigation bar (iOS 26+).
///
/// UIKit's own `UIScrollEdgeEffect` shows as soon as anything sits under the
/// bar, so a screen that starts with an edge-to-edge photo showed a blurred
/// band over the photo at rest. App8 draws the effect itself instead: nothing
/// at rest, then it fades in over `ramp` points of scrolling once content
/// reaches the bar's bottom edge (see `edgeEffectStart`). Same rule as the web
/// renderer (`edgeEffectStart` / `TopEdgeEffect`) and Android's
/// `heroScrollDistance`.
@MainActor
final class ScreenTopEdgeEffect {
    enum Style: Equatable { case soft, hard }

    /// Points of scrolling over which the effect fades in.
    static let ramp: CGFloat = 16
    /// Extra height of the soft effect below the bar, where it fades out.
    static let softTail: CGFloat = 16

    /// A frame (in screen coordinates, at rest) that may start the effect.
    struct Frame: Equatable {
        var x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
        init(_ r: CGRect) { x = r.minX; y = r.minY; w = r.width; h = r.height }
        init(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) { self.x = x; self.y = y; self.w = w; self.h = h }
    }

    /// How far a hero keeps the effect away: the bottom of the tallest
    /// full-width view that starts at the screen's top edge (taller than the
    /// bar, shorter than 90% of the screen) minus the bar's bottom; 0 with none.
    static func heroScrollDistance(_ frames: [Frame], barBottom: CGFloat, screen: CGSize) -> CGFloat {
        var hero: CGFloat = -1
        for f in frames where f.y <= 0.5 && f.x <= 0.5 && f.w >= screen.width - 1
            && f.h > barBottom && f.h < screen.height * 0.9 {
            hero = max(hero, f.y + f.h)
        }
        return hero < 0 ? 0 : max(0, hero - barBottom)
    }

    /// How far the scroll view must scroll from rest before the effect starts:
    /// over a hero, until the hero's bottom reaches the bar's bottom; otherwise
    /// until the first content reaches it (0 when it starts under the bar).
    static func edgeEffectStart(_ frames: [Frame], barBottom: CGFloat, screen: CGSize) -> CGFloat {
        let hero = heroScrollDistance(frames, barBottom: barBottom, screen: screen)
        if hero > 0 { return hero }
        let top = frames.filter { $0.w > 0 && $0.h > 0 }.map(\.y).min()
        return top.map { max(0, $0 - barBottom) } ?? 0
    }

    /// The effect's opacity `scrolled` points from rest.
    static func visibility(scrolled: CGFloat, start: CGFloat) -> CGFloat {
        min(1, max(0, (scrolled - start) / ramp))
    }

    // MARK: - Instance

    let overlay = TopEdgeEffectView()
    private weak var scrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []
    private(set) var start: CGFloat = 0
    private var barBottom: CGFloat = 0
    private weak var host: UIView?
    private var needsMeasure = true

    /// Hosts the overlay above `content` in `host` and tracks `scrollView`.
    func attach(host: UIView, above content: UIView, scrollView: UIScrollView?, style: Style, barBottom: CGFloat, background: UIColor) {
        self.host = host
        if overlay.superview !== host {
            host.insertSubview(overlay, aboveSubview: content)
        } else if let index = host.subviews.firstIndex(of: overlay),
                  let contentIndex = host.subviews.firstIndex(of: content), index < contentIndex {
            host.insertSubview(overlay, aboveSubview: content)
        }
        overlay.configure(style: style, background: background)
        if scrollView !== self.scrollView {
            self.scrollView = scrollView
            observations = scrollView.map { sv in
                [
                    sv.observe(\.contentOffset, options: []) { [weak self] _, _ in
                        MainActor.assumeIsolated { self?.update() }
                    },
                    sv.observe(\.contentSize, options: []) { [weak self] _, _ in
                        MainActor.assumeIsolated {
                            self?.needsMeasure = true
                            self?.update()
                        }
                    }
                ]
            } ?? []
        }
        if barBottom != self.barBottom { self.barBottom = barBottom; needsMeasure = true }
        let height = barBottom + (style == .soft ? Self.softTail : 0)
        let frame = CGRect(x: 0, y: 0, width: host.bounds.width, height: height)
        if overlay.frame != frame { overlay.frame = frame }
        needsMeasure = true
        update()
    }

    func detach() {
        observations = []
        scrollView = nil
        overlay.removeFromSuperview()
    }

    /// Distance the tracked scroll view has scrolled from rest.
    private func scrolled(_ sv: UIScrollView) -> CGFloat {
        sv.contentOffset.y + sv.adjustedContentInset.top
    }

    private func update() {
        guard let host, let sv = scrollView else {
            overlay.alpha = 0
            return
        }
        if needsMeasure {
            needsMeasure = false
            let offset = scrolled(sv)
            let frames = Self.componentFrames(in: sv, to: host).map { r in
                Frame(x: r.minX, y: r.minY + offset, w: r.width, h: r.height)
            }
            start = Self.edgeEffectStart(frames, barBottom: barBottom, screen: host.bounds.size)
        }
        let alpha = Self.visibility(scrolled: scrolled(sv), start: start)
        if overlay.alpha != alpha { overlay.alpha = alpha }
    }

    /// Frames (in `target` coordinates) of the App8 components inside the
    /// scroll view, not looking into nested scroll views (a carousel counts by
    /// its own frame).
    static func componentFrames(in scrollView: UIScrollView, to target: UIView) -> [CGRect] {
        var result: [CGRect] = []
        func walk(_ view: UIView) {
            for sub in view.subviews where !sub.isHidden && sub.alpha > 0.01 {
                if sub is CViewProtocol, sub.bounds.width > 0, sub.bounds.height > 0 {
                    result.append(sub.convert(sub.bounds, to: target))
                }
                if sub is UIScrollView { continue }
                walk(sub)
            }
        }
        walk(scrollView)
        return result
    }
}

/// The drawn effect: soft = a blur and a fade of the screen's background
/// that end below the bar; hard = a near-opaque band with a hairline.
@MainActor
final class TopEdgeEffectView: UIView {
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    private let blurMask = GradientView()
    private let tint = GradientView()
    private let hairline = UIView()
    private(set) var style: ScreenTopEdgeEffect.Style = .soft
    private var background: UIColor = .systemBackground

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0
        addSubview(blur)
        addSubview(tint)
        addSubview(hairline)
        blur.mask = blurMask
        blurMask.gradient.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        blurMask.gradient.locations = [0, 0.55, 1]
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: TopEdgeEffectView, _) in
            self.applyColors()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(style: ScreenTopEdgeEffect.Style, background: UIColor) {
        guard style != self.style || background != self.background || tint.gradient.colors == nil else { return }
        self.style = style
        self.background = background
        blur.isHidden = style == .hard
        hairline.isHidden = style == .soft
        applyColors()
    }

    private func applyColors() {
        let base = background.resolvedColor(with: traitCollection)
        switch style {
        case .soft:
            tint.gradient.colors = [base.withAlphaComponent(0.8), base.withAlphaComponent(0.55), base.withAlphaComponent(0)].map(\.cgColor)
            tint.gradient.locations = [0, 0.6, 1]
        case .hard:
            tint.gradient.colors = [base.withAlphaComponent(0.92), base.withAlphaComponent(0.92)].map(\.cgColor)
            tint.gradient.locations = [0, 1]
            hairline.backgroundColor = traitCollection.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.15) : UIColor(white: 0, alpha: 0.12)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        blurMask.frame = blur.bounds
        tint.frame = bounds
        let px = 1 / max(1, traitCollection.displayScale)
        hairline.frame = CGRect(x: 0, y: bounds.height, width: bounds.width, height: px)
    }

    final class GradientView: UIView {
        override class var layerClass: AnyClass { CAGradientLayer.self }
        var gradient: CAGradientLayer { layer as! CAGradientLayer }
    }
}
