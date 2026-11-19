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

    /// Mean relative luminance of the scroll view's content in `rect` (its
    /// own coordinates), composited over `background`: 8 × 4 px rendered
    /// from the model layer tree, the scroll view only (no bars, no effect).
    static func luminance(of scrollView: UIScrollView, in rect: CGRect, over background: UIColor) -> CGFloat? {
        guard rect.width > 0, rect.height > 0, scrollView.window != nil else { return nil }
        let w = 8, h = 4
        let sx = CGFloat(w) / rect.width, sy = CGFloat(h) / rect.height
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { context in
            background.setFill()
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            // What is on screen: the scroll view's visible bounds, placed so
            // that `rect` (its own coordinates) fills the bitmap. In an app,
            // `layer.render(in:)` came back empty for this tree on iOS 26;
            // without a render server (tests) the snapshot fails and the
            // model layer tree is drawn instead.
            let b = scrollView.bounds
            let target = CGRect(x: (b.minX - rect.minX) * sx, y: (b.minY - rect.minY) * sy,
                                width: b.width * sx, height: b.height * sy)
            if !scrollView.drawHierarchy(in: target, afterScreenUpdates: false) {
                let ctx = context.cgContext
                ctx.scaleBy(x: sx, y: sy)
                ctx.translateBy(x: -rect.minX, y: -rect.minY)
                scrollView.layer.render(in: ctx)
            }
        }
        return image.cgImage.flatMap(BackdropLuminance.meanLuminance)
    }

    /// The colour behind the scroll view: the overlay's configured background.
    private static func screenBackground(_ host: UIView) -> UIColor? {
        host.subviews.compactMap { $0 as? TopEdgeEffectView }.first?.backgroundForSampling
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
        sampleContentIfNeeded(scrolled: scrolled(sv))
    }

    /// Scroll position and time of the last content sample (nil: sample again).
    private var sampledAt: CGFloat?
    private var sampledTime: CFTimeInterval = 0
    private var trailingSample: DispatchWorkItem?
    /// Points of scrolling between two samples of the content under the bar.
    static let sampleStep: CGFloat = 12
    /// Seconds between two samples, at most (a snapshot costs a few ms).
    static let sampleInterval: CFTimeInterval = 0.1
    /// A last sample this long after the scroll view stops moving.
    static let settleDelay: TimeInterval = 0.15

    /// Like the system effect, the blur and tint follow the content under the
    /// bar: dark over a dark section, light over a light one, whatever the
    /// app's appearance. Sampled (8 × 4 px, with hysteresis) while the effect
    /// shows, every `sampleStep` points and `sampleInterval` seconds of
    /// scrolling, and once more when scrolling settles: a snapshot shows the
    /// last frame on screen, so a jump (a scroll-to action) is judged again.
    private func sampleContentIfNeeded(scrolled: CGFloat) {
        guard overlay.alpha > 0, overlay.window != nil else { sampledAt = nil; return }
        trailingSample?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let sv = self.scrollView else { return }
            self.trailingSample = nil
            self.sampleContent(scrolled: self.scrolled(sv))
        }
        trailingSample = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
        if let last = sampledAt {
            if abs(scrolled - last) < Self.sampleStep { return }
            if CACurrentMediaTime() - sampledTime < Self.sampleInterval { return }
        }
        sampleContent(scrolled: scrolled)
    }

    private func sampleContent(scrolled: CGFloat) {
        guard overlay.alpha > 0, overlay.window != nil, let sv = scrollView, let host else { return }
        sampledAt = scrolled
        sampledTime = CACurrentMediaTime()
        let rect = overlay.convert(overlay.bounds, to: sv)
        let behind = Self.screenBackground(host) ?? .systemBackground
        guard let luminance = Self.luminance(of: sv, in: rect, over: behind) else { return }
        overlay.setContentDark(BackdropLuminance.nextDark(current: overlay.contentDark, luminance: luminance))
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
/// that end below the bar; hard = a near-opaque band with a hairline. Both
/// follow the content under the bar, dark or light (`setContentDark`).
@MainActor
final class TopEdgeEffectView: UIView {
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    private let blurMask = GradientView()
    private let tint = GradientView()
    private let hairline = UIView()
    private(set) var style: ScreenTopEdgeEffect.Style = .soft
    private var background: UIColor = .systemBackground
    /// The screen's background, which shows where the content is transparent.
    var backgroundForSampling: UIColor { background.resolvedColor(with: traitCollection) }

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

    /// The content under the bar is dark (sampled); nil before the first sample.
    private(set) var contentDark: Bool?

    func setContentDark(_ dark: Bool) {
        guard dark != contentDark else { return }
        contentDark = dark
        applyColors()
    }

    /// Light or dark from a colour's relative luminance.
    static func isDark(_ color: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        return BackdropLuminance.luminance(r: r, g: g, b: b) < (BackdropLuminance.darkBelow + BackdropLuminance.lightAbove) / 2
    }

    /// The colour the effect fades into: the screen's background when it
    /// matches the content under the bar (dark or light), else black or white.
    static func tintBase(background: UIColor, contentDark: Bool?) -> UIColor {
        guard let contentDark, contentDark != isDark(background) else { return background }
        return contentDark ? .black : .white
    }

    private func applyColors() {
        let base = Self.tintBase(background: background.resolvedColor(with: traitCollection), contentDark: contentDark)
        let dark = contentDark ?? Self.isDark(base)
        let appearance: UIUserInterfaceStyle = dark ? .dark : .light
        if blur.overrideUserInterfaceStyle != appearance { blur.overrideUserInterfaceStyle = appearance }
        switch style {
        case .soft:
            tint.gradient.colors = [base.withAlphaComponent(0.8), base.withAlphaComponent(0.55), base.withAlphaComponent(0)].map(\.cgColor)
            tint.gradient.locations = [0, 0.6, 1]
        case .hard:
            tint.gradient.colors = [base.withAlphaComponent(0.92), base.withAlphaComponent(0.92)].map(\.cgColor)
            tint.gradient.locations = [0, 1]
            hairline.backgroundColor = dark
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
