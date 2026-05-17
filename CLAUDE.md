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

## Concurrency

- Use `@MainActor` for all UI-related types
- VariableStore, ViewModels, and Services are MainActor-isolated
- DSL model types should be `Sendable`
