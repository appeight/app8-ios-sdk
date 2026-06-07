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

    // NSLog (not print) so engine logs surface in the same place as host NSLog
    // output — visible in the Xcode console AND Console.app. `print` only reaches
    // the Xcode debug console, which made these logs invisible to some hosts.
    func debug(_ message: @autoclosure () -> String) {
        guard level == .debug else { return }
        NSLog("[App8Engine] %@", message())
    }

    func warning(_ message: @autoclosure () -> String) {
        guard level == .debug else { return }
        NSLog("⚠️ [App8Engine] %@", message())
    }

    func error(_ message: @autoclosure () -> String) {
        guard level == .debug else { return }
        NSLog("❌ [App8Engine] %@", message())
    }
}
