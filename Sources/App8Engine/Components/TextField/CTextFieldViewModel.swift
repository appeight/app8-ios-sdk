//
//  CTextFieldViewModel.swift
//  App8Engine
//

import Combine
import UIKit

/// ViewModel for TextField component with two-way variable binding
class CTextFieldViewModel: CBaseViewModel<DSL.Model.Component.TextField.C> {

    let textChanged = PassthroughSubject<String, Never>()

    /// External text updates originating from variable changes.
    let externalTextUpdate = PassthroughSubject<String, Never>()

    private(set) var currentText: String = ""

    /// Guards against view↔variable feedback loops.
    private var isUpdatingFromVariable = false

    override func setup() {
        super.setup()
        setupTwoWayBinding()
        initializeText()
    }

    /// Initializes text from the bound variable, falling back to the `text` property.
    private func initializeText() {
        if let bindVar = currentProperties.bindVariable,
           let value = variableStore.getValue(name: bindVar) as? String {
            currentText = value
        }
        else if let text = currentProperties.text {
            currentText = resolvePropertyToString(text)
        }
    }

    private func setupTwoWayBinding() {
        guard let bindVar = currentProperties.bindVariable else { return }

        // View -> Variable
        textChanged
            .filter { [weak self] _ in
                !(self?.isUpdatingFromVariable ?? false)
            }
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] newText in
                guard let self = self else { return }
                self.currentText = newText
                try? self.variableStore.setValue(name: bindVar, value: newText)
            }
            .store(in: &cancellables)

        // Variable -> View
        variableStore.anyVariableChanged
            .filter { $0 == bindVar }
            .compactMap { [weak self] _ -> String? in
                self?.variableStore.getValue(name: bindVar) as? String
            }
            .filter { [weak self] newText in
                newText != self?.currentText
            }
            .sink { [weak self] text in
                guard let self = self else { return }
                self.isUpdatingFromVariable = true
                self.currentText = text
                self.externalTextUpdate.send(text)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isUpdatingFromVariable = false
                }
            }
            .store(in: &cancellables)
    }

    func applyInputMask(_ text: String) -> String {
        guard let mask = currentProperties.inputMask else { return text }
        return TextInputValidation.formatWithMask(text: text, mask: mask)
    }

    func extractRawValue(_ text: String) -> String {
        guard currentProperties.inputMask != nil else { return text }
        return TextInputValidation.extractDigits(text)
    }

    func isCharacterAllowed(_ string: String, in range: NSRange, currentText: String) -> Bool {
        TextInputValidation.isInputAllowed(
            string,
            in: range,
            currentText: currentText,
            maxLength: currentProperties.maxLength,
            allowedPattern: currentProperties.allowedCharacters
        )
    }

    private var cancellables = Set<AnyCancellable>()
}
