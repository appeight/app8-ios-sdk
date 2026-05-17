//
//  ConstraintMonitor.swift
//  App8Engine
//

import Darwin
import Foundation

/// Captures AutoLayout constraint violation messages via a stderr tee.
/// Install-once: all output is forwarded to the original stderr (Xcode console preserved),
/// while constraint violation blocks are also parsed and accumulated.
///
/// Pipe drain runs on a background queue via `startDraining()`, which is `nonisolated`.
/// Closures created inside a `nonisolated` function cannot be inferred as `@MainActor`
/// by the Swift 6 compiler, preventing the runtime isolation check from firing when GCD
/// executes the handler on a utility thread (the root cause of EXC_BREAKPOINT crashes).
@MainActor
final class ConstraintMonitor {

    static let shared = ConstraintMonitor()
    private init() {}

    // MARK: - Public

    /// Screen ID assigned to newly captured violations. Updated by App8Service before each render.
    var currentScreenId: String?

    /// All violations captured since install() (or last clear()).
    private(set) var violations: [ConstraintViolation] = []

    /// When true, each captured violation is printed to stdout immediately.
    var liveReportingEnabled = false

    func install() {
        guard !isInstalled else { return }

        var fds = [Int32](repeating: 0, count: 2)
        guard Darwin.pipe(&fds) == 0 else { return }

        let saved = Darwin.dup(STDERR_FILENO)
        guard saved >= 0 else { Darwin.close(fds[0]); Darwin.close(fds[1]); return }

        guard Darwin.dup2(fds[1], STDERR_FILENO) >= 0 else {
            Darwin.close(fds[0]); Darwin.close(fds[1]); Darwin.close(saved); return
        }
        Darwin.close(fds[1])

        // Prevent SIGPIPE if Xcode closes its end of the original stderr pipe
        _ = Darwin.signal(SIGPIPE, SIG_IGN)

        // Make read end non-blocking so read() returns EAGAIN on spurious source wakeups
        let readFlags = Darwin.fcntl(fds[0], F_GETFL)
        if readFlags >= 0 { _ = Darwin.fcntl(fds[0], F_SETFL, readFlags | O_NONBLOCK) }

        // Write end (STDERR_FILENO) is intentionally left BLOCKING.
        // Setting O_NONBLOCK on it causes the unified logging system to drop messages
        // and emit "Logging Error: Failed to receive N log messages".
        // The background drain keeps the pipe empty so the main thread never stalls.

        pipeFds = fds
        savedStderrFd = saved
        isInstalled = true

        startDraining(readFd: fds[0], forwardFd: saved)
    }

    func clear() { violations.removeAll() }

    // MARK: - Private

    private var isInstalled = false
    private var pipeFds = [Int32](repeating: 0, count: 2)
    private var savedStderrFd: Int32 = -1
    // nonisolated(unsafe): written once from startDraining (called synchronously from install()
    // on the main thread), never written again. Safe without a lock.
    nonisolated(unsafe) private var readSource: DispatchSourceRead?
    private var pendingText = ""

    /// Creates the DispatchSource on a background queue.
    ///
    /// **Must be `nonisolated`.**  Closures created inside an `@MainActor` function are
    /// inferred as `@MainActor` by the Swift 6 compiler.  When GCD then executes the handler
    /// on a utility thread, the Swift runtime isolation check fires → EXC_BREAKPOINT (brk #1).
    /// A `nonisolated` function produces non-isolated closures, so no check is inserted.
    nonisolated private func startDraining(readFd: Int32, forwardFd: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: readFd, queue: .global(qos: .utility))
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let n = read(readFd, &buffer, buffer.count)
            guard n > 0 else { return }
            _ = Darwin.write(forwardFd, buffer, n)     // tee → original stderr
            if let text = String(bytes: buffer[..<n], encoding: .utf8) {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        ConstraintMonitor.shared.accumulate(text)
                    }
                }
            }
        }
        source.resume()
        readSource = source
    }

    private func accumulate(_ chunk: String) {
        pendingText += chunk
        parseBlocks()
        if pendingText.count > 200_000 { pendingText = String(pendingText.suffix(20_000)) }
    }

    private func printLive(_ v: ConstraintViolation) {
        let screenStr = v.screenId.map { " in \"\($0)\"" } ?? ""
        let constraintStr = v.brokenConstraint.map { ": broke \($0)" } ?? ""
        print("- WARNING [LAY001]:\(screenStr) AutoLayout conflict\(constraintStr)")
    }

    private func parseBlocks() {
        let start = "Unable to simultaneously satisfy constraints."
        let recover = "Will attempt to recover by breaking constraint"
        var from = pendingText.startIndex
        while true {
            guard let s = pendingText.range(of: start, range: from..<pendingText.endIndex),
                  let r = pendingText.range(of: recover, range: s.upperBound..<pendingText.endIndex),
                  let nl = pendingText.range(of: "\n\n", range: r.upperBound..<pendingText.endIndex)
            else { break }

            let block = String(pendingText[s.lowerBound..<nl.upperBound])
            let broken = pendingText[r.upperBound..<nl.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty

            let violation = ConstraintViolation(
                screenId: currentScreenId,
                rawMessage: block.trimmingCharacters(in: .whitespacesAndNewlines),
                brokenConstraint: broken,
                capturedAt: Date()
            )
            violations.append(violation)
            if liveReportingEnabled { printLive(violation) }
            from = nl.upperBound
        }
        if from > pendingText.startIndex { pendingText = String(pendingText[from...]) }
    }
}

// MARK: - ConstraintViolation

struct ConstraintViolation: Sendable {
    let screenId: String?
    let rawMessage: String
    let brokenConstraint: String?   // The constraint UIKit chose to break
    let capturedAt: Date
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
