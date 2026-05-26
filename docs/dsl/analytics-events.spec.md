# App8 Analytics Events — Canonical Specification

Cross-platform canonical registry. **Single source of truth** for iOS today, future Android, and every dashboard / data-pipeline that consumes App8 telemetry. Anything the iOS SDK fires must match this doc; anything Android adds must match this doc; any new auto-event PR updates this doc in the same change.

For host-side how-to and integration patterns, see [`analytics.md`](analytics.md). This file is the contract.

---

## Naming

All SDK-fired events use the dotted hierarchy `app8.<domain>.<verb>`. Author-declared events get `app8.` prepended automatically at dispatch (`stripeConnectClicked` → `app8.stripeConnectClicked`).

The SDK owns the prefix. Hosts never write it; hosts never strip it. Customers' dashboards see the same prefix shape for the same authored binding — no per-customer drift.

### Author-name normalization rules

| Author input | Wire value | Notes |
| --- | --- | --- |
| `"stripeConnectClicked"` | `app8.stripeConnectClicked` | Standard auto-prefix |
| `"app8.foo"` | `app8.foo` | Strip leading `app8.`, re-prepend; warn once |
| `"screen.appeared"` | `app8.screen.appeared` | Collides with reserved auto-event; warn once; dispatch anyway |
| `"app8."` | `app8.` (raw) | Defensive guard — empty after strip; falls back to raw input |

Warnings dedup once per offending name per `App8.Instance` lifetime.

---

## Reserved auto-events (9)

Constants live on `App8AnalyticsEvent.Auto.*` — use those at emit sites, not string literals.

### `app8.screen.appeared`

| | |
| --- | --- |
| **Fired by** | engine — `ScreenViewController.viewDidAppear` |
| **Gating** | `analyticsConfig.autoScreenEvents` |
| **Constant** | `App8AnalyticsEvent.Auto.screenAppeared` |

| Property | Type | Notes |
| --- | --- | --- |
| `title` | string | Optional — set when navigation bar declares one |

### `app8.screen.dismissed`

| | |
| --- | --- |
| **Fired by** | engine — `ScreenViewController.viewDidDisappear` |
| **Gating** | `analyticsConfig.autoScreenEvents` |
| **Constant** | `App8AnalyticsEvent.Auto.screenDismissed` |

| Property | Type | Notes |
| --- | --- | --- |
| `dwell_ms` | int | Wall-clock ms between appeared and dismissed |

### `app8.screen.rendered`

| | |
| --- | --- |
| **Fired by** | cloud — `A8CInstance.fireRenderEvent` after `screen(id:)` / `startApp(...)` success |
| **Gating** | `analyticsConfig.autoCloudEvents` |
| **Constant** | `App8AnalyticsEvent.Auto.screenRendered` |

| Property | Type | Notes |
| --- | --- | --- |
| `kind` | string | `"screen"` or `"app"` |
| `render_ms` | int | Wall-clock ms from request to VC returned |
| `served_version` | string | DSL document version actually served (nullable) |
| `requested_version` | string | Version requested by host (nullable) |
| `from_cache` | bool | `true` if served from cache, `false` if fetched |

`screenId` is the host-requested alias for screen renders; `"<app>"` sentinel for app-level renders.

### `app8.screen.shortcircuit`

| | |
| --- | --- |
| **Fired by** | cloud — availability is precomputed; the cloud short-circuits |
| **Gating** | `analyticsConfig.autoCloudEvents` |
| **Constant** | `App8AnalyticsEvent.Auto.screenShortcircuit` |

### `app8.component.tapped`

| | |
| --- | --- |
| **Fired by** | engine — `.tap` trigger on any component |
| **Gating** | `analyticsConfig.autoComponentTaps` |
| **Constant** | `App8AnalyticsEvent.Auto.componentTapped` |

`componentId` / `componentType` carry the DSL identifiers; for TableView rows, `componentType == "tableViewRow"` and `componentId` is the row's id.

### `app8.navigation.pushed`

| | |
| --- | --- |
| **Fired by** | engine — `.navigation` action runs (DSL→DSL navigation) |
| **Gating** | `analyticsConfig.autoNavigationEvents` |
| **Constant** | `App8AnalyticsEvent.Auto.navigationPushed` |

| Property | Type | Notes |
| --- | --- | --- |
| `from_screen_alias` | string | Host-requested alias of source screen |
| `to_screen_alias` | string | Optional — alias of next screen |
| `presentation` | string | Optional — `"push"` / `"modal"` / etc. |
| `is_back` | bool | Optional — `true` if a back-navigation |

**Why `_alias` not `_id`**: the engine has no reverse alias→DSL-id map at navigation time. These keys reflect the host-facing alias the host passed in, not the DSL document's internal id.

### `app8.url.opened`

| | |
| --- | --- |
| **Fired by** | engine — `.openURL` action runs |
| **Gating** | `analyticsConfig.autoUrlEvents` |
| **Constant** | `App8AnalyticsEvent.Auto.urlOpened` |

| Property | Type | Notes |
| --- | --- | --- |
| `url` | string | Full resolved URL including query string — use `redact` hook to scrub |

### `app8.render.failed`

| | |
| --- | --- |
| **Fired by** | cloud — `A8CInstance` on render failure |
| **Gating** | `analyticsConfig.autoCloudEvents` |
| **Constant** | `App8AnalyticsEvent.Auto.renderFailed` |

| Property | Type | Notes |
| --- | --- | --- |
| `kind` | string | `"screen"` or `"app"` |
| `reason` | string | One of the cloud SDK's failure-reason tokens |
| `status` | int | Optional HTTP status |
| `version` | string | Optional version that failed |
| `dsl_version_required` | string | Optional DSL version the host's engine doesn't support |
| `dsl_version_client_max` | string | Optional max DSL version the engine declares |

### `app8.render.fallback`

| | |
| --- | --- |
| **Fired by** | cloud — host-supplied fallback path runs after render failure |
| **Gating** | `analyticsConfig.autoCloudEvents` |
| **Constant** | `App8AnalyticsEvent.Auto.renderFallback` |

| Property | Type | Notes |
| --- | --- | --- |
| `kind` | string | `"screen"` or `"app"` |
| `reason` | string | Why the fallback was invoked |

---

## Canonical properties (merged onto every event)

The analytics bus merges these into `event.properties` at dispatch using stable snake_case unprefixed keys. **Keys are omitted entirely when the underlying typed field is nil — no null pollution.**

`App8AnalyticsEvent.canonicalKeys` is the public single source of truth (Set<String>).

| Key | Source | Always present? |
| --- | --- | --- |
| `screen_id` | `event.screenId` | When set — usually yes |
| `component_id` | `event.componentId` | No — absent for screen-lifecycle events |
| `component_type` | `event.componentType` | No — absent when no component anchor |
| `locale` | `event.locale` | Yes when engine has a translation store |
| `engine_version` | `EngineVersion.current` | Always (non-empty) |
| `cloud_version` | bus-level | Only when cloud SDK is in use |

### Author-property collision policy

If an author binding writes a `properties: { "<canonical_key>": ... }`, the SDK-canonical value wins. A console warning fires once per `(binding-name, key)` pair per `App8.Instance` lifetime. Authors should rename their keys.

---

## Funnel disambiguation

`app8.screen.rendered` is **not** the same as `app8.screen.appeared`. Both must exist for a complete funnel:

| Event | Means | Use as |
| --- | --- | --- |
| `app8.screen.rendered` | Engine built a `UIViewController` for the screen | Success-arm denominator (paired with `render.failed` / `render.fallback`) |
| `app8.screen.appeared` | `viewDidAppear` fired — user is looking at the screen | User-visibility denominator |
| `app8.component.tapped` | User interacted with a component | Engagement |
| `app8.navigation.pushed` | App navigated away | Funnel step transition |

The funnel reads `rendered → appeared → tapped → navigated` — four verbs, four steps.

---

## Redact hook contract

`App8AnalyticsBus.redact: ((App8AnalyticsEvent) -> App8AnalyticsEvent?)?`

**Pipeline ordering** (per dispatch):

1. Stamp `engineVersion` + `cloudVersion`.
2. Merge canonical context into `properties`.
3. Run `redact` (if set).
4. Fan out to subscribers.

Return semantics:

- `nil` → drop the event silently. No subscriber sees it.
- non-nil → substitute. The returned event is fanned out.

The closure is non-throwing (signature `(App8AnalyticsEvent) -> App8AnalyticsEvent?`). Hosts that need conditional drops return `nil`; hosts that need to surface an internal error log it themselves before returning.

**No `redact` on the action bus.** Host imperatives aren't third-party-bound data; `payload` reaches the host adapter unmodified.

---

## Versioning

`engineVersion` and `cloudVersion` are stamped at the bus boundary. Emit sites construct events with empty `engineVersion`; the bus overwrites with `EngineVersion.current`. The cloud SDK teaches the bus its version once at init (`engine.analyticsBus.cloudVersion = SDKVersion.current`), and every subsequent dispatch auto-stamps `cloudVersion`.

Engine-only callers (no cloud SDK in the app) get `cloudVersion == nil` and no `cloud_version` key in `properties`.

---

## Implementation invariants (test these)

- Every key in `App8AnalyticsEvent.canonicalKeys` is injected by the bus when its source field is non-nil — adding a key to the constant means adding a case to the merge function.
- Action bus never merges canonical keys into `payload` — `event.payload` is exactly what the DSL author wrote.
- `app8.screen.rendered` fires ONLY on the success path. Failure / fallback paths fire their respective events and never `rendered`.
- Author-name normalization is idempotent: `"app8.foo"` → `"app8.foo"` regardless of how many times it bounces through.
- Warning dedup is per `App8.Instance`: same collision firing 100 times → one log line.
