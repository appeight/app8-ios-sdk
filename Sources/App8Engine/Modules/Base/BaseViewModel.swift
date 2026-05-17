import Combine

@MainActor
protocol BaseViewModelProtocol: AnyObject, CancellableHolder {}

@MainActor
class BaseViewModel: BaseViewModelProtocol {
    var cancellables = Set<AnyCancellable>()
}
