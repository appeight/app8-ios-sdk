# Events

App8 has two complementary channels for getting information out of a DSL screen and into the host app:

1. **Action events** — sparse, intentional, typed. The DSL author writes `emit` actions; the host registers handlers and routes by `event.name`. Use when you want the host to *do* something in response to a user interaction.
2. **Analytics events** — dense, observational, named for product tracking. Author-declared via the `analytics` JSON binding, plus auto-fired `app8_*` events the engine emits without authoring. Use for funnels, dashboards, and analytics SDKs. See [`analytics.md`](analytics.md).

This page covers channel 1. Skip to [`analytics.md`](analytics.md) for channel 2.

---

## Emit action — DSL side

Inside any component's `actions` map, declare a trigger that fires the new `emit` action:

```json
{
    "id": "connectButton",
    "type": "view",
    "content": {
        "actions": {
            "tap": {
                "type": "emit",
                "name": "connect.tapped",
                "payload": { "source": "dsl" }
            }
        }
    }
}
```

**Fields.**

- `type`: `"emit"`.
- `name` *(required)*: dotted lowercase. Convention: `<domain>.<verb>` — `connect.tapped`, `creator.selected`, `payment.started`. Free-form — App8 reserves only the `app8_*` namespace on the analytics bus, never on this bus.
- `payload` *(optional)*: arbitrary JSON object. Values support `{{var}}` interpolation in string positions against the component's variable scope. Other scalars pass through unchanged.

## Chained actions

A trigger can run multiple actions in JSON order — emit *and* navigate, for example:

```json
"actions": {
    "tap": [
        { "type": "emit",       "name": "checkout.started", "payload": { "cart": "{{cartId}}" } },
        { "type": "navigation", "nextScreen": "confirm" }
    ]
}
```

Single-object form keeps working for the common case. Mixing `emit` with `navigation`/`openURL`/`setState`/`haptic`/etc. is the intended pattern.

## Host side — Swift API

### Closure

```swift
import App8Engine

let sub = app8Instance.subscribe { event in
    switch event.name {
    case "connect.tapped":
        startStripeFlow()
    case "creator.selected":
        showCreator(named: event.payload["name"] as? String ?? "")
    default:
        break
    }
}
// keep `sub` alive for as long as you want to receive events
```

Filter at subscribe-time when you only care about one event or one screen:

```swift
app8Instance.subscribe(to: "creator.selected") { event in /* … */ }
app8Instance.subscribe(onScreen: "demo-main-creators") { event in /* … */ }
```

### Combine

```swift
import Combine

let cancellable = app8Instance.events
    .filter { $0.name == "connect.tapped" }
    .sink { event in /* … */ }
```

### AsyncStream

```swift
Task {
    for await event in app8Instance.eventStream {
        // …
    }
}
```

### Delegate (Obj-C friendly)

```swift
final class MyHandler: App8EventHandler {
    func app8DidEmit(_ event: App8Event) { /* … */ }
}
app8Instance.setEventHandler(MyHandler())   // held weakly
```

## The event payload

```swift
public struct App8Event {
    public let name: String           // "connect.tapped"
    public let screenId: String       // "demo-main-constraints"
    public let componentId: String?   // "connectButton" (JSON leaf id)
    public let componentType: String? // "view"
    public let payload: [String: Any] // already interpolated
    public let timestamp: Date
}
```

`payload` strings are resolved at emit-time against the component's variable scope — by the time the host sees them, `{{name}}` has been replaced with the actual value.

## Cloud SDK

`App8Cloud.Instance` exposes the same API verbatim — `subscribe(...)`, `events`, `eventStream`, `setEventHandler(_:)`. Subscribing to the cloud instance subscribes to the underlying engine, so events from a screen rendered by the cloud SDK land in the same handler.

```swift
cloudInstance.subscribe { event in /* … */ }
```

## Notes

- Subscribers fire synchronously, in subscription order, on the main actor.
- Re-entrancy is allowed: a handler triggering another DSL action (e.g. `instance.dispatch(...)` in v2) is fine.
- Dropping the returned `App8Subscription` cancels the subscription. Hold a reference for the lifetime you want events.
- The bus has no buffering — events fired before a subscriber is attached are lost.

## Migration from URL-scheme deeplinks

Previously the only way to surface a DSL interaction was to author an `openURL` action with a custom scheme and parse it in `SceneDelegate`. Replace this pattern outright — even the demo migrated. URL schemes are now reserved for *actual* external deeplinks (universal links, app-to-app handoffs).

**Before:**

```json
"actions": { "tap": { "type": "openURL", "url": "myapp://connect?source=dsl" } }
```

**After:**

```json
"actions": { "tap": { "type": "emit", "name": "connect.tapped", "payload": { "source": "dsl" } } }
```
