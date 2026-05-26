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
    /// (e.g. `connect.tapped`, `user.selected`). Free-form — App8 does
    /// not reserve any namespace except `app8.*` analytics events (which
    /// flow on a separate bus, see `App8AnalyticsEvent`).
    public let name: String

    /// The host-requested screen alias (the string the host passed to
    /// `App8.Instance.renderScreen(screenId:)` or
    /// `App8Cloud.Instance.screen(id:)`), not the DSL document's internal
    /// `"id"` field. See `docs/dsl/events.md` for the full discussion.
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

    /// Engine version that produced the event. Stamped by `App8EventBus`
    /// at dispatch time from `EngineVersion.current` — emit sites pass `""`
    /// and let the bus overwrite. Always non-empty on events the host
    /// receives.
    public let engineVersion: String

    /// Cloud SDK version, when the bus has been taught by cloud SDK init
    /// (`A8CInstance` sets `eventBus.cloudVersion = SDKVersion.current` once
    /// on construction). `nil` for engine-only callers — the engine ships
    /// without a hard cloud dependency, so `cloudVersion` is opt-in.
    public let cloudVersion: String?

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
        engineVersion: String = "",
        cloudVersion: String? = nil,
        payload: [String: Any],
        timestamp: Date = Date()
    ) {
        self.name = name
        self.screenId = screenId
        self.componentId = componentId
        self.componentType = componentType
        self.locale = locale
        self.engineVersion = engineVersion
        self.cloudVersion = cloudVersion
        self.payload = payload
        self.timestamp = timestamp
    }

    /// Returns a copy with `engineVersion` / `cloudVersion` overwritten. Bus
    /// uses this to stamp version metadata onto outgoing events while keeping
    /// the public `let`-property contract immutable.
    internal func _stamped(engineVersion: String, cloudVersion: String?) -> App8Event {
        App8Event(
            name: name,
            screenId: screenId,
            componentId: componentId,
            componentType: componentType,
            locale: locale,
            engineVersion: engineVersion,
            cloudVersion: cloudVersion,
            payload: payload,
            timestamp: timestamp
        )
    }
}

// MARK: - App8AnalyticsEvent

/// An analytics event fired by the engine. Two sources:
///
/// 1. **Author-declared** via an `analytics` JSON binding on a component
///    (e.g. `"analytics": { "tap": "stripeConnectClicked" }`). Names are
///    auto-prefixed with `app8.` at the emit site — `stripeConnectClicked`
///    lands on the bus as `app8.stripeConnectClicked`.
/// 2. **Auto-fired** by the engine for built-in lifecycle moments. Canonical
///    names live under `App8AnalyticsEvent.Auto` (e.g. `app8.screen.appeared`,
///    `app8.component.tapped`). See `App8AnalyticsConfig` for gating.
///
/// `event.properties` is the canonical, fully-merged payload: author-supplied
/// keys plus SDK-canonical context (`screen_id`, `component_id`,
/// `component_type`, `locale`, `engine_version`, `cloud_version`) injected
/// by the bus at dispatch time using snake_case unprefixed keys. The merge
/// is non-destructive in the opposite direction: any author key whose name
/// collides with a canonical key is overwritten by the SDK value (a console
/// warning fires once per offending name per instance). Integration:
///
/// ```swift
/// func app8DidTrack(_ event: App8AnalyticsEvent) {
///     Mixpanel.track(event.name, properties: event.properties)
/// }
/// ```
///
/// Top-level Swift accessors (`screenId`, `componentId`, etc.) remain as
/// conveniences; `properties` is the source of truth for host adapters.
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
    /// Engine version that produced the event. Stamped by `App8AnalyticsBus`
    /// at dispatch time from `EngineVersion.current` — emit sites pass `""`
    /// and let the bus overwrite. Always non-empty on events the host
    /// receives.
    public let engineVersion: String
    /// Cloud SDK version, when the bus has been taught by cloud SDK init
    /// (`A8CInstance` sets `analyticsBus.cloudVersion = SDKVersion.current`
    /// once on construction). `nil` for engine-only callers.
    public let cloudVersion: String?
    public let properties: [String: Any]
    public let timestamp: Date

    public init(
        name: String,
        screenId: String? = nil,
        componentId: String? = nil,
        componentType: String? = nil,
        locale: String? = nil,
        engineVersion: String = "",
        cloudVersion: String? = nil,
        properties: [String: Any] = [:],
        timestamp: Date = Date()
    ) {
        self.name = name
        self.screenId = screenId
        self.componentId = componentId
        self.componentType = componentType
        self.locale = locale
        self.engineVersion = engineVersion
        self.cloudVersion = cloudVersion
        self.properties = properties
        self.timestamp = timestamp
    }

    /// Returns a copy with `engineVersion` / `cloudVersion` overwritten. Bus
    /// uses this to stamp version metadata onto outgoing events while keeping
    /// the public `let`-property contract immutable.
    internal func _stamped(engineVersion: String, cloudVersion: String?) -> App8AnalyticsEvent {
        App8AnalyticsEvent(
            name: name,
            screenId: screenId,
            componentId: componentId,
            componentType: componentType,
            locale: locale,
            engineVersion: engineVersion,
            cloudVersion: cloudVersion,
            properties: properties,
            timestamp: timestamp
        )
    }

    /// Returns a copy with `properties` replaced. Bus uses this after merging
    /// SDK-canonical context (`screen_id`, etc.) into the author-supplied dict.
    internal func _withProperties(_ properties: [String: Any]) -> App8AnalyticsEvent {
        App8AnalyticsEvent(
            name: name,
            screenId: screenId,
            componentId: componentId,
            componentType: componentType,
            locale: locale,
            engineVersion: engineVersion,
            cloudVersion: cloudVersion,
            properties: properties,
            timestamp: timestamp
        )
    }
}

// MARK: - Canonical event-name registry (`App8AnalyticsEvent.Auto`)

extension App8AnalyticsEvent {
    /// SDK-fired auto-event names. Use these constants instead of string
    /// literals at emit sites so a future rename is one edit. The SDK reserves
    /// the `app8.*` namespace — author-declared events that collide with one
    /// of these names trigger a console warning (dispatch still happens).
    public enum Auto {
        public static let screenAppeared    = "app8.screen.appeared"
        public static let screenDismissed   = "app8.screen.dismissed"
        public static let screenRendered    = "app8.screen.rendered"
        public static let screenShortcircuit = "app8.screen.shortcircuit"
        public static let componentTapped   = "app8.component.tapped"
        public static let navigationPushed  = "app8.navigation.pushed"
        public static let urlOpened         = "app8.url.opened"
        public static let renderFailed      = "app8.render.failed"
        public static let renderFallback    = "app8.render.fallback"
    }

    /// Names reserved for SDK auto-events. Used by the emit-site author-name
    /// normalizer to warn when an author binding collides with an auto-event
    /// name.
    public static let reservedNames: Set<String> = [
        Auto.screenAppeared,
        Auto.screenDismissed,
        Auto.screenRendered,
        Auto.screenShortcircuit,
        Auto.componentTapped,
        Auto.navigationPushed,
        Auto.urlOpened,
        Auto.renderFailed,
        Auto.renderFallback,
    ]

    /// Canonical property keys the analytics bus merges into `event.properties`
    /// at dispatch time. Stable, unprefixed snake_case. Author bindings that
    /// write a property with one of these keys trigger a console warning (the
    /// SDK-canonical value wins). Single source of truth — the bus's merge
    /// step iterates this set looking at typed fields; emit-site collision
    /// checks use the same set.
    public static let canonicalKeys: Set<String> = [
        "screen_id",
        "component_id",
        "component_type",
        "locale",
        "engine_version",
        "cloud_version",
    ]
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
    /// When `true` (default), the engine auto-fires `app8.screen.appeared`
    /// and `app8.screen.dismissed` on every DSL screen present/dismiss.
    /// Set `false` to suppress — author-declared analytics still fire.
    public var autoScreenEvents: Bool = true

    /// When `true` (default), the engine auto-fires `app8.component.tapped`
    /// on every `.tap` trigger, with `componentId` + `componentType`.
    public var autoComponentTaps: Bool = true

    /// When `true` (default), the engine auto-fires `app8.navigation.pushed`
    /// when a `.navigation` action runs (DSL→DSL navigation).
    public var autoNavigationEvents: Bool = true

    /// When `true` (default), the engine auto-fires `app8.url.opened` when
    /// an `.openURL` action runs.
    public var autoUrlEvents: Bool = true

    /// When `true` (default), the cloud SDK auto-fires its render-lifecycle
    /// events: `app8.screen.rendered` on success, `app8.render.failed` on
    /// failure, `app8.render.fallback` when a fallback path runs, and
    /// `app8.screen.shortcircuit` when availability is precomputed.
    /// Set `false` to suppress all four cloud-fired events.
    ///
    /// Engine-only callers can ignore this toggle — it's read by
    /// `App8Cloud.Instance` only.
    public var autoCloudEvents: Bool = true

    public init() {}
}
