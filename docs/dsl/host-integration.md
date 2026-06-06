# Host Integration

The engine never fetches anything itself. The **host app** supplies all content through one protocol — `App8DataSource` — and receives runtime events through two buses. This page is the bridge between the DSL (what authors write) and the Swift host (what serves and reacts to it).

> New to the SDK? Start with the [README Quick Start](../../README.md#quick-start) for the bootstrap (`App8.instance(dataSource:)` → `startApp()`). This page details the data surfaces the DSL relies on.

---

## `App8DataSource`

Implement this protocol to feed the engine. Only the core reads are required; the rest have default implementations.

| Method | Returns | Purpose |
|--------|---------|---------|
| `getApp()` | `Data` | The app manifest (`app`, `navigation`, `screens`, `templates`) |
| `getStyles()` | `[Data]` | Shared style entities referenced by [style pointers](styles.md#style-pointers-advanced) |
| `getScreen(screenId:)` | `Data` | A single screen definition |
| `getComponent(componentId:)` | `Data` | A reusable component definition |
| `getComponents()` | `[Data]` | Preloaded shared components |
| `getDatasource(screenId:datasourceId:)` | `Data` | A [datasource](#datasources) file (e.g. `"datasources/listings"`) |
| `getAsset(assetId:assetName:)` | `Data?` | Raw bytes for an image/asset — see [Assets](#assets) |
| `getTranslations()` | `Data` | The i18n [translation bundle](localization.md#translation-bundle) |
| `getAllScreenIds()` | `[String]?` | Optional — enables orphan-screen diagnostics |
| `streamScreen(_:)` / `streamDatasource(...)` / `streamStyles()` | `AsyncStream<Data>?` | Optional — [live updates](#live-updates--streaming) |

Each method returns JSON `Data`. A bundle-backed implementation just reads files; a server-backed one makes network calls — the DSL is identical either way.

---

## Datasources

A **datasource** is an external JSON file of data that the DSL binds to without hardcoding it inline. An author points a variable at one with the `source` field; the engine calls `getDatasource(screenId:datasourceId:)` to load it.

**DSL side** — bind a variable to a datasource ([variables.md](variables.md#variable-definition)):

```json
"variables": {
  "listings": { "type": "array", "source": "datasources/listings" }
}
```

**Host side** — `getDatasource(screenId:, datasourceId: "datasources/listings")` returns the file. Two shapes are accepted:

```json
// Wrapped — schema is stored for tooling but not enforced at runtime
{ "schema": { }, "data": [ { "id": "1", "title": "Loft" } ] }
```

```json
// Raw — the array (or object) directly
[ { "id": "1", "title": "Loft" } ]
```

The `data` value populates the variable. Use [`schema`](variables.md#object-variables-with-schema) on the variable to document the expected shape for navigation params and tooling.

---

## Assets

`image` components resolve their bytes through the data source. When a screen references a remote image, the engine asks the host for it via `getAsset(assetId:assetName:)`. Returning `nil` lets the component fall back to its declared URL.

To **prefetch** — warm the cache before a screen appears so images render instantly — the instance can walk a screen's DSL and hand you exactly the asset (and font) references it needs:

- `collectAssetReferences(screenId:)` / `collectAllAssetReferences()` — enumerate referenced assets
- `prefetchImages(forScreens:)` / `prefetchAllImages()` — warm the URL cache

This keeps delivery lean: only what a screen actually references is fetched, not the whole catalog.

---

## Live Updates & Streaming

The streaming methods let content change *after* a screen is on screen — for live editing, server-pushed updates, or collaboration. Each returns an `AsyncStream<Data>?`; return `nil` to opt out.

| Stream | Granularity | Effect |
|--------|-------------|--------|
| `streamScreen(screenId:)` | Whole screen | Re-renders the screen with a new definition (structural) |
| `streamDatasource(screenId:datasourceId:componentPath:)` | Data only | Updates bound variable values — **no re-render** (fast path) |
| `streamStyles()` | Style primitives | Re-applies all styles without reloading screens |

Prefer `streamDatasource` for value changes (a price ticking, a list growing) — it skips the structural rebuild. Reserve `streamScreen` for layout changes.

---

## Receiving Events

DSL screens fire two independent typed streams into the host. Both are documented in depth on their own pages; this is the orientation.

| Bus | Carries | Wire it for | Reference |
|-----|---------|-------------|-----------|
| **Event bus** | `.emit` action events authored in the DSL | Host behavior — start a checkout, open a sheet, mark a step done | [events.md](events.md) |
| **Analytics bus** | Auto `app8.*` lifecycle events + author-declared `analytics` bindings | Product analytics — proxy to Mixpanel / Amplitude / Segment | [analytics.md](analytics.md) |

To run host-side logic in response to a tap, the DSL author emits an event:

```json
"actions": { "tap": { "type": "emit", "name": "checkout.tapped", "payload": { "sku": "{{item.sku}}" } } }
```

…and the host routes it by `event.name`. This `.emit` → event-bus path is the supported way for DSL to trigger native code. (`executeFunction` is a reserved action consumed by higher-level delivery SDKs, not the core engine.)

---

## Localization

The host owns the active locale. `getTranslations()` supplies the bundle once at boot; `instance.setLocale(_:)` switches language at runtime; `instance.currentLocale` reports the resolved locale. See [localization.md](localization.md) for the bundle shape and fallback chain.

---

## See Also

- [README Quick Start](../../README.md#quick-start) — bootstrapping an instance
- [events.md](events.md) — the `.emit` event bus and subscribe API
- [analytics.md](analytics.md) — analytics events and handler wiring
- [localization.md](localization.md) — translation bundle and locale resolution
- [variables.md](variables.md) — `source` bindings and datasource-backed variables
