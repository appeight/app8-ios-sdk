# App8Engine

App8Engine is a dynamic UI rendering engine for iOS. It turns a JSON-based
declarative UI language — the **App8 DSL** — into native UIKit view controllers at
runtime, with reactive variables, expression evaluation, component state, and
flow-based navigation.

- **Zero dependencies** — only Apple frameworks (UIKit, Foundation, Combine, MapKit).
- **Native rendering** — no web views; the DSL becomes real `UIView`/`UIViewController`.
- **Reactive** — `{{expression}}` bindings, variables, and component states.
- **Host-driven content** — you supply DSL JSON through a single protocol, from a
  bundle, the network, or anywhere else.

## Requirements

- iOS 18+
- Swift 6.1+ / Xcode 16+

## Installation

Add App8Engine as a Swift Package Manager dependency:

```swift
dependencies: [
    .package(url: "https://github.com/appeight/App8Engine.git", from: "0.1.0")
]
```

Then add `App8Engine` to your target's dependencies.

> App8Engine is at an early release (`0.x`); the public API may change between
> minor versions.

## Quick Start

App8Engine never fetches content itself. You implement `App8DataSource` to feed it
DSL JSON, then ask an `App8.Instance` for a view controller.

### 1. Provide content with `App8DataSource`

```swift
import App8Engine

/// Serves DSL JSON bundled in the app. Swap the file reads for network calls
/// to update the UI dynamically.
final class BundleDataSource: App8DataSource {
    private let root: URL

    init(directory: URL) { self.root = directory }

    private func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relativePath))
    }

    func getApp() async throws -> Data { try data("app.json") }
    func getScreen(screenId: String) async throws -> Data { try data("screens/\(screenId).json") }
    func getComponent(componentId: String) async throws -> Data { try data("components/\(componentId).json") }
    func getStyles() async throws -> [Data] { [try data("styles.json")] }
    func getComponents() async throws -> [Data] { [] }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }

    // getDatasource, getAllScreenIds, and the stream* methods have default
    // implementations — override them only when you need those features.
}
```

### 2. Render

```swift
import App8Engine

let dataSource = BundleDataSource(directory: bundledAppURL)
let instance = App8.instance(dataSource: dataSource)

// Returns the app's root view controller, ready to present.
let rootViewController = try await instance.startApp()
present(rootViewController, animated: true)
```

To render a single screen outside the app flow, or to inspect/validate DSL, use
`App8.debugInstance(dataSource:)`.

### 3. Receive events and analytics

DSL screens fire two kinds of typed events into the host. Subscribe at app launch
and route by `event.name`.

```swift
// Host action events from `.emit` actions in the DSL — wire them to real
// host behaviour (start a checkout, open Stripe, mark a step complete).
let eventsSub = instance.subscribe { event in
    switch event.name {
    case "connect.tapped":   startStripeFlow()
    case "user.selected":    showProfile(named: event.payload["name"] as? String ?? "")
    default: break
    }
}

// Analytics events — both author-declared and auto-fired `app8_*` lifecycle
// events. Typical wiring: one handler that proxies to Mixpanel / Amplitude / Segment.
instance.setAnalyticsHandler(MyAnalyticsAdapter())
```

Every event carries `screenId`, `componentId`, `componentType`, and `locale`
(the active translation locale) so dashboards can slice by language and screen
without extra payload plumbing. See [`docs/dsl/events.md`](docs/dsl/events.md)
and [`docs/dsl/analytics.md`](docs/dsl/analytics.md) for the full surface.

## The App8 DSL

The DSL describes an app as JSON — an app manifest, navigation flows, and screens
built from components (`label`, `button`, `image`, `collection`, `stackView`, …).
A minimal screen:

```json
{
  "type": "screen",
  "content": {
    "navigationBar": { "title": "Home" },
    "variables": { "count": { "type": "number", "initialValue": 0 } },
    "children": [
      {
        "type": "label",
        "content": { "properties": { "text": "Count: {{count}}" } }
      },
      {
        "type": "button",
        "content": {
          "properties": { "text": "Increment" },
          "actions": { "tap": { "type": "incrementVariable", "variableName": "count", "by": 1 } }
        }
      }
    ]
  }
}
```

The full DSL reference — components, styles, layout, variables, actions,
navigation, collections, animations — lives in [`docs/dsl/`](docs/dsl/index.md).

## Building and testing

App8Engine depends on UIKit, so build and test it against the iOS Simulator
(`swift build` targets macOS and will fail to find UIKit):

```bash
xcodebuild test -scheme App8Engine -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Copyright 2026 App8 Ltd.
