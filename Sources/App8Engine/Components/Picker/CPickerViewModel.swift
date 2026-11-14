//
//  CPickerViewModel.swift
//  App8Engine
//

import Combine
import Foundation

class CPickerViewModel: CBaseViewModel<DSL.Model.Component.Picker.C> {

    typealias Option = DSL.Model.Component.Picker.Option

    let selectionChanged = PassthroughSubject<String, Never>()

    /// External updates originating from variable changes.
    let externalSelectionUpdate = PassthroughSubject<String, Never>()

    /// Fires when expression `options` resolve to a different list.
    let optionsUpdate = PassthroughSubject<[Option], Never>()

    private(set) var currentSelection: String = ""
    private(set) var currentOptions: [Option] = []

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Setup

    override func setup() {
        super.setup()
        currentOptions = resolveOptions()
        currentSelection = resolveSelection() ?? ""
        setupBinding()
    }

    // MARK: - Resolution

    /// Static `options`, or the `options` expression resolved to an array.
    func resolveOptions() -> [Option] {
        let props = currentProperties
        if let expression = props.optionsExpression {
            let resolved = resolveProperty(expression)
            guard let array = resolved as? [Any] else { return [] }
            return array.compactMap(Option.init(any:))
        }
        return props.options ?? []
    }

    /// The `bindKey` resolved in this component's scope (nil when unset/empty).
    private func resolvedBindKey() -> String? {
        guard let raw = currentProperties.bindKey else { return nil }
        let key = resolvePropertyToString(raw)
        return key.isEmpty ? nil : key
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let n as NSNumber:
            let d = n.doubleValue
            return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
        default: return nil
        }
    }

    /// Selection from the bound variable (at `bindKey` for an object variable),
    /// else from `selectedValue`.
    func resolveSelection() -> String? {
        let props = currentProperties
        if let bindVar = props.bindVariable {
            let bound = variableStore.getValue(name: bindVar)
            if let key = resolvedBindKey() {
                if let map = bound as? [String: Any], let value = Self.string(map[key]) {
                    return value
                }
            } else if let value = Self.string(bound), !value.isEmpty || props.selectedValue == nil {
                return value
            }
        }
        if let expr = props.selectedValue {
            return resolvePropertyToString(expr)
        }
        return nil
    }

    // MARK: - Binding

    private func setupBinding() {
        // View -> Variable
        selectionChanged
            .sink { [weak self] newValue in
                guard let self else { return }
                self.currentSelection = newValue
                self.write(newValue)
            }
            .store(in: &cancellables)

        // Variable -> View: re-resolve options and selection on any change in scope.
        variableStore.anyVariableChanged
            .sink { [weak self] _ in self?.refreshFromVariables() }
            .store(in: &cancellables)
    }

    private func write(_ value: String) {
        guard let bindVar = currentProperties.bindVariable else { return }
        if let key = resolvedBindKey() {
            var map = (variableStore.getValue(name: bindVar) as? [String: Any]) ?? [:]
            map[key] = value
            do {
                try variableStore.setValue(name: bindVar, value: map)
            } catch {
                service.context.logger.error("picker: failed to write '\(bindVar)[\(key)]': \(error)")
            }
        } else {
            try? variableStore.setValue(name: bindVar, value: value)
        }
    }

    private func refreshFromVariables() {
        if currentProperties.optionsExpression != nil {
            let options = resolveOptions()
            if options.map(\.value) != currentOptions.map(\.value) || options.map(\.label) != currentOptions.map(\.label) {
                currentOptions = options
                optionsUpdate.send(options)
            }
        }
        if let selection = resolveSelection(), selection != currentSelection {
            currentSelection = selection
            externalSelectionUpdate.send(selection)
        }
    }
}
