//
//  CTextFieldView.swift
//  App8Engine
//

import UIKit
import Combine

/// View for TextField component
class CTextFieldView: App8BaseView<DSL.Model.Component.TextField.C>, CViewProtocol, UITextFieldDelegate, Focusable {

    // MARK: - Properties

    weak var materialView: MaterialView?
    let contentView = UIView()
    private let textField = UITextField()

    override var intrinsicContentSource: UIView? { textField }

    private var viewModel: CTextFieldViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var placeholderStyle: DSL.Model.Style.TextModel?

    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var topConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?

    // MARK: - Focusable

    var focusableId: String? { viewModel?.componentPath }

    func requestFocus() {
        textField.becomeFirstResponder()
    }

    func resignFocus() {
        textField.resignFirstResponder()
    }

    // MARK: - Setup

    override func setup() {
        super.setup()

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()

        contentView.addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false

        // Default padding; overridden by style.padding in applyStyle.
        leadingConstraint = textField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        trailingConstraint = textField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
        topConstraint = textField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0)
        bottomConstraint = textField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 0)

        NSLayoutConstraint.activate([
            leadingConstraint!, trailingConstraint!, topConstraint!, bottomConstraint!
        ])

        textField.delegate = self
        textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)

        textField.textColor = .black
    }

    // MARK: - Configuration

    func configure(viewModel: CTextFieldViewModel, superview: UIView? = nil, animated: Bool = true) {
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

        textField.text = viewModel.currentText

        viewModel.service.context.focusManager.register(id: viewModel.componentPath, view: self)
        viewModel.startEventTriggers()
    }

    private func bindProperties(_ propertiesPublisher: AnyPublisher<DSL.Model.Component.TextField.Properties, Never>) {
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
                self?.textField.text = text
            }
            .store(in: &cancellables)
    }

    private func applyProperties(_ properties: DSL.Model.Component.TextField.Properties) {
        if let placeholder = properties.placeholder {
            let resolvedPlaceholder = viewModel?.resolvePropertyToString(placeholder) ?? placeholder
            textField.placeholder = resolvedPlaceholder
            // Re-apply placeholder style now that the text is set.
            if let style = placeholderStyle {
                applyPlaceholderStyle(style)
            }
        }

        if let keyboardType = properties.keyboardType {
            textField.keyboardType = keyboardType.uiKeyboardType
        }

        if let contentType = properties.textContentType {
            textField.textContentType = contentType.uiTextContentType
        }

        if let returnKeyType = properties.returnKeyType {
            textField.returnKeyType = returnKeyType.uiReturnKeyType
        }

        textField.isSecureTextEntry = properties.isSecure ?? false

        if let autocap = properties.autocapitalization {
            textField.autocapitalizationType = autocap.uiType
        }

        if let autocorrect = properties.autocorrection {
            textField.autocorrectionType = autocorrect ? .yes : .no
        }

        if let clearMode = properties.clearButtonMode {
            textField.clearButtonMode = clearMode.uiMode
        }

        textField.isEnabled = properties.isEnabled ?? true
    }

    // MARK: - Text Change Handling

    @objc private func textDidChange() {
        guard let viewModel = viewModel else { return }

        var text = textField.text ?? ""

        if viewModel.currentProperties.inputMask != nil {
            let maskedText = viewModel.applyInputMask(text)
            if maskedText != text {
                textField.text = maskedText
                text = maskedText
            }
        }

        viewModel.textChanged.send(text)

        // Fire onTextChange with a $value overlay so the action sees the new text.
        if let actions = viewModel.component.actions?[.onTextChange] {
            let context = VariableContext(store: viewModel.variableStore).overlaying("$value", value: text)
            for action in actions {
                do {
                    try VariableActionHandler().execute(action: action, store: viewModel.variableStore, context: context)
                } catch {
                    viewModel.service.context.logger.error("Failed to execute onTextChange action: \(error)")
                }
            }
        }

        // Auto-advance to the next field once maxLength is reached.
        if let maxLength = viewModel.currentProperties.maxLength,
           text.count >= maxLength {
            viewModel.service.context.focusManager.focusNext()
        }
    }

    // MARK: - UITextFieldDelegate

    func textFieldDidBeginEditing(_ textField: UITextField) {
        viewModel?.fireTrigger(.focus)
        if let id = focusableId {
            viewModel?.service.context.focusManager.didFocus(id: id)
        }
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        viewModel?.fireTrigger(.blur)
        if viewModel?.service.context.focusManager.currentFocusId == focusableId {
            viewModel?.service.context.focusManager.didFocus(id: nil)
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // TODO: add a dedicated return-key action trigger; reusing .tap for now.
        viewModel?.executeAction(for: .tap)
        textField.resignFirstResponder()
        return true
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let viewModel = viewModel else { return true }
        let currentText = textField.text ?? ""
        return viewModel.isCharacterAllowed(string, in: range, currentText: currentText)
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
            textField.tintColor = tintColor.ui
        }

        if let padding = style?.padding {
            let resolved = padding.resolve(defaultTop: 0, defaultLeft: 12, defaultBottom: 0, defaultRight: 12)
            leadingConstraint?.constant = resolved.left
            trailingConstraint?.constant = -resolved.right
            topConstraint?.constant = resolved.top
            bottomConstraint?.constant = -resolved.bottom
        }
    }

    private func applyTextStyle(_ textModel: DSL.Model.Style.TextModel) {
        if let themedColor = textModel.color {
            textField.textColor = themedColor.ui
        }

        if let alignment = textModel.alignment {
            textField.textAlignment = alignment.ui
        }

        textField.font = textModel.resolveUIFont()
    }

    private func applyPlaceholderStyle(_ textModel: DSL.Model.Style.TextModel) {
        guard let placeholder = textField.placeholder else { return }

        var attributes: [NSAttributedString.Key: Any] = [:]

        if let themedColor = textModel.color {
            attributes[.foregroundColor] = themedColor.ui
        }

        attributes[.font] = textModel.resolveUIFont()

        if let letterSpacing = textModel.letterSpacing, letterSpacing.type == .fixed {
            attributes[.kern] = letterSpacing.value
        }

        textField.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: attributes)
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
