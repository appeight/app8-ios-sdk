//
//  App8AnalyticsBusTests.swift
//  App8Engine
//
//  Mirrors `App8EventBusTests` for the analytics channel. The two buses
//  intentionally share shape so anything that breaks here is likely also
//  broken on the action-event side.
//

import Foundation
import Combine
import Testing
@testable import App8Engine

private func makeAnalytic(name: String = "test_event", screenId: String? = "screen-a", locale: String? = nil) -> App8AnalyticsEvent {
    App8AnalyticsEvent(name: name, screenId: screenId, locale: locale, properties: ["k": "v"])
}

@MainActor
@Test
func analyticsLocaleRidesOnEvents() async {
    let bus = App8AnalyticsBus()
    var captured: App8AnalyticsEvent?
    let sub = bus.subscribe { captured = $0 }
    bus.dispatch(makeAnalytic(locale: "ja-JP"))
    #expect(captured?.locale == "ja-JP")
    sub.cancel()
}

@MainActor
@Test
func analyticsClosureSubscribersReceiveDispatchedEvents() async {
    let bus = App8AnalyticsBus()
    var received: [String] = []
    let sub = bus.subscribe { received.append($0.name) }

    bus.dispatch(makeAnalytic(name: "one"))
    bus.dispatch(makeAnalytic(name: "two"))

    #expect(received == ["one", "two"])
    sub.cancel()
}

@MainActor
@Test
func analyticsCancellingStopsDelivery() async {
    let bus = App8AnalyticsBus()
    var received: [String] = []
    let sub = bus.subscribe { received.append($0.name) }
    bus.dispatch(makeAnalytic(name: "before"))
    sub.cancel()
    bus.dispatch(makeAnalytic(name: "after"))
    #expect(received == ["before"])
}

@MainActor
private final class TestAnalyticsHandler: App8AnalyticsHandler {
    var events: [App8AnalyticsEvent] = []
    func app8DidTrack(_ event: App8AnalyticsEvent) { events.append(event) }
}

@MainActor
@Test
func analyticsDelegateHandlerReceivesEvents() async {
    let bus = App8AnalyticsBus()
    let handler = TestAnalyticsHandler()
    bus.delegate = handler

    bus.dispatch(makeAnalytic(name: "tracked"))
    #expect(handler.events.count == 1)
    #expect(handler.events.first?.name == "tracked")
}

@MainActor
@Test
func analyticsConfigDefaultsAreAllEnabled() {
    let config = App8AnalyticsConfig()
    #expect(config.autoScreenEvents == true)
    #expect(config.autoComponentTaps == true)
    #expect(config.autoNavigationEvents == true)
    #expect(config.autoUrlEvents == true)
}

@MainActor
@Test
func analyticsCombinePublisherFansOutToMultipleSubscribers() async {
    let bus = App8AnalyticsBus()
    var a: [String] = []
    var b: [String] = []
    let cA = bus.publisher.sink { a.append($0.name) }
    let cB = bus.publisher.sink { b.append($0.name) }

    bus.dispatch(makeAnalytic(name: "x"))

    #expect(a == ["x"])
    #expect(b == ["x"])
    cA.cancel()
    cB.cancel()
}
