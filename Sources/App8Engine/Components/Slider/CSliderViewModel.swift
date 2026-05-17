//
//  CSliderViewModel.swift
//  App8Engine
//

import Combine
import Foundation

class CSliderViewModel: CBaseViewModel<DSL.Model.Component.Slider.C> {

    let sliderChanged = PassthroughSubject<Float, Never>()

    /// External updates originating from variable changes.
    let externalSliderUpdate = PassthroughSubject<Float, Never>()

    private(set) var currentValue: Float = 0

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
        let props = currentProperties
        if let bindVar = props.bindVariable,
           let value = variableStore.getValue(name: bindVar) {
            if let num = value as? Double { currentValue = Float(num) }
            else if let num = value as? Float { currentValue = num }
            else if let num = value as? Int { currentValue = Float(num) }
        } else if let expr = props.value {
            if let resolved = resolvePropertyToFloat(expr) {
                currentValue = Float(resolved)
            }
        }
    }

    /// Snap value to step if configured, clamped to [min, max]
    func snapToStep(_ value: Float) -> Float {
        guard let step = currentProperties.step, step > 0 else { return value }
        let minVal = currentProperties.minimumValue ?? 0
        let maxVal = currentProperties.maximumValue ?? 1
        let snapped = minVal + (((value - minVal) / step).rounded() * step)
        return min(maxVal, max(minVal, snapped))
    }

    private func setupTwoWayBinding() {
        guard let bindVar = currentProperties.bindVariable else { return }

        // View -> Variable
        sliderChanged
            .filter { [weak self] _ in !(self?.isUpdatingFromVariable ?? false) }
            .map { [weak self] value in self?.snapToStep(value) ?? value }
            .sink { [weak self] newValue in
                guard let self = self else { return }
                self.currentValue = newValue
                try? self.variableStore.setValue(name: bindVar, value: Double(newValue))
            }
            .store(in: &cancellables)

        // Variable -> View
        variableStore.anyVariableChanged
            .filter { $0 == bindVar }
            .compactMap { [weak self] _ -> Float? in
                guard let self = self else { return nil }
                let value = self.variableStore.getValue(name: bindVar)
                if let num = value as? Double { return Float(num) }
                if let num = value as? Float { return num }
                if let num = value as? Int { return Float(num) }
                return nil
            }
            .filter { [weak self] newValue in
                guard let self = self else { return false }
                return newValue != self.currentValue
            }
            .sink { [weak self] value in
                guard let self = self else { return }
                self.isUpdatingFromVariable = true
                self.currentValue = value
                self.externalSliderUpdate.send(value)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isUpdatingFromVariable = false
                }
            }
            .store(in: &cancellables)
    }
}
