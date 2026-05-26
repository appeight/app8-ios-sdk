# Claude Code Guidelines for App8Engine

## Build Commands

**Always use xcodebuild for iOS Simulator**, not `swift build`:

```bash
# Build the package
xcodebuild build -scheme App8Engine -destination 'platform=iOS Simulator,name=iPhone 17'

# Run tests
xcodebuild test -scheme App8Engine -destination 'platform=iOS Simulator,name=iPhone 17'
```

`swift build` will fail with "no such module 'UIKit'" because it builds for macOS by default and App8Engine depends on UIKit.

## Architecture

App8Engine is a DSL rendering engine that:
- Parses JSON component definitions
- Creates UIKit views dynamically
- Manages component state and transitions
- Handles variable expressions (`{{...}}` syntax)

## Key Patterns

### Variable System
- **VariableStore**: Base storage with dependency graph
- **ScopedVariableStore**: Child store with parent scope lookup
- **Three scopes**: App-level, Screen-level, Component-level
- Variables defined in DSL JSON are automatically initialized

### Expression System
- **ExpressionParser**: Tokenizes and parses `{{expression}}` syntax
- **ExpressionEvaluator**: Evaluates AST against variable context
- **PropertyResolver**: Resolves expressions in component properties

### Component Rendering
- Components are rendered via `App8Service.renderComponent()`
- Each component gets a ViewModel that manages state
- StateManager handles component state transitions

### Events & Analytics
- Two independent buses on `App8Context`: `eventBus` (`.emit` action events, host-facing) and `analyticsBus` (auto `app8.*` + author-declared `analytics` bindings). Public types live in `Sources/App8Engine/Events/`.
- **Every component trigger dispatch site MUST route through `CBaseViewModel.dispatchTrigger(_:execute:)`.** Calling `executeVariableAction(action)` or `executeAction(action)` directly bypasses analytics — author-declared `analytics: { trigger: ... }` silently no-ops and auto `app8.component.tapped` doesn't fire. The helper accepts a pluggable executor closure so dispatch sites that need scoped variable stores (Collection cell taps, Map annotation taps, ScrollView threshold, TextField text-change, etc.) work the same way.
- TableView rows aren't full Component view models — they use the host VM's `fireRowTapAnalytics(rowId:binding:)` to tag analytics with the row's own id, then call `executeAction(_:)` for each action. Pattern: see `CTableViewView.didSelectRowAt`.
- All engine-dispatched events should populate `locale: service.context.translationStore.activeLocale` so dashboards can slice by translation locale.
- **Bus stamping**: `App8AnalyticsBus.dispatch` and `App8EventBus.dispatch` stamp `engineVersion` (always, from `EngineVersion.current`) and `cloudVersion` (when the cloud SDK has taught the bus) onto every outgoing event. Emit sites construct events with an empty `engineVersion` and let the bus overwrite — never hardcode the version at the emit site.
- **Canonical-property merge** (analytics bus only): the bus merges `screen_id`, `component_id`, `component_type`, `locale`, `engine_version`, `cloud_version` into `event.properties` using snake_case unprefixed keys. `App8AnalyticsEvent.canonicalKeys` is the single source of truth. Action bus does NOT merge — `payload` stays exactly as the DSL author wrote it.
- **Author-name normalization**: author-declared `analytics` binding names are auto-prefixed with `app8.` at the emit site (`fireTriggerAnalytics` / `fireRowTapAnalytics`). Names that already start with `app8.` are stripped and re-prepended (warn once). Names colliding with reserved `App8AnalyticsEvent.Auto.*` constants warn once and dispatch anyway. Use `App8Context.warnedNames` for once-per-instance dedup.
- **`redact` hook on the analytics bus** runs AFTER version stamping AND AFTER property merge — closure receives the fully-baked event. Return `nil` to drop. Action bus has no `redact` — host imperatives aren't third-party-bound data.

## Concurrency

- Use `@MainActor` for all UI-related types
- VariableStore, ViewModels, and Services are MainActor-isolated
- DSL model types should be `Sendable`
