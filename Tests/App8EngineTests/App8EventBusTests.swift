//
//  App8EventBusTests.swift
//  App8Engine
//
//  Host-facing event bus: closure / filtered / delegate / Combine paths,
//  plus subscription cancel semantics.
//

import Foundation
import Combine
import Testing
@testable import App8Engine

private func makeEvent(name: String = "test.event", screenId: String = "screen-a", locale: String? = nil) -> App8Event {
    App8Event(
        name: name,
        screenId: screenId,
        componentId: "button",
        componentType: "view",
        locale: locale,
        payload: [:]
    )
}

@MainActor
@Test
func localeRidesOnEvents() async {
    let bus = App8EventBus()
    var captured: App8Event?
    let sub = bus.subscribe { captured = $0 }
    bus.dispatch(makeEvent(locale: "de-DE"))
    #expect(captured?.locale == "de-DE")
    sub.cancel()
}

@MainActor
@Test
func closureSubscribersReceiveDispatchedEvents() async {
    let bus = App8EventBus()
    var received: [String] = []
    let sub = bus.subscribe { event in received.append(event.name) }

    bus.dispatch(makeEvent(name: "first"))
    bus.dispatch(makeEvent(name: "second"))

    #expect(received == ["first", "second"])
    sub.cancel()
}

@MainActor
@Test
func cancellingSubscriptionStopsDelivery() async {
    let bus = App8EventBus()
    var received: [String] = []
    let sub = bus.subscribe { received.append($0.name) }

    bus.dispatch(makeEvent(name: "before"))
    sub.cancel()
    bus.dispatch(makeEvent(name: "after"))

    #expect(received == ["before"])
}

@MainActor
@Test
func subscriptionDeinitCancels() async {
    let bus = App8EventBus()
    var received: [String] = []
    do {
        _ = bus.subscribe { received.append($0.name) }
        // Discarded immediately — RAII deinit should cancel.
    }
    bus.dispatch(makeEvent(name: "afterDrop"))
    #expect(received.isEmpty)
}

@MainActor
@Test
func nameFilteredSubscriberOnlySeesMatchingEvents() async {
    let bus = App8EventBus()
    var received: [String] = []
    let sub = bus.subscribe(to: "match") { received.append($0.name) }

    bus.dispatch(makeEvent(name: "other"))
    bus.dispatch(makeEvent(name: "match"))
    bus.dispatch(makeEvent(name: "alsoOther"))

    #expect(received == ["match"])
    sub.cancel()
}

@MainActor
@Test
func screenFilteredSubscriberOnlySeesMatchingScreen() async {
    let bus = App8EventBus()
    var received: [String] = []
    let sub = bus.subscribe(onScreen: "screen-b") { received.append($0.screenId) }

    bus.dispatch(makeEvent(screenId: "screen-a"))
    bus.dispatch(makeEvent(screenId: "screen-b"))

    #expect(received == ["screen-b"])
    sub.cancel()
}

@MainActor
@Test
func combinePublisherEmitsToEachSubscriberIndependently() async {
    let bus = App8EventBus()
    var a: [String] = []
    var b: [String] = []
    let cancellableA = bus.publisher.sink { a.append($0.name) }
    let cancellableB = bus.publisher.sink { b.append($0.name) }

    bus.dispatch(makeEvent(name: "x"))
    bus.dispatch(makeEvent(name: "y"))

    #expect(a == ["x", "y"])
    #expect(b == ["x", "y"])
    cancellableA.cancel()
    cancellableB.cancel()
}

@MainActor
private final class TestEventHandler: App8EventHandler {
    var events: [App8Event] = []
    func app8DidEmit(_ event: App8Event) { events.append(event) }
}

@MainActor
@Test
func delegateHandlerReceivesEvents() async {
    let bus = App8EventBus()
    let handler = TestEventHandler()
    bus.delegate = handler

    bus.dispatch(makeEvent(name: "viaDelegate"))

    #expect(handler.events.count == 1)
    #expect(handler.events.first?.name == "viaDelegate")
}
