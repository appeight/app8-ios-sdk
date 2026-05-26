# Analytics

The analytics bus is a second, independent channel separate from action events ([`events.md`](events.md)). It surfaces:

- **Auto-fired** `app8.*` events the engine and cloud SDK emit for built-in lifecycle moments — no authoring required.
- **Author-declared** events from an `analytics` JSON binding on a component — auto-prefixed with `app8.` at dispatch.

The two get the same payload shape and flow through the same `App8AnalyticsHandler`. The typical wiring is **one handler at app launch** that proxies every event to your analytics SDK (Mixpanel, Amplitude, Segment, …):

```swift
final class AnalyticsAdapter: App8AnalyticsHandler {
    func app8DidTrack(_ event: App8AnalyticsEvent) {
        Mixpanel.track(event.name, properties: event.properties)
    }
}
app8Instance.setAnalyticsHandler(AnalyticsAdapter())
```

`event.properties` is the canonical, fully-merged payload: the SDK injects screen/component/locale/version context into it at dispatch time using stable snake_case keys. You don't flatten anything yourself — the host integration is one line.

---

## Auto-fired events

The engine and cloud SDK fire these without any DSL authoring. They share the `app8.<domain>.<verb>` dotted hierarchy so they're trivially filtered in dashboards.

| Event | Fired by | When | Notable properties |
| --- | --- | --- | --- |
| `app8.screen.appeared` | engine | `viewDidAppear` of a DSL screen | `title` (when set) |
| `app8.screen.dismissed` | engine | `viewDidDisappear` of a DSL screen | `dwell_ms` |
| `app8.component.tapped` | engine | `.tap` trigger fires on any component | — |
| `app8.url.opened` | engine | `.openURL` action runs | `url` |
| `app8.navigation.pushed` | engine | `.navigation` action runs (DSL→DSL) | `from_screen_alias`, `to_screen_alias`, `presentation`, `is_back` |
| `app8.screen.rendered` | cloud | a `screen(id:)` / `startApp(...)` render succeeds | `kind`, `render_ms`, `served_version`, `requested_version`, `from_cache` |
| `app8.render.failed` | cloud | cloud render fails | `kind`, `reason`, optional `status` / `version` / `dsl_version_required` |
| `app8.render.fallback` | cloud | host-supplied fallback runs after a render failure | `kind`, `reason` |
| `app8.screen.shortcircuit` | cloud | availability is precomputed and the cloud short-circuits | `kind`, `reason` |

Every auto event also carries the canonical merge context — see [Canonical property keys](#canonical-property-keys) below. So `app8.screen.appeared` in your dashboard arrives with `screen_id`, `locale`, `engine_version`, `cloud_version` already populated as params, on top of `title`.

### `rendered` vs `appeared`

Two events, two questions:

- **`app8.screen.rendered`** — the engine successfully built a `UIViewController` for the screen. The host may or may not have presented it yet.
- **`app8.screen.appeared`** — `viewDidAppear` fired. The user is actually looking at the screen.

The funnel reads `rendered → appeared → tapped → navigated` — four verbs, four steps. Use `rendered` as the success-arm denominator alongside `render.failed`/`render.fallback`; use `appeared` as the user-visibility denominator.

### Configuring auto events

Per-instance toggles on `App8.Instance.analyticsConfig`:

```swift
var cfg = app8Instance.analyticsConfig
cfg.autoComponentTaps = false   // suppress app8.component.tapped firehose
app8Instance.analyticsConfig = cfg
```

All toggles default to `true`. Available:

| Toggle | Suppresses |
| --- | --- |
| `autoScreenEvents` | `app8.screen.appeared`, `app8.screen.dismissed` (engine lifecycle only) |
| `autoComponentTaps` | `app8.component.tapped` |
| `autoNavigationEvents` | `app8.navigation.pushed` |
| `autoUrlEvents` | `app8.url.opened` |
| `autoCloudEvents` | `app8.screen.rendered`, `app8.render.failed`, `app8.render.fallback`, `app8.screen.shortcircuit` (cloud SDK only) |

`autoCloudEvents` is read by `App8Cloud.Instance` only — engine-only callers can ignore it. `autoScreenEvents` only gates the engine's screen lifecycle; cloud render telemetry has its own gate.

---

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

This dispatches as `App8AnalyticsEvent(name: "app8.stripeConnectClicked", ...)`. **The SDK owns the prefix.** Author names get `app8.` prepended automatically — you don't write the prefix, the SDK does. This guarantees every customer's dashboards see the same prefix shape for the same authored binding, no per-host drift.

If you write a name that already starts with `app8.` (e.g. `"app8.foo"`), the SDK strips the leading `app8.` and re-prepends — idempotent — and logs a one-time console warning so you can clean up the source. If you write a name that collides with a reserved auto-event name (e.g. authoring `"screen.appeared"` becomes `app8.screen.appeared`), the SDK warns once and dispatches anyway.

### Full form — name + properties

```json
"analytics": {
    "tap": {
        "name": "userCardClicked",
        "properties": {
            "display_name": "{{name}}",
            "followers": "{{followers}}"
        }
    }
}
```

`properties` values support `{{var}}` interpolation in strings, same as `emit` payloads. The bus merges SDK-canonical context (`screen_id`, `component_id`, etc.) on top of your `properties` at dispatch — so your dashboard sees both `display_name` and `screen_id` as one flat dict. Use snake_case keys to match the canonical convention; if you write a key that collides with a canonical name (`screen_id`, `component_id`, `component_type`, `locale`, `engine_version`, `cloud_version`), the SDK value wins and a one-time console warning fires.

### Collection `onItemTap`

Track which item the user tapped without hand-rolling instrumentation. Inside a Collection's `analytics` map, `onItemTap` resolves the cell's data scope just like the action handler does — `{{item.id}}`, `{{item.title}}`, and every raw field from the row's data are available.

```json
{
    "type": "collection",
    "content": {
        "actions": {
            "onItemTap": { "type": "navigation", "nextScreen": "user-detail" }
        },
        "analytics": {
            "onItemTap": {
                "name": "userListItemTapped",
                "properties": { "user_id": "{{item.id}}", "rank": "{{$index}}" }
            }
        }
    }
}
```

The auto `app8.component.tapped` event does **not** fire for individual cells inside a Collection (the Collection itself is the tappable component) — use `onItemTap` analytics if you want per-item tracking.

### TableView row analytics

Static rows in a `tableView` can each carry their own `analytics` binding. The auto `app8.component.tapped` event fires per row with `componentId = row.id` and `componentType = "tableViewRow"`, even when no author-declared binding is present.

```json
{
    "id": "settings-row-delete",
    "actions": {
        "tap": [{ "type": "showAlert", "alertTitle": "Delete account?" }]
    },
    "analytics": {
        "tap": "settingsDeleteRowTapped"
    }
}
```

### Action events vs analytics: when to use which

| You want… | Channel |
| --- | --- |
| "Host, do X when the user taps this." | `emit` action |
| "Track that this happened, but don't change the app's behavior." | `analytics` binding |
| Both | Declare both on the same component — they're independent. |

**Naming convention.** Action events use **dotted lowercase** (`connect.tapped`, `user.selected`) — see [`events.md`](events.md). Analytics events use **camelCase suffixes that the SDK prefixes with `app8.`** (`stripeConnectClicked` → `app8.stripeConnectClicked`). The two channels are independent on purpose, so the names can diverge.

---

## Canonical property keys

The analytics bus injects six canonical keys into every dispatched event's `properties` dict at dispatch time. Stable, unprefixed snake_case. Omitted entirely when the underlying typed field is nil.

| Key | Source | Notes |
| --- | --- | --- |
| `screen_id` | `event.screenId` | The host-requested alias, never the DSL internal id (see [events.md screenId discussion](events.md#screenid-is-the-alias-you-requested-not-the-dsl-documents-id)) |
| `component_id` | `event.componentId` | Leaf component id; omitted for screen-lifecycle events |
| `component_type` | `event.componentType` | DSL type token (`button`, `view`, `tableViewRow`, …) |
| `locale` | `event.locale` | Active `TranslationStore.activeLocale` at fire time |
| `engine_version` | `EngineVersion.current` | Always present |
| `cloud_version` | bus-level | Set by the cloud SDK at init; absent on engine-only instances |

`App8AnalyticsEvent.canonicalKeys` is the public single source of truth.

---

## The event payload

```swift
public struct App8AnalyticsEvent {
    public let name: String
    public let screenId: String?       // the alias YOU requested, see below
    public let componentId: String?
    public let componentType: String?
    public let locale: String?
    public let engineVersion: String   // stamped by the bus
    public let cloudVersion: String?   // stamped by the bus when cloud SDK is in use
    public let properties: [String: Any]
    public let timestamp: Date
}
```

Top-level accessors are conveniences. **`event.properties` is the canonical payload** — host integrators forward it as-is.

`event.screenId` is **the screen id the host asked for** — the value passed to `App8.Instance.renderScreen(screenId:)` or `App8Cloud.Instance.screen(id:)` — NOT the DSL document's internal `"id"` field. See [events.md](events.md#screenid-is-the-alias-you-requested-not-the-dsl-documents-id) for the full discussion; the rule is identical on both buses.

---

## Subscription surfaces

Same shape as action events — pick whichever fits:

```swift
// Delegate (typical: one handler at app launch)
app8Instance.setAnalyticsHandler(MyAdapter())

// Closure
let sub = app8Instance.observeAnalytics { event in /* … */ }

// Combine
app8Instance.analytics
    .filter { $0.name.hasPrefix("app8.") }
    .sink { /* … */ }

// AsyncStream
for await event in app8Instance.analyticsStream { /* … */ }
```

---

## Redact hook (PII boundary)

The analytics bus exposes a `redact` closure for stripping PII before it reaches subscribers. Set it once at app launch on `App8.Instance.analyticsBus`:

```swift
app8Instance.analyticsBus.redact = { event in
    // Strip the query string from app8.url.opened.
    guard event.name == App8AnalyticsEvent.Auto.urlOpened,
          var urlString = event.properties["url"] as? String,
          let qIdx = urlString.firstIndex(of: "?") else { return event }
    urlString = String(urlString[..<qIdx])
    var props = event.properties
    props["url"] = urlString
    return event._withProperties(props)
}
```

- Return `nil` → the event is dropped (no subscriber sees it).
- Return a mutated copy → it substitutes the original.
- The closure runs **after** version stamping and the canonical-property merge — `event.properties["engine_version"]` is already populated when your closure sees the event.
- The action bus (`App8EventBus`) has **no** redact hook — host imperatives aren't third-party-bound data.

---

## Cloud SDK

`App8Cloud.Instance` exposes the same API. The cloud SDK additionally fires:

- `app8.screen.rendered` on every successful screen / app render — funnel denominator.
- `app8.render.failed` when a `screen(...)` call fails.
- `app8.render.fallback` when a host-supplied fallback runs.
- `app8.screen.shortcircuit` when availability is precomputed and the cloud short-circuits.

All four are gated by `analyticsConfig.autoCloudEvents` (default `true`). Engine events and cloud events flow through the same analytics handler — the host wires one adapter and sees everything.

---

## Notes on data

- **PII in `url`.** `app8.url.opened` includes the full resolved URL including query string. The SDK does not scrub by default — use the `redact` hook above to scrub at the bus boundary.
- **No buffering.** Events emitted before a handler is registered are lost. Register early (typically in `SceneDelegate` / `AppDelegate`).
- **Synchronous dispatch.** Handlers run on the main actor in subscription order.
