# Analytics

The analytics bus is a second, independent channel separate from action events ([`events.md`](events.md)). It surfaces:

- **Auto-fired** `app8_*` events the engine emits for built-in lifecycle moments — no authoring required.
- **Author-declared** events from an `analytics` JSON binding on a component.

The two get the same payload shape and flow through the same `App8AnalyticsHandler`. The typical wiring is **one handler at app launch** that proxies every event to your analytics SDK (Mixpanel, Amplitude, Segment, …).

```swift
final class AnalyticsAdapter: App8AnalyticsHandler {
    func app8DidTrack(_ event: App8AnalyticsEvent) {
        Mixpanel.track(event.name, properties: event.properties)
    }
}
app8Instance.setAnalyticsHandler(AnalyticsAdapter())
```

---

## Auto-fired events

The engine fires these without any DSL authoring. They share the `app8_*` prefix so they're trivially filtered in dashboards.

| Event | When | Notable properties |
| --- | --- | --- |
| `app8_screen_appeared` | `viewDidAppear` of a DSL screen | `screenId`, `title` (when set) |
| `app8_screen_dismissed` | `viewDidDisappear` of a DSL screen | `screenId`, `dwellMs` |
| `app8_component_tapped` | `.tap` trigger fires on any component | `screenId`, `componentId`, `componentType` |
| `app8_url_opened` | `.openURL` action runs | `screenId`, `componentId`, `url` |
| `app8_navigation_pushed` | `.navigation` action runs (DSL→DSL) | `fromScreenId`, `toScreenId`, `presentation`, `isBack` |
| `app8_render_failed` *(Cloud SDK)* | cloud render fails or falls back | `kind`, `reason`, optional `status` / `version` / `dslVersionRequired` |

### Configuring auto events

Per-instance toggles on `App8.Instance.analyticsConfig`:

```swift
var cfg = app8Instance.analyticsConfig
cfg.autoComponentTaps = false   // suppress app8_component_tapped firehose
app8Instance.analyticsConfig = cfg
```

All toggles default to `true`. Available: `autoScreenEvents`, `autoComponentTaps`, `autoNavigationEvents`, `autoUrlEvents`.

## Author-declared analytics

Add an `analytics` map alongside `actions` on any component. Same trigger keys (`tap`, `longPress`, `onItemTap`, …).

### Shorthand — string event name

```json
{
    "id": "connectButton",
    "type": "view",
    "content": {
        "actions": {
            "tap": { "type": "emit", "name": "connect.tapped" }
        },
        "analytics": {
            "tap": "stripeConnectClicked"
        }
    }
}
```

Fires `App8AnalyticsEvent(name: "stripeConnectClicked", properties: [:], ...)`.

### Full form — name + properties

```json
"analytics": {
    "tap": {
        "name": "creatorCardClicked",
        "properties": {
            "creatorName": "{{name}}",
            "followers": "{{followers}}"
        }
    }
}
```

`properties` values support `{{var}}` interpolation in strings, same as `emit` payloads.

### Action events vs analytics: when to use which

| You want… | Channel |
| --- | --- |
| "Host, do X when the user taps this." | `emit` action |
| "Track that this happened, but don't change the app's behavior." | `analytics` binding |
| Both | Declare both on the same component — they're independent. |

**Naming convention.** Action events use **dotted lowercase** (`connect.tapped`, `creator.selected`) — see [`events.md`](events.md). Analytics events use **camelCase** (`stripeConnectClicked`, `creatorCardClicked`) — matches your existing analytics SDK conventions. The two channels are independent on purpose, so the names can diverge.

## The event payload

```swift
public struct App8AnalyticsEvent {
    public let name: String
    public let screenId: String?
    public let componentId: String?
    public let componentType: String?
    /// Translation locale active at fire time (e.g. `"en"`, `"de-DE"`).
    /// Source: `TranslationStore.activeLocale`. Useful for funnel parity
    /// across languages.
    public let locale: String?
    public let properties: [String: Any]
    public let timestamp: Date
}
```

## Subscription surfaces

Same shape as action events — pick whichever fits:

```swift
// Delegate (typical: one handler at app launch)
app8Instance.setAnalyticsHandler(MyAdapter())

// Closure
let sub = app8Instance.observeAnalytics { event in /* … */ }

// Combine
app8Instance.analytics
    .filter { $0.name.hasPrefix("app8_") }
    .sink { /* … */ }

// AsyncStream
for await event in app8Instance.analyticsStream { /* … */ }
```

## Cloud SDK

`App8Cloud.Instance` exposes the same API. The cloud SDK additionally fires `app8_render_failed` on the analytics bus when a `screen(...)` call fails or invokes a fallback — host's analytics handler sees engine events and cloud errors uniformly.

## Notes on data

- **PII in `url`.** `app8_url_opened` includes the full resolved URL including query string. The SDK does not scrub — that's the host's responsibility.
- **No buffering.** Events emitted before a handler is registered are lost. Register early (typically in `SceneDelegate` / `AppDelegate`).
- **Synchronous dispatch.** Handlers run on the main actor in subscription order.
