import UIKit

/// A property animation with `options: ["repeat"]` (animations.md, "Repeating animations"):
/// an infinite, additive Core Animation loop from the start value to the model value.
///
/// The model value (the view's `transform` / `alpha`) is the target; the loop adds
/// `start − target` → `0` on top, so the presentation runs start → target and starts
/// over. A rotation animates `transform.rotation.z` as an angle, so a full turn spins
/// (a `UIView.animate` between two identical affine transforms never moves).
struct RepeatLoop: Equatable {
    enum Property: String, CaseIterable {
        case rotation, translateX, translateY, scale, alpha

        var layerKey: String { "a8.repeat.\(rawValue)" }

        /// The property's value at rest: where a loop starts when the view is set up again.
        var rest: CGFloat {
            switch self {
            case .rotation, .translateX, .translateY: return 0
            case .scale, .alpha: return 1
            }
        }
    }

    let property: Property
    let from: CGFloat
    let to: CGFloat
    let duration: Double
    let delay: Double
    let timing: CAMediaTimingFunction?
    let autoreverses: Bool

    init?(property: Property, from: CGFloat, to: CGFloat, animation: DSL.Model.Animation.Inline?) {
        guard let animation, animation.options.contains(.repeat), from != to else { return nil }
        self.property = property
        self.from = from
        self.to = to
        self.duration = max(animation.duration, 0.01)
        self.delay = max(animation.delay, 0)
        // A spring has no duration-based loop; it repeats on its duration, eased out.
        self.timing = animation.caTimingFunction ?? CAMediaTimingFunction(name: .easeOut)
        self.autoreverses = animation.options.contains(.autoreverse)
    }

    static func == (a: RepeatLoop, b: RepeatLoop) -> Bool {
        a.property == b.property && a.from == b.from && a.to == b.to && a.duration == b.duration
            && a.delay == b.delay && a.autoreverses == b.autoreverses
    }

    /// The additive layer animation for this loop.
    func makeAnimation() -> CABasicAnimation {
        let anim: CABasicAnimation
        switch property {
        case .rotation:
            anim = CABasicAnimation(keyPath: "transform.rotation.z")
            anim.fromValue = (from - to) * .pi / 180
            anim.toValue = 0
        case .translateX:
            anim = CABasicAnimation(keyPath: "transform.translation.x")
            anim.fromValue = from - to
            anim.toValue = 0
        case .translateY:
            anim = CABasicAnimation(keyPath: "transform.translation.y")
            anim.fromValue = from - to
            anim.toValue = 0
        case .scale:
            // Additive value-function transforms concatenate: scale by start/target → 1.
            anim = CABasicAnimation(keyPath: "transform.scale")
            anim.fromValue = to == 0 ? 0 : from / to
            anim.toValue = 1
        case .alpha:
            anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = from - to
            anim.toValue = 0
        }
        anim.isAdditive = true
        anim.duration = duration
        anim.repeatCount = .infinity
        anim.autoreverses = autoreverses
        anim.timingFunction = timing
        // Kept across app background and window changes; reinstalled if the platform drops it.
        anim.isRemovedOnCompletion = false
        if delay > 0 {
            anim.beginTime = CACurrentMediaTime() + delay
            anim.fillMode = .backwards
        }
        return anim
    }
}

/// Keeps a view's repeat loops installed: on (re)configure, when it joins a window
/// (tab switch, push/pop, a cell scrolled back) and when the app returns to the foreground.
@MainActor
final class RepeatLoops {
    private(set) var loops: [RepeatLoop.Property: RepeatLoop] = [:]
    private weak var layer: CALayer?
    nonisolated(unsafe) private var foregroundObserver: NSObjectProtocol?

    init(layer: CALayer) { self.layer = layer }

    var isEmpty: Bool { loops.isEmpty }

    /// Sets (or clears, with nil) the loop of one property; reinstalls only when it changed.
    func set(_ loop: RepeatLoop?, for property: RepeatLoop.Property) {
        guard loops[property] != loop || (loop != nil && layer?.animation(forKey: property.layerKey) == nil) else { return }
        layer?.removeAnimation(forKey: property.layerKey)
        loops[property] = loop
        if let loop { layer?.add(loop.makeAnimation(), forKey: property.layerKey) }
        observeForeground()
    }

    /// Starts every loop over from its start value. Called when the view comes back on
    /// screen (a window again, a cell displayed again, the app in the foreground): a layer
    /// that left the render tree can keep a listed animation that no longer runs, so the
    /// loops are replaced rather than checked.
    func restartAll() {
        guard let layer else { return }
        for (property, loop) in loops {
            layer.removeAnimation(forKey: property.layerKey)
            layer.add(loop.makeAnimation(), forKey: property.layerKey)
        }
    }

    private func observeForeground() {
        if loops.isEmpty {
            if let o = foregroundObserver { NotificationCenter.default.removeObserver(o) }
            foregroundObserver = nil
            return
        }
        guard foregroundObserver == nil else { return }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAll() }
        }
    }

    deinit {
        if let o = foregroundObserver { NotificationCenter.default.removeObserver(o) }
    }
}

/// A view with `repeat` loops; a collection cell restarts them when it is displayed.
@MainActor
protocol RepeatLoopHost: AnyObject {
    func restartRepeatLoops()
}

@MainActor
enum RepeatLoopRestart {
    /// Restarts the loops of [view] and everything under it.
    static func restart(in view: UIView) {
        (view as? RepeatLoopHost)?.restartRepeatLoops()
        for sub in view.subviews { restart(in: sub) }
    }
}
