import Foundation
import Combine

// MARK: - App8EventBus

/// In-process pub/sub for `App8Event`. Owned by `App8Context`; one bus per
/// `App8.Instance`. Host code interacts via the convenience methods on the
/// instance (`subscribe(_:)`, `events`, `eventStream`, `setEventHandler(_:)`)
/// rather than touching the bus directly, but the bus is public so the
/// Cloud SDK can wire passthrough.
@MainActor
public final class App8EventBus {

    private struct Subscriber {
        let id: UUID
        let handler: (App8Event) -> Void
    }

    private var subscribers: [Subscriber] = []
    private let subject = PassthroughSubject<App8Event, Never>()

    /// Optional single-handler sink for hosts that prefer a delegate style.
    /// Stored weakly to avoid retain cycles with view controllers.
    public weak var delegate: App8EventHandler?

    public init() {}

    // MARK: Dispatch (engine-internal)

    /// Engine-internal entry. Fans out to: closure subscribers, the Combine
    /// subject, and the delegate, in that order. Synchronous + on the main
    /// actor so subscription order is preserved and the host can react
    /// before subsequent actions run.
    public func dispatch(_ event: App8Event) {
        for subscriber in subscribers {
            subscriber.handler(event)
        }
        subject.send(event)
        delegate?.app8DidEmit(event)
    }

    // MARK: Subscription

    @discardableResult
    public func subscribe(_ handler: @escaping (App8Event) -> Void) -> App8Subscription {
        let id = UUID()
        subscribers.append(Subscriber(id: id, handler: handler))
        return App8Subscription { [weak self] in
            self?.subscribers.removeAll { $0.id == id }
        }
    }

    @discardableResult
    public func subscribe(to eventName: String, _ handler: @escaping (App8Event) -> Void) -> App8Subscription {
        subscribe { event in
            if event.name == eventName { handler(event) }
        }
    }

    @discardableResult
    public func subscribe(onScreen screenId: String, _ handler: @escaping (App8Event) -> Void) -> App8Subscription {
        subscribe { event in
            if event.screenId == screenId { handler(event) }
        }
    }

    /// Combine publisher view. Each subscription is independent; values are
    /// shared, not buffered (no replay).
    public var publisher: AnyPublisher<App8Event, Never> {
        subject.eraseToAnyPublisher()
    }

    /// AsyncStream view. Each access returns a fresh stream; events emitted
    /// before the stream is awaited are dropped (no buffering).
    public var stream: AsyncStream<App8Event> {
        AsyncStream { continuation in
            let sub = subscribe { event in
                continuation.yield(event)
            }
            continuation.onTermination = { _ in
                Task { @MainActor in sub.cancel() }
            }
        }
    }
}

// MARK: - App8AnalyticsBus

/// In-process pub/sub for `App8AnalyticsEvent`. Mirrors `App8EventBus` but
/// for the analytics channel — separate sink so high-volume analytics
/// events don't pollute the action-event handler.
@MainActor
public final class App8AnalyticsBus {

    private struct Subscriber {
        let id: UUID
        let handler: (App8AnalyticsEvent) -> Void
    }

    private var subscribers: [Subscriber] = []
    private let subject = PassthroughSubject<App8AnalyticsEvent, Never>()

    public weak var delegate: App8AnalyticsHandler?

    public init() {}

    public func dispatch(_ event: App8AnalyticsEvent) {
        for subscriber in subscribers {
            subscriber.handler(event)
        }
        subject.send(event)
        delegate?.app8DidTrack(event)
    }

    @discardableResult
    public func subscribe(_ handler: @escaping (App8AnalyticsEvent) -> Void) -> App8Subscription {
        let id = UUID()
        subscribers.append(Subscriber(id: id, handler: handler))
        return App8Subscription { [weak self] in
            self?.subscribers.removeAll { $0.id == id }
        }
    }

    public var publisher: AnyPublisher<App8AnalyticsEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    public var stream: AsyncStream<App8AnalyticsEvent> {
        AsyncStream { continuation in
            let sub = subscribe { event in
                continuation.yield(event)
            }
            continuation.onTermination = { _ in
                Task { @MainActor in sub.cancel() }
            }
        }
    }
}
