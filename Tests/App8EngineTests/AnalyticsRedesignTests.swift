//
//  AnalyticsRedesignTests.swift
//  App8Engine
//
//  Coverage for the analytics taxonomy redesign. Five concern areas:
//
//   1. Bus stamping — engineVersion always, cloudVersion when taught.
//   2. Canonical-property merge — author keys + SDK keys, nil omission,
//      action bus does NOT merge.
//   3. Redact hook — nil drops, mutated copy substitutes, ordering (after
//      stamp AND after merge).
//   4. Author-name normalization — auto-prefix, app8.* strip + warn,
//      reserved-name collision warn, dedup across many dispatches.
//   5. Author-property-key collision — SDK wins, warn once, dedup.
//
//  These guard the redesign's invariants — anything regressing here is a
//  cross-customer breakage at the integration boundary.
//

import UIKit
import Testing
@testable import App8Engine

// MARK: - Test helpers

@MainActor
private func makeService() -> (App8Service, App8Context) {
    let context = App8Context()
    let service = App8Service(publicDataSource: RedesignStubDataSource(), context: context)
    return (service, context)
}

private func makeAnalytic(
    name: String = "test_event",
    screenId: String? = "screen-a",
    componentId: String? = "btn",
    componentType: String? = "view",
    locale: String? = "en",
    properties: [String: Any] = [:]
) -> App8AnalyticsEvent {
    App8AnalyticsEvent(
        name: name,
        screenId: screenId,
        componentId: componentId,
        componentType: componentType,
        locale: locale,
        properties: properties
    )
}

// MARK: - 1. Bus stamping

@MainActor
@Test
func busStampsEngineVersionAutomatically() throws {
    let bus = App8AnalyticsBus()
    var captured: App8AnalyticsEvent?
    let sub = bus.subscribe { captured = $0 }
    defer { sub.cancel() }

    bus.dispatch(makeAnalytic(name: "stamp.test"))
    let event = try #require(captured)
    // Asserted against the constant, not a literal — release tooling bumps
    // the constant; the bus contract is "stamps whatever EngineVersion says."
    #expect(event.engineVersion == EngineVersion.current)
    #expect(!event.engineVersion.isEmpty)
    #expect((event.properties["engine_version"] as? String) == EngineVersion.current)
}

@MainActor
@Test
func busStampsCloudVersionWhenSet() throws {
    let bus = App8AnalyticsBus()
    bus.cloudVersion = "9.9.9"
    var captured: App8AnalyticsEvent?
    let sub = bus.subscribe { captured = $0 }
    defer { sub.cancel() }

    bus.dispatch(makeAnalytic(name: "stamp.cloud"))
    let event = try #require(captured)
    #expect(event.cloudVersion == "9.9.9")
    #expect((event.properties["cloud_version"] as? String) == "9.9.9")
}

@MainActor
@Test
func busLeavesCloudVersionNilWhenUnset() throws {
    let bus = App8AnalyticsBus()
    var captured: App8AnalyticsEvent?
    let sub = bus.subscribe { captured = $0 }
    defer { sub.cancel() }

    bus.dispatch(makeAnalytic(name: "stamp.nocloud"))
    let event = try #require(captured)
    #expect(event.cloudVersion == nil)
    #expect(event.properties["cloud_version"] == nil)
}

@MainActor
@Test
func actionBusStampsBothVersionsOnTypedFields() throws {
    let bus = App8EventBus()
    bus.cloudVersion = "test-cloud-1.0"
    var captured: App8Event?
    let sub = bus.subscribe { captured = $0 }
    defer { sub.cancel() }

    bus.dispatch(App8Event(
        name: "connect.tapped",
        screenId: "intro",
        componentId: "btn",
        componentType: "view",
        locale: "en",
        payload: ["userId": "abc"]
    ))
    let event = try #require(captured)
    #expect(event.engineVersion == EngineVersion.current)
    #expect(event.cloudVersion == "test-cloud-1.0")
}

// MARK: - 2. Canonical-property merge (analytics) & non-merge (action)

@MainActor
@Test
func canonicalMergeInjectsAllPopulatedFields() throws {
    let bus = App8AnalyticsBus()
    bus.cloudVersion = "test-cloud-1.0"
    var captured: App8AnalyticsEvent?
    let sub = bus.subscribe { captured = $0 }
    defer { sub.cancel() }

    bus.dispatch(makeAnalytic(
        name: "merge.full",
        screenId: "intro",
        componentId: "btn",
        componentType: "button",
        locale: "de-DE",
        properties: ["author_key": "author_value"]
    ))

    let props = try #require(captured?.properties)
    #expect(props["author_key"] as? String == "author_value")
    #expect(props["screen_id"] as? String == "intro")
    #expect(props["component_id"] as? String == "btn")
    #expect(props["component_type"] as? String == "button")
    #expect(props["locale"] as? String == "de-DE")
    #expect(props["engine_version"] as? String == EngineVersion.current)
    #expect(props["cloud_version"] as? String == "test-cloud-1.0")
}

@MainActor
@Test
func canonicalMergeOmitsNilFields() throws {
    let bus = App8AnalyticsBus()
    var captured: App8AnalyticsEvent?
    let sub = bus.subscribe { captured = $0 }
    defer { sub.cancel() }

    bus.dispatch(makeAnalytic(
        name: "merge.nil",
        screenId: "intro",
        componentId: nil,
        componentType: nil,
        locale: nil
    ))

    let props = try #require(captured?.properties)
    #expect(props["screen_id"] as? String == "intro")
    // Nil typed fields → key absent, not nil-valued.
    #expect(props["component_id"] == nil)
    #expect(props["component_type"] == nil)
    #expect(props["locale"] == nil)
    #expect(props["cloud_version"] == nil)
    // engine_version always present.
    #expect(props["engine_version"] as? String == EngineVersion.current)
}

@MainActor
@Test
func canonicalKeysConstantMatchesBusInjection() throws {
    let bus = App8AnalyticsBus()
    bus.cloudVersion = "test-cloud-1.0"
    var captured: App8AnalyticsEvent?
    let sub = bus.subscribe { captured = $0 }
    defer { sub.cancel() }

    bus.dispatch(makeAnalytic(
        name: "canonical.match",
        screenId: "s", componentId: "c", componentType: "t", locale: "en"
    ))

    let props = try #require(captured?.properties)
    for key in App8AnalyticsEvent.canonicalKeys {
        #expect(props[key] != nil, "canonicalKeys lists '\(key)' but bus didn't inject it")
    }
}

@MainActor
@Test
func actionBusDoesNotMergeCanonicalKeysIntoPayload() throws {
    let bus = App8EventBus()
    bus.cloudVersion = "test-cloud-1.0"
    var captured: App8Event?
    let sub = bus.subscribe { captured = $0 }
    defer { sub.cancel() }

    bus.dispatch(App8Event(
        name: "connect.tapped",
        screenId: "intro",
        componentId: "btn",
        componentType: "view",
        locale: "en",
        payload: ["userId": "abc"]
    ))

    let payload = try #require(captured?.payload)
    // Author payload preserved exactly — no SDK keys injected.
    #expect(payload["userId"] as? String == "abc")
    #expect(payload.count == 1)
    #expect(payload["screen_id"] == nil)
    #expect(payload["engine_version"] == nil)
    #expect(payload["component_id"] == nil)
}

// MARK: - 3. Redact hook

@MainActor
@Test
func redactReturningNilDropsEvent() {
    let bus = App8AnalyticsBus()
    bus.redact = { _ in nil }
    var captured: App8AnalyticsEvent?
    let sub = bus.subscribe { captured = $0 }
    defer { sub.cancel() }

    bus.dispatch(makeAnalytic(name: "drop.me"))
    #expect(captured == nil)
}

@MainActor
@Test
func redactReturningMutatedCopySubstitutes() {
    let bus = App8AnalyticsBus()
    bus.redact = { event in
        var props = event.properties
        props["url"] = "https://example.com/path"  // strip query string
        return event._withProperties(props)
    }
    var captured: App8AnalyticsEvent?
    let sub = bus.subscribe { captured = $0 }
    defer { sub.cancel() }

    bus.dispatch(makeAnalytic(
        name: App8AnalyticsEvent.Auto.urlOpened,
        properties: ["url": "https://example.com/path?token=secret"]
    ))
    #expect((captured?.properties["url"] as? String) == "https://example.com/path")
}

@MainActor
@Test
func redactRunsAfterStampingAndMerge() {
    let bus = App8AnalyticsBus()
    bus.cloudVersion = "test-cloud-1.0"
    var sawCanonicalKeys = false
    var sawEngineVersionField = false
    bus.redact = { event in
        sawEngineVersionField = event.engineVersion == EngineVersion.current
            && !event.engineVersion.isEmpty
        // Properties should already contain merged canonical keys here.
        sawCanonicalKeys = event.properties["engine_version"] as? String == EngineVersion.current
            && event.properties["screen_id"] as? String == "intro"
            && event.properties["cloud_version"] as? String == "test-cloud-1.0"
        return event
    }
    let sub = bus.subscribe { _ in }
    defer { sub.cancel() }

    bus.dispatch(makeAnalytic(name: "order", screenId: "intro"))
    #expect(sawEngineVersionField, "redact must see stamped engineVersion field")
    #expect(sawCanonicalKeys, "redact must see merged canonical keys in properties")
}

@MainActor
@Test
func actionBusHasNoRedactHook() {
    // The action bus intentionally has no redact API — host imperatives are
    // not third-party-bound data. This test pins that surface via reflection:
    // the action bus mirror must not expose a `redact` property. If a future
    // PR adds it, this test fails and forces a design conversation.
    let actionBus = App8EventBus()
    let mirror = Mirror(reflecting: actionBus)
    let names = mirror.children.compactMap(\.label)
    #expect(!names.contains("redact"))
}

// MARK: - 4. Author-name normalization

@MainActor
@Test
func authorNameAutoPrefixed() async throws {
    let (service, context) = makeService()
    let component = try JSONDecoder().decode(
        DSL.Model.Component.`Any`.self,
        from: redesignScreen(authorBindingName: "stripeConnectClicked").data(using: .utf8)!
    )
    var seen: [String] = []
    let sub = context.analyticsBus.subscribe { seen.append($0.name) }
    defer { sub.cancel() }

    _ = await service.renderScreen(component, screenId: "home")
    let btn = service.componentRegistry.viewModel(forId: "home.btn") as? CViewModel
    try #require(btn != nil)
    btn!.executeAction(for: .tap)

    #expect(seen.contains("app8.stripeConnectClicked"))
}

@MainActor
@Test
func authorNameWithApp8PrefixStripsAndRePrepends() async throws {
    let (service, context) = makeService()
    let component = try JSONDecoder().decode(
        DSL.Model.Component.`Any`.self,
        from: redesignScreen(authorBindingName: "app8.foo").data(using: .utf8)!
    )
    var seen: [String] = []
    let sub = context.analyticsBus.subscribe { seen.append($0.name) }
    defer { sub.cancel() }

    _ = await service.renderScreen(component, screenId: "home")
    let btn = service.componentRegistry.viewModel(forId: "home.btn") as? CViewModel
    try #require(btn != nil)
    btn!.executeAction(for: .tap)

    // Lands as "app8.foo" (idempotent).
    #expect(seen.contains("app8.foo"))
}

@MainActor
@Test
func authorNameCollidingWithReservedDispatchesAnyway() async throws {
    let (service, context) = makeService()
    // Authoring "screen.appeared" — after prefix becomes the reserved
    // `app8.screen.appeared`.
    let component = try JSONDecoder().decode(
        DSL.Model.Component.`Any`.self,
        from: redesignScreen(authorBindingName: "screen.appeared").data(using: .utf8)!
    )
    var seen: [String] = []
    let sub = context.analyticsBus.subscribe { seen.append($0.name) }
    defer { sub.cancel() }

    _ = await service.renderScreen(component, screenId: "home")
    let btn = service.componentRegistry.viewModel(forId: "home.btn") as? CViewModel
    try #require(btn != nil)
    btn!.executeAction(for: .tap)

    #expect(seen.contains(App8AnalyticsEvent.Auto.screenAppeared))
}

@MainActor
@Test
func warnDedupCollidesOnlyOnce() async throws {
    let (service, context) = makeService()
    let component = try JSONDecoder().decode(
        DSL.Model.Component.`Any`.self,
        from: redesignScreen(authorBindingName: "screen.appeared").data(using: .utf8)!
    )
    _ = await service.renderScreen(component, screenId: "home")
    let btn = service.componentRegistry.viewModel(forId: "home.btn") as? CViewModel
    try #require(btn != nil)

    // 100 dispatches → exactly one collision entry in warnedNames.
    for _ in 0..<100 { btn!.executeAction(for: .tap) }
    let collisionEntries = context.warnedNames.filter { $0.hasPrefix("author-name:reserved:") }
    #expect(collisionEntries.count == 1)
}

// MARK: - 5. Author-property-key collision

@MainActor
@Test
func authorPropertyCollidingWithCanonicalKeyIsOverwritten() async throws {
    let (service, context) = makeService()
    // Author writes properties.screen_id = "fake".
    let component = try JSONDecoder().decode(
        DSL.Model.Component.`Any`.self,
        from: redesignScreenFullForm(authorBindingName: "leakyEvent", propertyKey: "screen_id", propertyValue: "fake").data(using: .utf8)!
    )
    var captured: App8AnalyticsEvent?
    let sub = context.analyticsBus.subscribe { event in
        if event.name == "app8.leakyEvent" { captured = event }
    }
    defer { sub.cancel() }

    _ = await service.renderScreen(component, screenId: "home")
    let btn = service.componentRegistry.viewModel(forId: "home.btn") as? CViewModel
    try #require(btn != nil)
    btn!.executeAction(for: .tap)

    let event = try #require(captured)
    // SDK wins.
    #expect(event.properties["screen_id"] as? String == "home")
    #expect(event.properties["screen_id"] as? String != "fake")

    // Warning entry recorded.
    let propWarnings = context.warnedNames.filter { $0.hasPrefix("author-prop:") }
    #expect(propWarnings.count == 1)
}

@MainActor
@Test
func authorPropertyCollisionDedupAcrossManyDispatches() async throws {
    let (service, context) = makeService()
    let component = try JSONDecoder().decode(
        DSL.Model.Component.`Any`.self,
        from: redesignScreenFullForm(authorBindingName: "leakyEvent", propertyKey: "screen_id", propertyValue: "fake").data(using: .utf8)!
    )
    _ = await service.renderScreen(component, screenId: "home")
    let btn = service.componentRegistry.viewModel(forId: "home.btn") as? CViewModel
    try #require(btn != nil)

    for _ in 0..<100 { btn!.executeAction(for: .tap) }
    let propWarnings = context.warnedNames.filter { $0.hasPrefix("author-prop:") }
    #expect(propWarnings.count == 1)
}

// MARK: - 6. Auto event config gating

@MainActor
@Test
func autoCloudEventsToggleDoesNotSuppressEngineAutoEvents() async throws {
    let (service, context) = makeService()
    // Suppress cloud telemetry, leave engine lifecycle on.
    context.analyticsConfig.autoCloudEvents = false

    let component = try JSONDecoder().decode(
        DSL.Model.Component.`Any`.self,
        from: redesignScreen(authorBindingName: "stripeConnectClicked").data(using: .utf8)!
    )
    var seen: [String] = []
    let sub = context.analyticsBus.subscribe { seen.append($0.name) }
    defer { sub.cancel() }

    _ = await service.renderScreen(component, screenId: "home")
    let btn = service.componentRegistry.viewModel(forId: "home.btn") as? CViewModel
    try #require(btn != nil)
    btn!.executeAction(for: .tap)

    // Engine auto event still fires; cloud config gate doesn't affect it.
    #expect(seen.contains(App8AnalyticsEvent.Auto.componentTapped))
}

// MARK: - Stubs / fixtures

private func redesignScreen(authorBindingName: String) -> String {
    """
    {
        "type": "screen",
        "id": "home",
        "content": {
            "properties": {},
            "children": [
                {
                    "id": "btn",
                    "type": "view",
                    "content": {
                        "properties": {},
                        "actions": {
                            "tap": { "type": "emit", "name": "btn.tapped" }
                        },
                        "analytics": {
                            "tap": "\(authorBindingName)"
                        }
                    }
                }
            ]
        }
    }
    """
}

private func redesignScreenFullForm(authorBindingName: String, propertyKey: String, propertyValue: String) -> String {
    """
    {
        "type": "screen",
        "id": "home",
        "content": {
            "properties": {},
            "children": [
                {
                    "id": "btn",
                    "type": "view",
                    "content": {
                        "properties": {},
                        "actions": {
                            "tap": { "type": "emit", "name": "btn.tapped" }
                        },
                        "analytics": {
                            "tap": {
                                "name": "\(authorBindingName)",
                                "properties": { "\(propertyKey)": "\(propertyValue)" }
                            }
                        }
                    }
                }
            ]
        }
    }
    """
}

private final class RedesignStubDataSource: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data { Data() }
}
