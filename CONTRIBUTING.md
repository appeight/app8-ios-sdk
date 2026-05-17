# Contributing to App8Engine

Thanks for your interest in improving App8Engine. This guide covers how to build,
test, and submit changes.

## Prerequisites

- macOS with Xcode 16 or newer
- Swift 6.1+
- An iOS 18 Simulator (the project standardizes on **iPhone 17**)

App8Engine has **zero external dependencies**, so there is nothing to install
beyond Xcode.

## Building and testing

App8Engine depends on UIKit, which means it must be built for the iOS Simulator.
`swift build` targets macOS by default and fails with `no such module 'UIKit'` —
use `xcodebuild` instead:

```bash
# Build
xcodebuild build -scheme App8Engine -destination 'platform=iOS Simulator,name=iPhone 17'

# Run the test suite
xcodebuild test -scheme App8Engine -destination 'platform=iOS Simulator,name=iPhone 17'
```

All tests must pass before a change can be merged.

## Project layout

- `Sources/App8Engine/` — engine source
- `Tests/App8EngineTests/` — XCTest suite; JSON fixtures live in `Tests/App8EngineTests/Fixtures/`
- `docs/dsl/` — the App8 DSL reference

## Conventions

- Use `@MainActor` for all UI-related types (views, view models, services).
- DSL model types should be `Sendable`.
- New behavior should come with tests. Add JSON fixtures under `Fixtures/` when a
  test needs sample DSL.
- Keep the engine dependency-free — only Apple frameworks.

## Submitting changes

1. Fork the repository and create a branch for your change.
2. Make your change with accompanying tests.
3. Confirm the full test suite passes on the iPhone 17 simulator.
4. Open a pull request describing the change and the motivation.

By submitting a contribution you agree it is licensed under the Apache License 2.0,
the same license as the project (see [LICENSE](LICENSE)).
