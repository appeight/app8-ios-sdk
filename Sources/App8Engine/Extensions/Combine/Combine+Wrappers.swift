import Combine

@propertyWrapper
struct Relay<Value> {
    private let subject: CurrentValueSubject<Value, Never>

    init(wrappedValue: Value) {
        subject = CurrentValueSubject(wrappedValue)
    }

    var wrappedValue: Value {
        get { subject.value }
        set { subject.send(newValue) }
    }

    var projectedValue: AnyPublisher<Value, Never> {
        subject.eraseToAnyPublisher()
    }
}
