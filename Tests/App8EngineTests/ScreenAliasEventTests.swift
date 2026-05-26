//
//  ScreenAliasEventTests.swift
//  App8Engine
//
//  Verify that `App8Event.screenId` and `App8AnalyticsEvent.screenId` are
//  stamped with the **caller-supplied alias** (the value the host passed to
//  `App8.Instance.renderScreen(screenId:)` / `App8Cloud.Instance.screen(id:)`),
//  NOT the DSL document's internal `"id"`.
//
//  Regression test for the bug where `subscribe(onScreen: alias)` never
//  matched cloud-rendered screens because the engine used the DSL document's
//  internal id as the path root, while the host only knew the cloud-request
//  alias.
//

import UIKit
import Testing
@testable import App8Engine

@MainActor
private func makeService() -> (App8Service, App8Context) {
    let context = App8Context()
    let service = App8Service(publicDataSource: AliasStubDataSource(), context: context)
    return (service, context)
}

/// Screen JSON whose internal `"id"` ("intro-screen-r1") is intentionally
/// different from the cloud-request alias the host uses to fetch it. Mirrors
/// the production case in the bug report.
private let aliasDivergentScreenJSON = """
{
    "type": "screen",
    "id": "intro-screen-r1",
    "content": {
        "properties": {},
        "children": [
            {
                "id": "connectButton",
                "type": "view",
                "content": {
                    "properties": {},
                    "actions": {
                        "tap": {
                            "type": "emit",
                            "name": "connect.tapped",
                            "payload": { "source": "dsl" }
                        }
                    },
                    "analytics": {
                        "tap": "stripeConnectClicked"
                    }
                }
            }
        ]
    }
}
"""

private let hostAlias = "onboarding-intro-v2"
private let dslInternalId = "intro-screen-r1"

@MainActor
@Test
func renderScreenStampsRequestedAliasOnEmitEvents() async throws {
    let (service, context) = makeService()
    let component = try JSONDecoder().decode(
        DSL.Model.Component.`Any`.self,
        from: aliasDivergentScreenJSON.data(using: .utf8)!
    )

    var captured: App8Event?
    let sub = context.eventBus.subscribe { captured = $0 }
    defer { sub.cancel() }

    _ = await service.renderScreen(component, screenId: hostAlias)

    // The screen-level viewModel should be registered at the alias, NOT at
    // the DSL internal id.
    #expect(service.componentRegistry.viewModel(forId: hostAlias) != nil)
    #expect(service.componentRegistry.viewModel(forId: dslInternalId) == nil)

    // Reach the connectButton's viewModel via its full alias-rooted path
    // and dispatch the `.tap` trigger directly. This is the same code path
    // the gesture recognizer hits at runtime.
    let buttonPath = "\(hostAlias).connectButton"
    let buttonVM = service.componentRegistry.viewModel(forId: buttonPath) as? CViewModel
    try #require(buttonVM != nil, "Expected connectButton VM registered at '\(buttonPath)'")
    buttonVM!.executeAction(for: .tap)

    let event = try #require(captured, "subscriber received no event")
    #expect(event.name == "connect.tapped")
    #expect(event.screenId == hostAlias, "event.screenId should be the requested alias, was '\(event.screenId)'")
    #expect(event.screenId != dslInternalId, "event.screenId leaked DSL document's internal id")
    #expect(event.componentId == "connectButton")
    #expect(event.payload["source"] as? String == "dsl")
}

@MainActor
@Test
func subscribeOnScreenMatchesRequestedAlias() async throws {
    let (service, context) = makeService()
    let component = try JSONDecoder().decode(
        DSL.Model.Component.`Any`.self,
        from: aliasDivergentScreenJSON.data(using: .utf8)!
    )

    // The host-facing API: filter by the alias they requested. This is the
    // exact pattern the bug report calls broken.
    var receivedNames: [String] = []
    let sub = context.eventBus.subscribe(onScreen: hostAlias) { event in
        receivedNames.append(event.name)
    }
    defer { sub.cancel() }

    _ = await service.renderScreen(component, screenId: hostAlias)

    let buttonPath = "\(hostAlias).connectButton"
    let buttonVM = service.componentRegistry.viewModel(forId: buttonPath) as? CViewModel
    try #require(buttonVM != nil)
    buttonVM!.executeAction(for: .tap)

    #expect(receivedNames == ["connect.tapped"], "subscribe(onScreen:) should match the requested alias")
}

@MainActor
@Test
func subscribeOnScreenDoesNotMatchDslInternalId() async throws {
    let (service, context) = makeService()
    let component = try JSONDecoder().decode(
        DSL.Model.Component.`Any`.self,
        from: aliasDivergentScreenJSON.data(using: .utf8)!
    )

    // A host that mistakenly filters by the DSL internal id sees NOTHING —
    // proves the alias is the source of truth on the bus.
    var receivedNames: [String] = []
    let sub = context.eventBus.subscribe(onScreen: dslInternalId) { event in
        receivedNames.append(event.name)
    }
    defer { sub.cancel() }

    _ = await service.renderScreen(component, screenId: hostAlias)

    let buttonPath = "\(hostAlias).connectButton"
    let buttonVM = service.componentRegistry.viewModel(forId: buttonPath) as? CViewModel
    try #require(buttonVM != nil)
    buttonVM!.executeAction(for: .tap)

    #expect(receivedNames.isEmpty, "filter on DSL internal id must not match events from an aliased render")
}

@MainActor
@Test
func analyticsEventsCarryRequestedAlias() async throws {
    let (service, context) = makeService()
    let component = try JSONDecoder().decode(
        DSL.Model.Component.`Any`.self,
        from: aliasDivergentScreenJSON.data(using: .utf8)!
    )

    var analyticsEvents: [App8AnalyticsEvent] = []
    let sub = context.analyticsBus.subscribe { analyticsEvents.append($0) }
    defer { sub.cancel() }

    _ = await service.renderScreen(component, screenId: hostAlias)

    let buttonPath = "\(hostAlias).connectButton"
    let buttonVM = service.componentRegistry.viewModel(forId: buttonPath) as? CViewModel
    try #require(buttonVM != nil)
    buttonVM!.executeAction(for: .tap)

    // We expect the auto `app8.component.tapped` plus the author-declared
    // `stripeConnectClicked` (auto-prefixed to `app8.stripeConnectClicked`).
    // Both must carry the alias.
    let names = analyticsEvents.map(\.name)
    #expect(names.contains(App8AnalyticsEvent.Auto.componentTapped))
    #expect(names.contains("app8.stripeConnectClicked"))

    for event in analyticsEvents {
        #expect(event.screenId == hostAlias, "\(event.name).screenId was '\(event.screenId ?? "nil")', expected '\(hostAlias)'")
        #expect(event.screenId != dslInternalId, "\(event.name).screenId leaked DSL document's internal id")
    }
}

@MainActor
@Test
func fallsBackToDslInternalIdWhenNoAliasProvided() async throws {
    // The no-screenId render path (preview tooling, screenshot capture) keeps
    // the legacy behavior: stamp the DSL document's internal id, because no
    // alias was supplied.
    let (service, context) = makeService()
    let component = try JSONDecoder().decode(
        DSL.Model.Component.`Any`.self,
        from: aliasDivergentScreenJSON.data(using: .utf8)!
    )

    var captured: App8Event?
    let sub = context.eventBus.subscribe { captured = $0 }
    defer { sub.cancel() }

    _ = service.renderScreen(component)   // overload without screenId

    let buttonPath = "\(dslInternalId).connectButton"
    let buttonVM = service.componentRegistry.viewModel(forId: buttonPath) as? CViewModel
    try #require(buttonVM != nil, "Expected fallback to DSL internal id when no alias passed")
    buttonVM!.executeAction(for: .tap)

    let event = try #require(captured)
    #expect(event.screenId == dslInternalId)
}

// MARK: - Stub

private final class AliasStubDataSource: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data { Data() }
}
