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
- Two independent buses on `App8Context`: `eventBus` (`.emit` action events, host-facing) and `analyticsBus` (auto `app8_*` + author-declared `analytics` bindings). Public types live in `Sources/App8Engine/Events/`.
- **Every component trigger dispatch site MUST route through `CBaseViewModel.dispatchTrigger(_:execute:)`.** Calling `executeVariableAction(action)` or `executeAction(action)` directly bypasses analytics — author-declared `analytics: { trigger: ... }` silently no-ops and auto `app8_component_tapped` doesn't fire. The helper accepts a pluggable executor closure so dispatch sites that need scoped variable stores (Collection cell taps, Map annotation taps, ScrollView threshold, TextField text-change, etc.) work the same way.
- TableView rows aren't full Component view models — they use the host VM's `fireRowTapAnalytics(rowId:binding:)` to tag analytics with the row's own id, then call `executeAction(_:)` for each action. Pattern: see `CTableViewView.didSelectRowAt`.
- All engine-dispatched events should populate `locale: service.context.translationStore.activeLocale` so dashboards can slice by translation locale.

## Concurrency

- Use `@MainActor` for all UI-related types
- VariableStore, ViewModels, and Services are MainActor-isolated
- DSL model types should be `Sendable`
