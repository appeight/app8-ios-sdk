//
//  CTextViewView.swift
//  App8Engine
//

import UIKit
import Combine

/// View for TextView component (multi-line text input)
class CTextViewView: App8BaseView<DSL.Model.Component.TextView.C>, CViewProtocol, UITextViewDelegate, Focusable {

    // MARK: - Properties

    weak var materialView: MaterialView?
    let contentView = UIView()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()

    override var intrinsicContentSource: UIView? { textView }

    private var viewModel: CTextViewViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var heightConstraint: NSLayoutConstraint?
    private var placeholderStyle: DSL.Model.Style.TextModel?

    private var placeholderLeadingConstraint: NSLayoutConstraint?
    private var placeholderTrailingConstraint: NSLayoutConstraint?
    private var placeholderTopConstraint: NSLayoutConstraint?

    private let defaultPadding = (top: CGFloat(12), left: CGFloat(12), bottom: CGFloat(12), right: CGFloat(12))

    // MARK: - Focusable

    var focusableId: String? { viewModel?.componentPath }

    func requestFocus() {
        textView.becomeFirstResponder()
    }

    func resignFocus() {
        textView.resignFirstResponder()
    }

    // MARK: - Setup

    override func setup() {
        super.setup()

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()

        contentView.addSubview(textView)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.textContainer.lineFragmentPadding = 0

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            textView.topAnchor.constraint(equalTo: contentView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // Placeholder label overlays the text view.
        textView.addSubview(placeholderLabel)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.numberOfLines = 0

        placeholderLeadingConstraint = placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: defaultPadding.left)
        placeholderTrailingConstraint = placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -defaultPadding.right)
        placeholderTopConstraint = placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: defaultPadding.top)

        NSLayoutConstraint.activate([
            placeholderLeadingConstraint!, placeholderTrailingConstraint!, placeholderTopConstraint!
        ])

        textView.delegate = self

        textView.textColor = .black
        placeholderLabel.textColor = .gray
    }

    // MARK: - Configuration

    func configure(viewModel: CTextViewViewModel, superview: UIView? = nil, animated: Bool = true) {
        self.viewModel = viewModel

        guard let superview = superview ?? self.superview else {
            return
        }

        bindLayout(
            viewModel.layout,
            in: superview,
            viewRegistry: viewModel.service.componentRegistry.viewRegistry,
            parentComponentPath: viewModel.parentPath,
            keyboardService: viewModel.service.context.keyboardService,
            animated: animated
        )
        bindStyle(viewModel.style, animation: viewModel.animation)
        bindProperties(viewModel.propertiesWithVariables)
        bindExternalTextUpdates()

        textView.text = viewModel.currentText
        updatePlaceholderVisibility()

        viewModel.service.context.focusManager.register(id: viewModel.componentPath, view: self)
        viewModel.startEventTriggers()
    }

    private func bindProperties(_ propertiesPublisher: AnyPublisher<DSL.Model.Component.TextView.Properties, Never>) {
        propertiesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] properties in
                self?.applyProperties(properties)
            }
            .store(in: &cancellables)
    }

    private func bindExternalTextUpdates() {
        viewModel?.externalTextUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.textView.text = text
                self?.updatePlaceholderVisibility()
            }
            .store(in: &cancellables)
    }

    private func applyProperties(_ properties: DSL.Model.Component.TextView.Properties) {
        if let placeholder = properties.placeholder {
            let resolvedPlaceholder = viewModel?.resolvePropertyToString(placeholder) ?? placeholder
            placeholderLabel.text = resolvedPlaceholder
            // Re-apply placeholder style now that the text is set.
            if let style = placeholderStyle {
                applyPlaceholderStyle(style)
            }
        }

        if let keyboardType = properties.keyboardType {
            textView.keyboardType = keyboardType.uiKeyboardType
        }

        if let contentType = properties.textContentType {
            textView.textContentType = contentType.uiTextContentType
        }

        if let returnKeyType = properties.returnKeyType {
            textView.returnKeyType = returnKeyType.uiReturnKeyType
        }

        if let autocap = properties.autocapitalization {
            textView.autocapitalizationType = autocap.uiType
        }

        if let autocorrect = properties.autocorrection {
            textView.autocorrectionType = autocorrect ? .yes : .no
        }

        textView.isEditable = properties.isEnabled ?? true
        textView.isScrollEnabled = properties.scrollEnabled ?? true
    }

    // MARK: - Placeholder

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }

    // MARK: - UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        guard let viewModel = viewModel else { return }

        let text = textView.text ?? ""
        updatePlaceholderVisibility()

        viewModel.textChanged.send(text)

        if viewModel.currentProperties.autoGrow == true {
            updateHeightForAutoGrow()
        }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        viewModel?.fireTrigger(.focus)
        if let id = focusableId {
            viewModel?.service.context.focusManager.didFocus(id: id)
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        viewModel?.fireTrigger(.blur)
        if viewModel?.service.context.focusManager.currentFocusId == focusableId {
            viewModel?.service.context.focusManager.didFocus(id: nil)
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard let viewModel = viewModel else { return true }
        let currentText = textView.text ?? ""
        return viewModel.isCharacterAllowed(text, in: range, currentText: currentText)
    }

    // MARK: - Auto-Grow

    private func updateHeightForAutoGrow() {
        guard let viewModel = viewModel,
              viewModel.currentProperties.autoGrow == true else { return }

        let maxHeight = viewModel.currentProperties.maxHeight ?? 200
        let minHeight = viewModel.currentProperties.minHeight ?? 44

        let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
        let newHeight = min(max(size.height, minHeight), maxHeight)

        if let constraint = heightConstraint {
            constraint.constant = newHeight
        }

        textView.isScrollEnabled = size.height > maxHeight
    }

    // MARK: - Style Application

    override func applyStyle(
        _ style: Content.Style?,
        animated: Bool = true,
        duration: TimeInterval = 0.25,
        options: UIView.AnimationOptions = [.curveEaseInOut],
        useSpring: Bool = false
    ) {
        super.applyStyle(style, animated: animated, duration: duration, options: options, useSpring: useSpring)
        applyBaseStyle(style, animated: animated, duration: duration, options: options, useSpring: useSpring)

        if let textModel = style?.text {
            applyTextStyle(textModel)
        }

        if let placeholderModel = style?.placeholder {
            placeholderStyle = placeholderModel
            applyPlaceholderStyle(placeholderModel)
        }

        // tintColor styles the cursor.
        if let tintColor = style?.tintColor {
            textView.tintColor = tintColor.ui
        }

        let padding = style?.padding?.resolve(
            defaultTop: defaultPadding.top,
            defaultLeft: defaultPadding.left,
            defaultBottom: defaultPadding.bottom,
            defaultRight: defaultPadding.right
        ) ?? defaultPadding

        textView.textContainerInset = UIEdgeInsets(
            top: padding.top,
            left: padding.left,
            bottom: padding.bottom,
            right: padding.right
        )
        placeholderLeadingConstraint?.constant = padding.left
        placeholderTrailingConstraint?.constant = -padding.right
        placeholderTopConstraint?.constant = padding.top
    }

    private func applyTextStyle(_ textModel: DSL.Model.Style.TextModel) {
        if let themedColor = textModel.color {
            textView.textColor = themedColor.ui
        }

        if let alignment = textModel.alignment {
            textView.textAlignment = alignment.ui
        }

        textView.font = textModel.resolveUIFont()
    }

    private func applyPlaceholderStyle(_ textModel: DSL.Model.Style.TextModel) {
        if let themedColor = textModel.color {
            placeholderLabel.textColor = themedColor.ui
        }

        if let alignment = textModel.alignment {
            placeholderLabel.textAlignment = alignment.ui
        }

        placeholderLabel.font = textModel.resolveUIFont()
    }

    // MARK: - Cleanup

    override func removeFromSuperview() {
        viewModel?.cancelEventTriggers()
        if let id = focusableId {
            viewModel?.service.context.focusManager.unregister(id: id)
        }
        cancellables.removeAll()
        super.removeFromSuperview()
    }
}
