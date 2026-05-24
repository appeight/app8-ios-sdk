import Foundation
import Combine

// MARK: - Convenience host API for events + analytics

/// Host-facing closure/Combine/AsyncStream/delegate sugar over
/// `App8.Instance.eventBus` + `App8.Instance.analyticsBus`. The bus types are
/// public for direct use (and for the Cloud SDK passthrough) but most hosts
/// will reach for these one-liners.
public extension App8.Instance {

    // MARK: Action events

    /// Subscribe to every `.emit` action event fired from any DSL screen
    /// rendered by this instance. Hold the returned subscription for the
    /// lifetime you want events; cancel it (or let it deallocate) to stop.
    @MainActor
    @discardableResult
    func subscribe(_ handler: @escaping (App8Event) -> Void) -> App8Subscription {
        eventBus.subscribe(handler)
    }

    /// Subscribe to events with a specific `name`.
    @MainActor
    @discardableResult
    func subscribe(to eventName: String, _ handler: @escaping (App8Event) -> Void) -> App8Subscription {
        eventBus.subscribe(to: eventName, handler)
    }

    /// Subscribe to events fired from a specific DSL screen.
    @MainActor
    @discardableResult
    func subscribe(onScreen screenId: String, _ handler: @escaping (App8Event) -> Void) -> App8Subscription {
        eventBus.subscribe(onScreen: screenId, handler)
    }

    /// Combine view of the action-event stream. Each subscription is
    /// independent; values are not buffered.
    var events: AnyPublisher<App8Event, Never> {
        eventBus.publisher
    }

    /// AsyncStream view of the action-event stream. Each access returns a
    /// fresh stream; events emitted before await are dropped.
    var eventStream: AsyncStream<App8Event> {
        eventBus.stream
    }

    /// Register a single delegate-style handler for action events. Held
    /// weakly; pass `nil` to clear.
    @MainActor
    func setEventHandler(_ handler: App8EventHandler?) {
        eventBus.delegate = handler
    }

    // MARK: Analytics events

    /// Observe every analytics event — both author-declared and auto-fired
    /// (`app8_*`). For the canonical "proxy to my analytics SDK" case,
    /// prefer `setAnalyticsHandler(_:)` instead.
    @MainActor
    @discardableResult
    func observeAnalytics(_ handler: @escaping (App8AnalyticsEvent) -> Void) -> App8Subscription {
        analyticsBus.subscribe(handler)
    }

    /// Combine view of the analytics stream.
    var analytics: AnyPublisher<App8AnalyticsEvent, Never> {
        analyticsBus.publisher
    }

    /// AsyncStream view of the analytics stream.
    var analyticsStream: AsyncStream<App8AnalyticsEvent> {
        analyticsBus.stream
    }

    /// Register a single delegate-style analytics handler. The expected
    /// pattern: one implementation in your app's analytics adapter,
    /// proxying every event to your real tracker (Mixpanel, Amplitude, …).
    /// Held weakly; pass `nil` to clear.
    @MainActor
    func setAnalyticsHandler(_ handler: App8AnalyticsHandler?) {
        analyticsBus.delegate = handler
    }
}
