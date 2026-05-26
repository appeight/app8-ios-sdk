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

    /// Cloud SDK version stamped onto every dispatched event. `nil` for
    /// engine-only callers; `A8CInstance` sets this once at construction
    /// (`engine.eventBus.cloudVersion = SDKVersion.current`) so every
    /// subsequent dispatch auto-stamps `cloudVersion` without per-call
    /// plumbing. Action events get version stamping but **not** the
    /// canonical-property merge that the analytics bus does — `payload` is
    /// exactly what the DSL author wrote; injecting SDK keys would break the
    /// host-handler contract (host switches/destructures on payload keys).
    /// Hosts that want SDK context read it from typed fields
    /// (`event.engineVersion`, `event.cloudVersion`, `event.screenId`,
    /// `event.locale`).
    public var cloudVersion: String?

    public init() {}

    // MARK: Dispatch (engine-internal)

    /// Engine-internal entry. Stamps `engineVersion` + `cloudVersion`, then
    /// fans out to: closure subscribers, the Combine subject, and the
    /// delegate, in that order. Synchronous + on the main actor so
    /// subscription order is preserved and the host can react before
    /// subsequent actions run.
    public func dispatch(_ event: App8Event) {
        let stamped = event._stamped(
            engineVersion: EngineVersion.current,
            cloudVersion: cloudVersion
        )
        for subscriber in subscribers {
            subscriber.handler(stamped)
        }
        subject.send(stamped)
        delegate?.app8DidEmit(stamped)
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
///
/// **Dispatch pipeline** (`dispatch(_:)`):
///
/// 1. **Stamp** `engineVersion` (from `EngineVersion.current`) and
///    `cloudVersion` (from `self.cloudVersion`) onto the event.
/// 2. **Merge** SDK-canonical context into `properties` using snake_case
///    unprefixed keys: `screen_id`, `component_id`, `component_type`,
///    `locale`, `engine_version`, `cloud_version`. Keys whose underlying
///    typed field is `nil` are omitted entirely — no null pollution. SDK
///    values win over any author-supplied key with the same name (collision
///    warnings fire at the emit site, not here; the bus stays a dumb pipe).
/// 3. **Redact** — if a `redact` closure is set, the canonical event runs
///    through it. Returning `nil` drops the event silently. Returning a
///    mutated copy substitutes it. The closure receives the fully-baked
///    event with `engine_version` etc. already in `properties`.
/// 4. **Fan out** to closure subscribers, the Combine subject, and the
///    delegate, in that order.
@MainActor
public final class App8AnalyticsBus {

    private struct Subscriber {
        let id: UUID
        let handler: (App8AnalyticsEvent) -> Void
    }

    private var subscribers: [Subscriber] = []
    private let subject = PassthroughSubject<App8AnalyticsEvent, Never>()

    public weak var delegate: App8AnalyticsHandler?

    /// Cloud SDK version stamped onto every dispatched event. `nil` for
    /// engine-only callers; `A8CInstance` sets this once at construction.
    /// When set, every dispatch auto-stamps `cloudVersion` on the typed field
    /// and merges `cloud_version` into `properties`.
    public var cloudVersion: String?

    /// Optional PII/redaction hook. Runs *after* version stamping and the
    /// canonical-property merge — the closure receives the fully-baked event,
    /// including `engine_version`, `screen_id`, etc. already in `properties`.
    ///
    /// Return value semantics:
    /// - `nil` → the event is dropped silently (no subscriber sees it).
    /// - non-`nil` → the returned event substitutes the original and is
    ///   fanned out to all subscribers.
    ///
    /// The closure is non-throwing — Swift function-type closures cannot
    /// throw unless declared `throws` in the signature, and this property's
    /// signature is non-throwing, so propagation is impossible by type.
    /// Hosts that need conditional drops return `nil`; hosts that need to
    /// surface an error log it themselves before returning.
    public var redact: ((App8AnalyticsEvent) -> App8AnalyticsEvent?)?

    public init() {}

    public func dispatch(_ event: App8AnalyticsEvent) {
        // Step 1: stamp versions.
        let stamped = event._stamped(
            engineVersion: EngineVersion.current,
            cloudVersion: cloudVersion
        )
        // Step 2: merge canonical context into properties.
        let merged = stamped._withProperties(mergeCanonical(into: stamped))
        // Step 3: redact.
        let final: App8AnalyticsEvent
        if let redact = redact {
            guard let redacted = redact(merged) else { return }
            final = redacted
        } else {
            final = merged
        }
        // Step 4: fan out.
        for subscriber in subscribers {
            subscriber.handler(final)
        }
        subject.send(final)
        delegate?.app8DidTrack(final)
    }

    /// Builds the final `properties` dict for an event: author keys first,
    /// then SDK-canonical keys overlaid (so SDK wins on collision). Keys
    /// whose underlying typed field is `nil` are omitted — `properties`
    /// never carries `screen_id: nil`, it carries no `screen_id` at all.
    /// Mirrors `App8AnalyticsEvent.canonicalKeys` — adding a key there
    /// means adding a case here, and the `canonicalKeys`-matches-bus test
    /// will fail if you forget.
    private func mergeCanonical(into event: App8AnalyticsEvent) -> [String: Any] {
        var merged = event.properties
        if let v = event.screenId       { merged["screen_id"] = v }
        if let v = event.componentId    { merged["component_id"] = v }
        if let v = event.componentType  { merged["component_type"] = v }
        if let v = event.locale         { merged["locale"] = v }
        if !event.engineVersion.isEmpty { merged["engine_version"] = event.engineVersion }
        if let v = event.cloudVersion   { merged["cloud_version"] = v }
        return merged
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
