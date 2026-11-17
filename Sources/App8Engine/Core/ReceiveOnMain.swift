//
//  ReceiveOnMain.swift
//  App8Engine
//

import Combine
import Foundation

extension Publisher where Failure == Never {

    /// `receive(on: DispatchQueue.main)`, except for the values the upstream
    /// emits while it is being subscribed on the main thread (the current
    /// value of a `CurrentValueSubject` or of a `@Published` property). Those
    /// are delivered inline, so a component shows its text, style and content
    /// in the same pass that builds it. With a plain main-queue hop, a screen
    /// pushed right after it is built showed its first frames with layout
    /// only: no text, no images, default tint (very visible under a zoom
    /// transition, which shows the new screen at once). Later values hop to
    /// the main queue as before.
    func receiveOnMain() -> AnyPublisher<Output, Never> {
        receiveOnMainTagged().map(\.value).eraseToAnyPublisher()
    }

    /// `receiveOnMain()` without the inline values: for sinks whose caller
    /// already applied the current value itself.
    func receiveOnMainDroppingInline() -> AnyPublisher<Output, Never> {
        receiveOnMainTagged().filter { !$0.isInline }.map(\.value).eraseToAnyPublisher()
    }

    /// `receiveOnMain()` with each value marked: `isInline` is true for a value
    /// delivered while subscribing (the starting value, to apply without
    /// animation), false for a later change.
    func receiveOnMainTagged() -> AnyPublisher<(value: Output, isInline: Bool), Never> {
        ReceiveOnMainFirstInline(upstream: self).eraseToAnyPublisher()
    }
}

private struct ReceiveOnMainFirstInline<Upstream: Publisher>: Publisher where Upstream.Failure == Never {
    typealias Output = (value: Upstream.Output, isInline: Bool)
    typealias Failure = Never

    let upstream: Upstream

    func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Never {
        let gate = InlineGate(isOpen: Thread.isMainThread)
        upstream
            .flatMap(maxPublishers: .unlimited) { value -> AnyPublisher<Output, Never> in
                if gate.isOpen && Thread.isMainThread {
                    return Just((value: value, isInline: true)).eraseToAnyPublisher()
                }
                return Just((value: value, isInline: false)).receive(on: DispatchQueue.main).eraseToAnyPublisher()
            }
            .receive(subscriber: subscriber)
        // Subscribing requested the subscriber's demand, so whatever the
        // upstream emits on subscription has been delivered by now.
        gate.isOpen = false
    }
}

private final class InlineGate: @unchecked Sendable {
    var isOpen: Bool
    init(isOpen: Bool) { self.isOpen = isOpen }
}

