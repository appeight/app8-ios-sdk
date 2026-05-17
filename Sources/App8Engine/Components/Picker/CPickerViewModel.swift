//
//  CPickerViewModel.swift
//  App8Engine
//

import Combine
import Foundation

class CPickerViewModel: CBaseViewModel<DSL.Model.Component.Picker.C> {

    let selectionChanged = PassthroughSubject<String, Never>()

    /// External updates originating from variable changes.
    let externalSelectionUpdate = PassthroughSubject<String, Never>()

    private(set) var currentSelection: String = ""

    /// Guards against view↔variable feedback loops.
    private var isUpdatingFromVariable = false

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Setup

    override func setup() {
        super.setup()
        setupTwoWayBinding()
        initializeValue()
    }

    private func initializeValue() {
        if let bindVar = currentProperties.bindVariable,
           let value = variableStore.getValue(name: bindVar) as? String {
            currentSelection = value
        } else if let expr = currentProperties.selectedValue {
            currentSelection = resolvePropertyToString(expr)
        }
    }

    private func setupTwoWayBinding() {
        guard let bindVar = currentProperties.bindVariable else { return }

        // View -> Variable
        selectionChanged
            .filter { [weak self] _ in !(self?.isUpdatingFromVariable ?? false) }
            .sink { [weak self] newValue in
                guard let self = self else { return }
                self.currentSelection = newValue
                try? self.variableStore.setValue(name: bindVar, value: newValue)
            }
            .store(in: &cancellables)

        // Variable -> View
        variableStore.anyVariableChanged
            .filter { $0 == bindVar }
            .compactMap { [weak self] _ -> String? in
                self?.variableStore.getValue(name: bindVar) as? String
            }
            .filter { [weak self] newValue in
                guard let self = self else { return false }
                return newValue != self.currentSelection
            }
            .sink { [weak self] value in
                guard let self = self else { return }
                self.isUpdatingFromVariable = true
                self.currentSelection = value
                self.externalSelectionUpdate.send(value)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isUpdatingFromVariable = false
                }
            }
            .store(in: &cancellables)
    }
}
