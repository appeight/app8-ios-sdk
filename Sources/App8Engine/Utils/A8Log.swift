//
//  A8Log.swift
//  App8Engine
//

import Foundation

/// Centralized logger for App8Engine.
/// Each `App8.Instance` owns its own `A8Log` via `App8Context`; set the level
/// via `instance.logLevel = .debug` to enable logging for that instance.
public final class A8Log: @unchecked Sendable {

    public enum Level: Sendable {
        case none
        case debug
    }

    private let lock = NSLock()
    private var _level: Level = .none

    /// Log level — lock-guarded; may be read/written from different threads.
    public var level: Level {
        get { lock.lock(); defer { lock.unlock() }; return _level }
        set { lock.lock(); _level = newValue; lock.unlock() }
    }

    public init() {}

    func debug(_ message: @autoclosure () -> String) {
        guard level == .debug else { return }
        print("[App8Engine] \(message())")
    }

    func warning(_ message: @autoclosure () -> String) {
        guard level == .debug else { return }
        print("⚠️ [App8Engine] \(message())")
    }

    func error(_ message: @autoclosure () -> String) {
        guard level == .debug else { return }
        print("❌ [App8Engine] \(message())")
    }
}
