//
//  CToggleViewModel.swift
//  App8Engine
//

import Combine
import Foundation

class CToggleViewModel: CBaseViewModel<DSL.Model.Component.Toggle.C> {

    let toggleChanged = PassthroughSubject<Bool, Never>()

    /// External updates originating from variable changes.
    let externalToggleUpdate = PassthroughSubject<Bool, Never>()

    private(set) var currentIsOn: Bool = false

    /// Guards against view↔variable feedback loops.
    private var isUpdatingFromVariable = false

    private var cancellables = Set<AnyCancellable>()

    override func setup() {
        super.setup()
        setupTwoWayBinding()
        initializeValue()
    }

    private func initializeValue() {
        if let bindVar = currentProperties.bindVariable,
           let value = variableStore.getValue(name: bindVar) {
            if let bool = value as? Bool {
                currentIsOn = bool
            } else if let num = value as? Int {
                currentIsOn = num != 0
            } else if let str = value as? String {
                currentIsOn = str.lowercased() == "true" || str == "1"
            }
        } else if let expr = currentProperties.isOn {
            currentIsOn = resolvePropertyToBool(expr) ?? false
        }
    }

    private func setupTwoWayBinding() {
        guard let bindVar = currentProperties.bindVariable else { return }

        // View -> Variable
        toggleChanged
            .filter { [weak self] _ in !(self?.isUpdatingFromVariable ?? false) }
            .sink { [weak self] newValue in
                guard let self = self else { return }
                self.currentIsOn = newValue
                try? self.variableStore.setValue(name: bindVar, value: newValue)
            }
            .store(in: &cancellables)

        // Variable -> View
        variableStore.anyVariableChanged
            .filter { $0 == bindVar }
            .compactMap { [weak self] _ -> Bool? in
                guard let self = self else { return nil }
                let value = self.variableStore.getValue(name: bindVar)
                if let bool = value as? Bool { return bool }
                if let num = value as? Int { return num != 0 }
                if let str = value as? String { return str.lowercased() == "true" || str == "1" }
                return nil
            }
            .filter { [weak self] newValue in
                guard let self = self else { return false }
                return newValue != self.currentIsOn
            }
            .sink { [weak self] value in
                guard let self = self else { return }
                self.isUpdatingFromVariable = true
                self.currentIsOn = value
                self.externalToggleUpdate.send(value)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isUpdatingFromVariable = false
                }
            }
            .store(in: &cancellables)
    }
}
