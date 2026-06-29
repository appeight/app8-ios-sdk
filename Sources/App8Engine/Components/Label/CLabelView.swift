import UIKit
import Combine

class CLabelView: App8BaseView<DSL.Model.Component.Label.C>, CViewProtocol {

    private var viewModel: CLabelViewModel?
    var layoutModeId: String? { viewModel?.componentPath.split(separator: ".").last.map(String.init) }
    var layoutModeContext: App8LayoutMode? { viewModel?.service.context.layoutMode }
    private var propertiesCancellable: AnyCancellable?
    private var variablesCancellable: AnyCancellable?
    weak var materialView: MaterialView?
    let contentView = UIView()
    private let label = UILabel()

    override var intrinsicContentSource: UIView? { label }

    // MARK: - isHidden Expression
    private var isHiddenExpression: String?
    private var lastIsHidden: Bool?

    // MARK: - Background Color (per-property animation)
    private var backgroundColorAnimation: DSL.Model.Animation.Inline?
    private var lastBackgroundColor: UIColor??
    private var hasAppliedBackgroundColorOnce = false

    // MARK: - Text Attributes (letter-spacing / line-height)
    private var textAttributes: [NSAttributedString.Key: Any] = [:]

    // MARK: - Inline span overrides (per-character-range style)
    private var currentSpans: [DSL.Model.Component.Label.Properties.Span]?

    // MARK: - Manual autoshrink (binary-search shrink-to-fit)
    // UILabel.adjustsFontSizeToFitWidth is unreliable for multi-line + attributed
    // text with custom paragraph styles, so we take it over.
    private struct AutoshrinkConfig {
        let maxLines: Int  // 0 = unbounded
        let minimumScaleFactor: CGFloat
    }
    private var autoshrinkConfig: AutoshrinkConfig?
    private var autoshrinkSource: NSAttributedString?
    private var autoshrinkLastWidth: CGFloat = -1
    private var autoshrinkAppliedScale: CGFloat = 1.0

    // MARK: - Touch handling
    private var tapGesture: UITapGestureRecognizer?

    override func setup() {
        super.setup()

        // Labels default to non-interactive; enabled below if actions/triggers exist
        isUserInteractionEnabled = false

        // Don't clip — swashed/calligraphic glyphs and pronounced descenders
        // can extend beyond the label's typographic bounds, and we want them
        // visible rather than chopped at the bounding rect.
        clipsToBounds = false
        contentView.clipsToBounds = false
        label.clipsToBounds = false

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()

        contentView.addSubview(label)
        label.cMakeEqualToSuperview()
    }

    // UILabel.intrinsicContentSize reports a single-line size unless
    // `preferredMaxLayoutWidth` is set, so multi-line labels (numberOfLines = 0,
    // text containing `\n`, or wrapping text) under-report their height and get
    // truncated when their container is under vertical pressure. Sync the
    // preferred width to the laid-out bounds so intrinsic stays correct.
    override func layoutSubviews() {
        super.layoutSubviews()
        // Wrap at the nearest CONTENT-INDEPENDENT boundary (see
        // `availableWrapWidth`). A center-aligned stack doesn't pin a child's
        // cross-axis width, so a multi-line label left to its own devices sizes
        // to its full SINGLE-LINE width and overflows its container — UIKit then
        // renders it on one truncated line. And syncing `preferredMaxLayoutWidth`
        // from the label's own bounds has two stable fixed points (wrapped vs.
        // single-line overflow), so the same text renders wrapped on one launch
        // and truncated on the next. The boundary width collapses that to one
        // fixed point.
        //
        // Use the boundary DIRECTLY — never `min(label.bounds.width, boundary)`.
        // In a content-hugging chain (a badge/chip, or a centerX stack of link
        // rows) the label's own bounds IS the squeezed value, so taking the min
        // would feed the collapse loop back in and wrap the text one character
        // per line. The boundary is already the true cap.
        let available = availableWrapWidth()
        if available > 0.5, abs(label.preferredMaxLayoutWidth - available) > 0.5 {
            label.preferredMaxLayoutWidth = available
            label.invalidateIntrinsicContentSize()
            invalidateIntrinsicContentSize()
        }
        performAutoshrinkIfNeeded()
    }

    /// The widest this label may grow before it must wrap: the narrowest
    /// *content-independent* width among the label's own view and its ancestors.
    ///
    /// We must NOT clamp to just any ancestor. A content-hugging container — a
    /// badge/chip pinned on only one edge, or an intrinsic-width stack — derives
    /// its width FROM the label. Clamping the wrap width to it feeds a collapse
    /// loop: narrower wrap → narrower container → narrower wrap → … until the
    /// label renders one character per line. So we skip those and clamp only to
    /// boundaries whose width is fixed independent of their content: an explicit
    /// width, both horizontal edges pinned to a content-independent parent, a
    /// frame-driven root, or the window. The genuinely bounded container (a stack
    /// pinned to the screen margins, or the device-sized root) is selected; the
    /// hugging containers between it and the label are ignored.
    ///
    /// Returns 0 before anything has a real width (we're not laid out yet).
    private func availableWrapWidth() -> CGFloat {
        var width = CGFloat.greatestFiniteMagnitude
        var node: UIView? = self
        var isSelf = true
        while let view = node {
            let w = view.bounds.width
            if w > 0.5 {
                // `self` counts only via an explicit width of its own. A both-edges
                // pin on self just tracks a (possibly hugging) parent — that case is
                // handled by walking up to the parent.
                let counts = isSelf ? hasExplicitWidthConstraint(view)
                                    : hasContentIndependentWidth(view)
                if counts { width = min(width, w) }
            }
            if view is UIWindow { break }
            node = view.superview
            isSelf = false
        }
        return width == .greatestFiniteMagnitude ? 0 : width
    }

    /// True when `view` carries its own width constraint (a constant, or a
    /// fraction of another view) — its width does not depend on its content.
    private func hasExplicitWidthConstraint(_ view: UIView) -> Bool {
        for c in view.constraints where c.isActive {
            if (c.firstItem === view && c.firstAttribute == .width) ||
               (c.secondItem === view && c.secondAttribute == .width) {
                return true
            }
        }
        return false
    }

    /// True when `view`'s width is fixed independent of its content: the window,
    /// a frame-driven (autoresizing) root, an explicit width, or both horizontal
    /// edges pinned with an equal relation to a parent that is itself
    /// content-independent. Inequality edge pins (`>=` / `<=`) and single-edge
    /// pins do NOT count — those let the view hug its content.
    private func hasContentIndependentWidth(_ view: UIView) -> Bool {
        if view is UIWindow { return true }
        if view.translatesAutoresizingMaskIntoConstraints { return true }
        if hasExplicitWidthConstraint(view) { return true }
        guard let superview = view.superview else { return false }
        var pinnedLeading = false
        var pinnedTrailing = false
        // Cross-view edge constraints install on the nearest common ancestor —
        // for a child pinned to its superview, that's the superview.
        for c in superview.constraints where c.isActive && c.relation == .equal {
            func note(_ item: AnyObject?, _ attr: NSLayoutConstraint.Attribute) {
                guard item === view else { return }
                if attr == .leading || attr == .left { pinnedLeading = true }
                if attr == .trailing || attr == .right { pinnedTrailing = true }
            }
            note(c.firstItem, c.firstAttribute)
            note(c.secondItem, c.secondAttribute)
        }
        guard pinnedLeading, pinnedTrailing else { return false }
        return hasContentIndependentWidth(superview)
    }

    func configure(viewModel: CLabelViewModel, superview: UIView? = nil, animated: Bool = true) {
        self.viewModel = viewModel

        guard let superview = superview ?? self.superview else {
            return
        }
        bindLayout(viewModel.layout, in: superview, viewRegistry: viewModel.service.componentRegistry.viewRegistry, parentComponentPath: viewModel.parentPath, keyboardService: viewModel.service.context.keyboardService, animated: animated)
        bindStyle(viewModel.style, animation: viewModel.animation)
        bindProperties(viewModel.propertiesWithVariables)
        bindIsHidden(viewModel: viewModel)
        setupTouchHandlingIfNeeded()
    }

    // MARK: - isHidden Expression

    private func bindIsHidden(viewModel: CLabelViewModel) {
        let props = viewModel.currentProperties
        isHiddenExpression = props.isHidden?.contains("{{") == true ? props.isHidden : nil
        guard isHiddenExpression != nil else { return }

        variablesCancellable = viewModel.variablesChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIsHidden()
            }
        updateIsHidden()
    }

    private func updateIsHidden() {
        guard let viewModel = viewModel,
              let expression = isHiddenExpression else { return }
        let hidden = viewModel.resolvePropertyToBool(expression) ?? false
        guard lastIsHidden != hidden else { return }
        lastIsHidden = hidden
        self.isHidden = hidden
    }

    // MARK: - Touch Handling

    private var shouldHandleTouches: Bool {
        guard let viewModel = viewModel else { return false }
        return viewModel.component.triggers != nil || viewModel.component.actions != nil
    }

    private func setupTouchHandlingIfNeeded() {
        guard shouldHandleTouches, tapGesture == nil else { return }
        isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        tapGesture = tap
    }

    @objc private func handleTap() {
        viewModel?.executeAction(for: .tap)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard shouldHandleTouches else { return }
        viewModel?.fireTrigger(.touchDown)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard shouldHandleTouches else { return }
        viewModel?.fireTrigger(.touchUp)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        guard shouldHandleTouches else { return }
        viewModel?.fireTrigger(.touchUp)
    }

    /// Subscribe to properties changes for text updates (re-resolves when variables change)
    private func bindProperties(_ propertiesPublisher: AnyPublisher<DSL.Model.Component.Label.Properties, Never>) {
        propertiesCancellable?.cancel()
        propertiesCancellable = propertiesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] properties in
                self?.applyProperties(properties)
            }
    }

    /// Apply properties to UI, resolving any {{expressions}} in text
    private func applyProperties(_ properties: DSL.Model.Component.Label.Properties) {
        // Capture spans before setLabelText so it can apply per-range overrides.
        currentSpans = properties.spans
        // Cache the per-property animation descriptor (if supplied via the
        // wrapped form) once per properties update.
        backgroundColorAnimation = properties.backgroundColor?.animation?.inlineOrNil
        guard !(viewModel?.service.context.layoutMode.isEnabled == true) else {
            // Show text at reduced opacity so layout structure is visible.
            // Setting text = nil collapses UILabel.intrinsicContentSize to zero,
            // which makes the label invisible in layout mode.
            // If resolved is empty (e.g. unresolvable {{item.label}} template var),
            // fall back to the raw DSL string so the label keeps non-zero intrinsic width.
            let resolved = viewModel?.resolveLocalizedToString(properties.text) ?? properties.text.rawValue
            setLabelText(resolved.isEmpty ? properties.text.rawValue : resolved)
            label.textColor = UIColor.label.withAlphaComponent(0.4)
            return
        }
        let resolved = viewModel?.resolveLocalizedToString(properties.text) ?? properties.text.rawValue
        setLabelText(resolved)
        applyBackgroundColor(properties.backgroundColor?.value)
    }

    /// Resolve and apply the background color expression. First apply is
    /// instantaneous; subsequent variable-driven changes route through
    /// `AnimationRunner` using the per-property animation descriptor (or
    /// no animation when none was supplied — matches historic behavior).
    private func applyBackgroundColor(_ expression: String?) {
        let color = expression.flatMap { resolvedExpr -> UIColor? in
            guard let resolved = viewModel?.resolvePropertyToString(resolvedExpr) else { return nil }
            return UIColor(withHexString: resolved)
        }
        // Skip when nothing changed to avoid an unnecessary animation pass.
        if let last = lastBackgroundColor, last == color { return }
        lastBackgroundColor = .some(color)
        let isFirstApply = !hasAppliedBackgroundColorOnce
        hasAppliedBackgroundColorOnce = true
        let animation = isFirstApply ? nil : backgroundColorAnimation
        AnimationRunner.run(
            animation: animation,
            additionalOptions: [.allowUserInteraction],
            viewBlock: { [self] in
                self.backgroundColor = color
            }
        )
    }

    /// Apply text to the label, using attributed string when letter-spacing,
    /// line-height, or per-range span overrides are set.
    private func setLabelText(_ text: String) {
        let hasSpans = (currentSpans?.isEmpty == false)
        let needsAttributed = !textAttributes.isEmpty || hasSpans || autoshrinkConfig != nil
        if !needsAttributed {
            label.attributedText = nil
            label.text = text
            autoshrinkSource = nil
        } else {
            // Bake the base font into the attributed string so that:
            // (1) autoshrink can scale every range uniformly, and
            // (2) ranges without an explicit .font still render correctly when
            //     UILabel reads from attributedText rather than `font`.
            var baseAttrs = textAttributes
            if baseAttrs[.font] == nil, let font = label.font {
                baseAttrs[.font] = font
            }
            let attributed = NSMutableAttributedString(string: text, attributes: baseAttrs)
            if let spans = currentSpans, !spans.isEmpty {
                applySpanOverrides(spans, to: attributed)
            }
            label.attributedText = attributed
            if autoshrinkConfig != nil {
                autoshrinkSource = attributed.copy() as? NSAttributedString
                autoshrinkLastWidth = -1
                autoshrinkAppliedScale = 1.0
            } else {
                autoshrinkSource = nil
            }
        }
        // Seed preferredMaxLayoutWidth so multi-line intrinsic reports correct
        // height before the first layout pass establishes bounds. `layoutSubviews`
        // refines it to the actual width once we have one. Prefer the bounded
        // ancestor's width (the device-sized screen container) when we're already
        // installed — on Mac Catalyst `UIScreen.main.bounds.width` is the whole
        // display, which would seed a single-line/overflow layout that then sticks.
        if label.bounds.width <= 0, label.preferredMaxLayoutWidth <= 0 {
            let seed = availableWrapWidth()
            label.preferredMaxLayoutWidth = seed > 0.5 ? seed : UIScreen.main.bounds.width
        }
        invalidateIntrinsicContentSize()
        // If we already know our width (e.g. mid-streaming update), apply the
        // shrink right away so we don't show a one-frame oversize flash.
        if autoshrinkConfig != nil, label.bounds.width > 0 {
            performAutoshrinkIfNeeded()
        }
    }

    /// Apply each span's overrides on top of the base attributes. Out-of-range
    /// indices clamp silently. Spans win over base in their range — last span
    /// in the array wins on overlap.
    private func applySpanOverrides(
        _ spans: [DSL.Model.Component.Label.Properties.Span],
        to attributed: NSMutableAttributedString
    ) {
        let totalLength = attributed.length
        let baseSize = label.font?.pointSize ?? 17
        for span in spans {
            let from = max(0, min(span.from, totalLength))
            let to = max(from, min(span.to, totalLength))
            guard to > from else { continue }
            let range = NSRange(location: from, length: to - from)
            if let family = span.fontFamily, let font = UIFont(name: family, size: baseSize) {
                attributed.addAttribute(.font, value: font, range: range)
            }
            if let hex = span.color, let color = UIColor(withHexString: hex) {
                attributed.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
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

        // Applied always, so font/size/numberOfLines are correct in layout mode too.
        if let textModel = style?.text {
            applyTextModel(textModel)
        }
    }

    private func applyTextModel(_ textModel: DSL.Model.Style.TextModel) {
        if let alignment = textModel.alignment {
            label.textAlignment = alignment.ui
        }

        // Color is skipped in layout mode; applyProperties sets a semi-transparent color instead.
        if !(viewModel?.service.context.layoutMode.isEnabled == true), let themedColor = textModel.color {
            label.textColor = themedColor.ui
        }

        label.font = textModel.resolveUIFont()
        let maxLines = textModel.numberOfLines ?? 0
        label.numberOfLines = maxLines
        if let lineBreakMode = textModel.lineBreakMode {
            label.lineBreakMode = lineBreakMode.ui
        }
        // We take over UILabel's autoshrink because it doesn't work reliably for
        // multi-line attributed text with custom paragraph styles.
        label.adjustsFontSizeToFitWidth = false
        if textModel.adjustsFontSizeToFitWidth == true {
            let minScale = max(0.05, min(1.0, textModel.minimumScaleFactor ?? 0.5))
            autoshrinkConfig = AutoshrinkConfig(maxLines: maxLines, minimumScaleFactor: minScale)
        } else {
            autoshrinkConfig = nil
            autoshrinkSource = nil
            autoshrinkLastWidth = -1
            autoshrinkAppliedScale = 1.0
        }
        textAttributes = buildTextAttributes(for: textModel)

        if let currentText = label.attributedText?.string ?? label.text {
            setLabelText(currentText)
        }
    }

    /// Compute NSAttributedString attributes for letter-spacing and line-height.
    /// Returns empty when neither is configured (caller then uses plain text).
    private func buildTextAttributes(for textModel: DSL.Model.Style.TextModel) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [:]

        if let letterSpacing = textModel.letterSpacing, letterSpacing.type == .fixed {
            attrs[.kern] = letterSpacing.value
        }

        // Underline/strikethrough are added before the `lineHeight` early-return
        // below so they survive the `.auto` case.
        if textModel.underline == true {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if textModel.strikethrough == true {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        if let lineHeight = textModel.lineHeight {
            let paragraphStyle = NSMutableParagraphStyle()
            switch lineHeight.type {
            case .fixed:
                paragraphStyle.minimumLineHeight = lineHeight.value
                paragraphStyle.maximumLineHeight = lineHeight.value
            case .multiplier:
                paragraphStyle.lineHeightMultiple = lineHeight.value
            case .interLineSpacing:
                paragraphStyle.lineSpacing = lineHeight.value
            case .fontSizeFraction:
                paragraphStyle.lineSpacing = textModel.fontSize * lineHeight.value
            case .auto:
                // No paragraph style needed
                return attrs
            }
            if let alignment = textModel.alignment {
                paragraphStyle.alignment = alignment.ui
            }
            attrs[.paragraphStyle] = paragraphStyle
        }

        return attrs
    }

    // MARK: - Manual Autoshrink

    /// Re-runs the binary-search shrink-to-fit pass when the available width
    /// has changed. Cheap when the width is unchanged — guarded with
    /// `autoshrinkLastWidth`.
    private func performAutoshrinkIfNeeded() {
        guard let config = autoshrinkConfig, let source = autoshrinkSource else { return }
        let width = label.bounds.width
        guard width > 0.5 else { return }
        if abs(width - autoshrinkLastWidth) < 0.5 { return }
        autoshrinkLastWidth = width

        // Fast path: unscaled text already fits.
        if attributedFits(source, width: width, maxLines: config.maxLines) {
            if autoshrinkAppliedScale != 1.0 {
                autoshrinkAppliedScale = 1.0
                label.attributedText = source
            }
            return
        }

        // Binary search the largest scale that fits within the line cap.
        // 14 iterations across [minScale, 1.0] resolves to better than 1e-4 —
        // well below any visually meaningful threshold.
        var lo = config.minimumScaleFactor
        var hi: CGFloat = 1.0
        var best = config.minimumScaleFactor
        var bestFits = false
        for _ in 0..<14 {
            let mid = (lo + hi) / 2
            let candidate = scaled(source, by: mid)
            if attributedFits(candidate, width: width, maxLines: config.maxLines) {
                best = mid
                bestFits = true
                lo = mid
            } else {
                hi = mid
            }
        }
        // If nothing in the search range fits (even at minScale), pin to
        // minScale and let UILabel truncate the overflow.
        let appliedScale = bestFits ? best : config.minimumScaleFactor
        autoshrinkAppliedScale = appliedScale
        label.attributedText = scaled(source, by: appliedScale)
    }

    /// Produce a uniformly scaled copy of `source` — every `.font` run gets a
    /// proportionally smaller point size, and `.paragraphStyle` line metrics
    /// that are expressed as absolute lengths (fixed line height, line spacing)
    /// are scaled too. `lineHeightMultiple` is a ratio so it stays as-is.
    private func scaled(_ source: NSAttributedString, by scale: CGFloat) -> NSAttributedString {
        if scale >= 0.9995 { return source }
        let m = NSMutableAttributedString(attributedString: source)
        let fullRange = NSRange(location: 0, length: m.length)
        m.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            if let font = value as? UIFont {
                m.addAttribute(.font, value: font.withSize(font.pointSize * scale), range: range)
            }
        }
        m.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
            guard let paragraph = value as? NSParagraphStyle,
                  let mutable = paragraph.mutableCopy() as? NSMutableParagraphStyle else { return }
            if mutable.minimumLineHeight > 0 { mutable.minimumLineHeight *= scale }
            if mutable.maximumLineHeight > 0 { mutable.maximumLineHeight *= scale }
            if mutable.lineSpacing > 0 { mutable.lineSpacing *= scale }
            m.addAttribute(.paragraphStyle, value: mutable, range: range)
        }
        return m
    }

    /// Returns true when laying out `attributed` at the given width fits within
    /// `maxLines` (where 0 means "no cap"). Uses NSLayoutManager directly so
    /// line counting accounts for paragraph-style line metrics and Unicode
    /// word-wrap rules — `boundingRect(...).height / lineHeight` is too crude.
    private func attributedFits(_ attributed: NSAttributedString, width: CGFloat, maxLines: Int) -> Bool {
        let cap = maxLines > 0 ? maxLines : Int.max
        let storage = NSTextStorage(attributedString: attributed)
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        container.lineBreakMode = .byWordWrapping
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)

        var lineCount = 0
        var glyphIndex = 0
        let totalGlyphs = manager.numberOfGlyphs
        while glyphIndex < totalGlyphs {
            var lineRange = NSRange()
            _ = manager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            glyphIndex = NSMaxRange(lineRange)
            lineCount += 1
            if lineCount > cap { return false }
        }
        return lineCount <= cap
    }

}

// MARK: - StreamingUpdatable

extension CLabelView: StreamingUpdatable {

    /// Updates text and style in-place for a streaming diff hit (same id, same type).
    /// Does NOT rebind layout — constraints are preserved as-is.
    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CLabelViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }

        self.viewModel = vm
        bindStyle(vm.style, animation: vm.animation)

        let currentProps = vm.currentProperties
        if animated {
            UIView.transition(with: self, duration: 0.2, options: [.transitionCrossDissolve]) {
                self.applyProperties(currentProps)
            }
        } else {
            applyProperties(currentProps)
        }
        bindProperties(vm.propertiesWithVariables)
        return vm
    }
}

extension DSL.Model.Style.TextModel.Alignment {

    var ui: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .justified: return .justified
        case .natural: return .natural
        }
    }
}
