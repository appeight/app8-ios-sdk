import AVFoundation
import Foundation

/// Encapsulates all AVFoundation observation for `CVideoView` — KVO on the
/// player / layer / item / looper, the play-to-end notification, and boundary
/// time observers for `marks` — and surfaces them as plain MainActor callbacks.
/// Keeping this out of the view keeps `CVideoView` focused on layout and poster
/// state.
///
/// One observer instance is attached per built player; `detach()` (from the
/// view's teardown) tears everything down. KVO/notifications may be delivered
/// off the main thread, so every callback is hopped onto the MainActor; only
/// `Sendable` values are carried across the hop.
@MainActor
final class VideoPlaybackObserver {

    /// Item is `.readyToPlay` — startup (seek / delay / play) is now safe.
    var onReadyToPlay: (() -> Void)?
    var onStart: (() -> Void)?
    var onPause: (() -> Void)?
    var onStall: (() -> Void)?
    var onLoop: ((Int) -> Void)?
    var onError: ((String?) -> Void)?
    var onComplete: (() -> Void)?
    var onMark: ((String) -> Void)?

    private var observations: [NSKeyValueObservation] = []
    private var boundaryToken: Any?
    private var endObserver: NSObjectProtocol?
    private weak var player: AVPlayer?

    /// Fire `onReadyToPlay` only on the first transition into `.readyToPlay`.
    private var didBecomeReady = false

    /// Fire `onStart` only on the first transition into `.playing` per play-through.
    private var didStart = false
    private var lastLoopCount = 0

    private var marks: [DSL.Model.Component.Video.Mark] = []
    private var firedMarkIds: Set<String> = []

    /// Tolerance (seconds) for matching a boundary callback to a mark time.
    private static let markTolerance = 0.3

    func attach(
        player: AVPlayer,
        item: AVPlayerItem,
        looper: AVPlayerLooper?,
        marks: [DSL.Model.Component.Video.Mark],
        loops: Bool
    ) {
        detach()
        self.player = player
        self.marks = marks

        // Readiness / failure — drive startup off the player's status, which
        // reaches `.readyToPlay` for both a direct item (non-loop) and the
        // looper's enqueued replicas (loop). `seek` / `rate` / `play` issued
        // before this point are silently dropped, so startup is gated on it.
        observations.append(player.observe(\.status, options: [.new]) { player, _ in
            let status = player.status
            let message = player.error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    guard !self.didBecomeReady else { return }
                    self.didBecomeReady = true
                    self.onReadyToPlay?()
                case .failed:
                    self.onError?(message)
                default:
                    break
                }
            }
        })

        // Start / pause / stall.
        observations.append(player.observe(\.timeControlStatus, options: [.new]) { player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .playing:
                    if !self.didStart {
                        self.didStart = true
                        self.onStart?()
                    }
                case .paused:
                    self.onPause?()
                case .waitingToPlayAtSpecifiedRate:
                    self.onStall?()
                @unknown default:
                    break
                }
            }
        })

        if loops {
            // Looping: the looper consumes item-end; track loop cycles instead.
            if let looper {
                lastLoopCount = looper.loopCount
                observations.append(looper.observe(\.loopCount, options: [.new]) { looper, _ in
                    let count = looper.loopCount
                    Task { @MainActor [weak self] in
                        guard let self, count > self.lastLoopCount else { return }
                        self.lastLoopCount = count
                        self.firedMarkIds.removeAll()   // re-arm marks each cycle
                        self.onLoop?(count)
                    }
                })
            }
        } else {
            // Non-looping: fire complete when the item plays to the end.
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                Task { @MainActor [weak self] in self?.onComplete?() }
            }
        }

        // Marks — forward-only boundary observers.
        if !marks.isEmpty {
            let times = marks.map { NSValue(time: CMTime(seconds: $0.time, preferredTimescale: 600)) }
            boundaryToken = player.addBoundaryTimeObserver(forTimes: times, queue: .main) { [weak self] in
                Task { @MainActor in self?.handleBoundaryCrossing() }
            }
        }
    }

    /// Re-arm `onStart` and marks for a fresh play-through (once-per-appearance
    /// replay). Does not touch loop bookkeeping.
    func resetForReplay() {
        didStart = false
        firedMarkIds.removeAll()
    }

    func detach() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        if let boundaryToken, let player {
            player.removeTimeObserver(boundaryToken)
        }
        boundaryToken = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player = nil
        didStart = false
        didBecomeReady = false
        lastLoopCount = 0
        firedMarkIds.removeAll()
        marks = []
    }

    private func handleBoundaryCrossing() {
        guard let player, let item = player.currentItem else { return }
        let now = item.currentTime().seconds
        guard now.isFinite else { return }
        // Fire every not-yet-fired mark within tolerance of the crossing point.
        for mark in marks where !firedMarkIds.contains(mark.id) {
            if abs(mark.time - now) <= Self.markTolerance {
                firedMarkIds.insert(mark.id)
                onMark?(mark.id)
            }
        }
    }
}
