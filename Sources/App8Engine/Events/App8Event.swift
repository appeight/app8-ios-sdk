import Foundation

// MARK: - App8Event (host action events)

/// A typed event fired from a DSL screen to the host. Originates from an
/// `.emit` action authored in the DSL. The host subscribes via
/// `App8.Instance.subscribe(...)` (or the publisher/stream variants) and
/// routes by `name`.
///
/// Payload values support `{{var}}` interpolation in string positions at the
/// authoring site — by the time the event reaches the host, every string in
/// `payload` has been resolved against the component's variable scope.
public struct App8Event: @unchecked Sendable {
    /// Author-declared event name. Convention: dotted lowercase
    /// (e.g. `connect.tapped`, `creator.selected`). Free-form — App8 does
    /// not reserve any namespace except `app8_*` analytics events (which
    /// flow on a separate bus, see `App8AnalyticsEvent`).
    public let name: String

    /// ID of the screen the user is on (the screen's top-level `"id"` in DSL).
    public let screenId: String

    /// Leaf component id of the originating component (the top-level `"id"`
    /// the author wrote on that component in the JSON). `nil` only for
    /// events fired from screen-level triggers without a component anchor.
    public let componentId: String?

    /// Component type token from the DSL (`button`, `view`, `label`, `image`,
    /// etc.). `nil` when the event isn't tied to a single component.
    public let componentType: String?

    /// Active translation locale at fire time (e.g. `"en"`, `"en-US"`,
    /// `"de-DE"`) — from `TranslationStore.activeLocale`. Useful for funnel
    /// parity across languages. `nil` only when an event is constructed
    /// outside the engine (tests, host fixtures).
    public let locale: String?

    /// Resolved payload. Keys are author-declared; string values have already
    /// been interpolated against the component's variable scope.
    public let payload: [String: Any]

    /// Wall-clock time the event was dispatched, set by the engine.
    public let timestamp: Date

    public init(
        name: String,
        screenId: String,
        componentId: String?,
        componentType: String?,
        locale: String? = nil,
        payload: [String: Any],
        timestamp: Date = Date()
    ) {
        self.name = name
        self.screenId = screenId
        self.componentId = componentId
        self.componentType = componentType
        self.locale = locale
        self.payload = payload
        self.timestamp = timestamp
    }
}

// MARK: - App8AnalyticsEvent

/// An analytics event fired by the engine. Two sources:
///
/// 1. **Author-declared** via an `analytics` JSON binding on a component
///    (e.g. `"analytics": { "tap": "stripe_connect_clicked" }`).
/// 2. **Auto-fired** by the engine for built-in lifecycle moments (`app8_*`
///    prefix). See `App8AnalyticsConfig` for which auto events fire.
///
/// Hosts typically register one `App8AnalyticsHandler` at app launch and
/// proxy every event to their real analytics SDK (Mixpanel, Amplitude,
/// Segment, etc.).
public struct App8AnalyticsEvent: @unchecked Sendable {
    public let name: String
    public let screenId: String?
    public let componentId: String?
    public let componentType: String?
    /// Active translation locale at fire time (e.g. `"en"`, `"en-US"`,
    /// `"de-DE"`) — from `TranslationStore.activeLocale`. Useful for funnel
    /// parity across languages. `nil` only when an event is constructed
    /// outside the engine (tests, host fixtures).
    public let locale: String?
    public let properties: [String: Any]
    public let timestamp: Date

    public init(
        name: String,
        screenId: String? = nil,
        componentId: String? = nil,
        componentType: String? = nil,
        locale: String? = nil,
        properties: [String: Any] = [:],
        timestamp: Date = Date()
    ) {
        self.name = name
        self.screenId = screenId
        self.componentId = componentId
        self.componentType = componentType
        self.locale = locale
        self.properties = properties
        self.timestamp = timestamp
    }
}

// MARK: - Handlers

/// Single-handler sink for action events. Hosts that prefer a delegate-style
/// integration over a closure can register one of these via
/// `App8.Instance.setEventHandler(_:)`. The instance holds it weakly.
@MainActor
public protocol App8EventHandler: AnyObject {
    func app8DidEmit(_ event: App8Event)
}

/// Single-handler sink for analytics events. Typical wiring: implement this
/// once in your analytics adapter and proxy `event.name` + `event.properties`
/// straight to your tracker.
@MainActor
public protocol App8AnalyticsHandler: AnyObject {
    func app8DidTrack(_ event: App8AnalyticsEvent)
}

// MARK: - Subscription

/// RAII token returned from `subscribe(...)` / `observeAnalytics(...)`. Hold
/// the reference for the lifetime you want to receive events; let it
/// deallocate (or call `cancel()`) to stop. Discarding without storing
/// cancels immediately.
public final class App8Subscription: @unchecked Sendable {
    private let cancelClosure: () -> Void
    private var cancelled = false
    private let lock = NSLock()

    init(cancel: @escaping () -> Void) {
        self.cancelClosure = cancel
    }

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return }
        cancelled = true
        cancelClosure()
    }

    deinit {
        cancel()
    }
}

// MARK: - Analytics config

/// Per-instance analytics configuration. Tune by mutating
/// `App8.Instance.analyticsConfig`. Changes apply to events fired after the
/// mutation; already-dispatched events are unaffected.
public struct App8AnalyticsConfig: Sendable {
    /// When `true` (default), the engine auto-fires `app8_screen_appeared`
    /// and `app8_screen_dismissed` on every DSL screen present/dismiss.
    /// Set `false` to suppress — author-declared analytics still fire.
    public var autoScreenEvents: Bool = true

    /// When `true` (default), the engine auto-fires `app8_component_tapped`
    /// on every `.tap` trigger, with `componentId` + `componentType`.
    public var autoComponentTaps: Bool = true

    /// When `true` (default), the engine auto-fires `app8_navigation_pushed`
    /// when a `.navigation` action runs (DSL→DSL navigation).
    public var autoNavigationEvents: Bool = true

    /// When `true` (default), the engine auto-fires `app8_url_opened` when
    /// an `.openURL` action runs.
    public var autoUrlEvents: Bool = true

    public init() {}
}
