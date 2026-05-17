import Combine

class CPageControlViewModel: CBaseViewModel<DSL.Model.Component.PageControl.C> {

    /// Publisher for page changes from user interaction
    let pageChanged = PassthroughSubject<Int, Never>()

    private var cancellables = Set<AnyCancellable>()

    override func setup() {
        super.setup()
        setupBinding()
    }

    /// Writes page changes back to the bound variable.
    private func setupBinding() {
        guard let bindVar = currentProperties.bindVariable else { return }

        pageChanged
            .sink { [weak self] page in
                guard let self = self else { return }
                try? self.variableStore.setValue(name: bindVar, value: page)
            }
            .store(in: &cancellables)
    }
}
