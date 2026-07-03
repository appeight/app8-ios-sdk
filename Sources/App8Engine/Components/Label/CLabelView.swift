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
    // truncated when their container is under vertical pressure. We keep
    // `preferredMaxLayoutWidth` equal to the width the container actually grants
    // us — MEASURED via the layout engine, not guessed from the constraint graph
    // (see `syncWrapWidth`).
    override func layoutSubviews() {
        super.layoutSubviews()
        syncWrapWidth()
        performAutoshrinkIfNeeded()
    }

    // MARK: - Deterministic wrap width (measure, don't classify)

    private enum WrapPhase { case idle, measuring }
    private var wrapPhase: WrapPhase = .idle
    private var lastWrapContainerWidth: CGFloat = -1
    private var lastWrapNatural: CGFloat = -1

    /// Keep `preferredMaxLayoutWidth` equal to the width our container is actually
    /// willing to give us, determined by MEASUREMENT rather than by inspecting the
    /// constraint graph.
    ///
    /// Why not inspect constraints: UIKit expresses "hug your content", "chain to
    /// your sibling" (`UIStackView`), and "size to the scrolled content"
    /// (`UIScrollView.contentLayoutGuide`) using the very same `.equal` edge and
    /// width constraints an author uses to pin a fixed width — and even realizes a
    /// label's own content-driven width as a `width == k` constraint. There is no
    /// reliable *local* way to tell an authored fixed width from a content-derived
    /// one, so any classifier eventually clamps a label to a content-driven
    /// ancestor and closes a collapse feedback loop (narrower label → narrower
    /// container → narrower clamp → …) that renders text one glyph per line — e.g.
    /// a name label in a horizontal carousel.
    ///
    /// Instead we let the constraint solver answer the only question that matters:
    /// *if this label reported its full unwrapped width, how wide would its
    /// container let it be?* If the granted width is at least the unwrapped width,
    /// nothing is constraining us — hug (single line, or wrap only at authored
    /// newlines). If it is narrower, a genuine boundary (a fixed-width stack, a
    /// vertical scroll pinned to its frame, the safe area, the window) is capping
    /// us — wrap there. Content-hugging ancestors grant us our full width and so
    /// never cap; this needs no knowledge of the surrounding topology.
    ///
    /// Driven across two layout passes so we never force a re-entrant layout:
    /// `.measuring` publishes the unwrapped width; the next pass reads what the
    /// container granted and commits it. We re-measure only when the container
    /// width or the text's unwrapped width changes, so steady state is free.
    private func syncWrapWidth() {
        // A single-line label never soft-wraps; its intrinsic width is already
        // correct and `preferredMaxLayoutWidth` would only truncate it.
        guard label.numberOfLines != 1 else { return }
        let containerWidth = superview?.bounds.width ?? 0

        // Steady-state fast path: once committed (`lastWrapNatural > 0`, reset to
        // -1 on every text change), skip the `boundingRect` measurement entirely
        // while the container width is unchanged.
        if wrapPhase == .idle, lastWrapNatural > 0,
           abs(containerWidth - lastWrapContainerWidth) < 0.5 { return }

        let natural = naturalUnwrappedWidth()
        guard natural > 0.5 else { return }

        if wrapPhase == .idle {
            // Nothing that affects the answer changed → the committed width holds.
            if abs(containerWidth - lastWrapContainerWidth) < 0.5,
               abs(natural - lastWrapNatural) < 0.5 { return }
            // Publish our full unwrapped width and let the container re-grant our
            // bounds on the next pass — unless we're already reporting it, in which
            // case `bounds.width` already reflects the grant and we can commit now.
            if abs(label.preferredMaxLayoutWidth - natural) > 0.5 {
                wrapPhase = .measuring
                setPreferredMaxWidth(natural)
                return
            }
        }
        // `.measuring` (or already-at-natural): `bounds.width` is the width the
        // container grants when we ask for our full width. Commit the wrap width.
        let granted = label.bounds.width
        let target = granted + 0.5 >= natural ? natural : granted
        wrapPhase = .idle
        lastWrapContainerWidth = containerWidth
        lastWrapNatural = natural
        setPreferredMaxWidth(target)
    }

    private func setPreferredMaxWidth(_ width: CGFloat) {
        guard abs(label.preferredMaxLayoutWidth - width) > 0.5 else { return }
        label.preferredMaxLayoutWidth = width
        label.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
    }

    /// The width this label needs to render without SOFT-wrapping — the widest of
    /// its hard (`\n`-delimited) lines. Independent of `preferredMaxLayoutWidth`,
    /// so it is a stable reference the measurement compares its granted width
    /// against.
    private func naturalUnwrappedWidth() -> CGFloat {
        let attributed: NSAttributedString
        if let attr = label.attributedText, attr.length > 0 {
            attributed = attr
        } else if let text = label.text, !text.isEmpty {
            attributed = NSAttributedString(string: text, attributes: [.font: label.font as Any])
        } else {
            return 0
        }
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let rect = attributed.boundingRect(
            with: unbounded,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(rect.width)
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
        // The text (hence its unwrapped width) changed — force `syncWrapWidth` to
        // re-measure on the next layout pass rather than trust its cache.
        lastWrapNatural = -1
        // Seed preferredMaxLayoutWidth so a multi-line label reports a sensible
        // height before the first layout pass establishes bounds; `syncWrapWidth`
        // measures the real granted width once we're laid out. A generous seed (the
        // display width) can only over-report height for a frame or two — never
        // collapse — which the measurement then corrects.
        if label.bounds.width <= 0, label.preferredMaxLayoutWidth <= 0 {
            label.preferredMaxLayoutWidth = UIScreen.main.bounds.width
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
