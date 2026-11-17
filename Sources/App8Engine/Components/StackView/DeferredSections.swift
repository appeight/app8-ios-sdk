//
//  DeferredSections.swift
//  App8Engine
//
//  DSL "Deferred sections": a stack child with `defer` is not built with its
//  screen. A placeholder holds its slot, and the child is built once the
//  screen is in the window (the navigation transition has started), a few
//  per frame, then swapped in with a short fade.
//

import QuartzCore
import UIKit

@MainActor
final class DeferredBuildQueue {

    static let shared = DeferredBuildQueue()

    /// Budget per frame; at least one ready job runs every frame.
    static let frameBudget: CFTimeInterval = 0.006

    /// > 0 while a screen is being built: only then is `defer` honoured
    /// (collection cells and later rebuilds build everything at once).
    private(set) var screenBuildDepth = 0
    /// True while a deferred component is being built: `defer` inside it is ignored.
    private(set) var isBuildingDeferred = false

    var defersNow: Bool { screenBuildDepth > 0 && !isBuildingDeferred }

    private struct Job {
        weak var anchor: UIView?
        let build: () -> Void
    }

    private var jobs: [Job] = []
    private var link: CADisplayLink?

    func buildingScreen<T>(_ body: () -> T) -> T {
        screenBuildDepth += 1
        defer { screenBuildDepth -= 1 }
        return body()
    }

    /// Queues `build` to run once `anchor` (the placeholder) is in a window.
    func enqueue(anchor: UIView, build: @escaping () -> Void) {
        jobs.append(Job(anchor: anchor, build: build))
        guard link == nil else { return }
        let link = CADisplayLink(target: DisplayLinkTarget(queue: self), selector: #selector(DisplayLinkTarget.step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Whether the screen holding `view` is being pushed, popped or presented.
    static func isInTransition(_ view: UIView) -> Bool {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller.transitionCoordinator != nil
                    || controller.navigationController?.transitionCoordinator != nil
            }
            responder = current.next
        }
        return false
    }

    fileprivate func step() {
        let start = CACurrentMediaTime()
        var ranOne = false
        var index = 0
        while index < jobs.count {
            guard let anchor = jobs[index].anchor else {
                jobs.remove(at: index) // its screen is gone
                continue
            }
            guard anchor.window != nil, !Self.isInTransition(anchor) else {
                // Not on screen yet, or its push/zoom is still running (a
                // section takes tens of ms to build: it would drop frames of
                // the transition). Keep it, try the next.
                index += 1
                continue
            }
            if ranOne && CACurrentMediaTime() - start > Self.frameBudget { break }
            let job = jobs.remove(at: index)
            isBuildingDeferred = true
            job.build()
            isBuildingDeferred = false
            ranOne = true
        }
        if jobs.isEmpty {
            link?.invalidate()
            link = nil
        }
    }
}

/// CADisplayLink retains its target; this one holds the queue weakly.
@MainActor
private final class DisplayLinkTarget: NSObject {
    weak var queue: DeferredBuildQueue?
    init(queue: DeferredBuildQueue) { self.queue = queue }
    @objc func step() { queue?.step() }
}

/// Holds a deferred child's slot in its stack: empty space, or a neutral
/// rounded block with a sweeping highlight.
final class DeferredPlaceholderView: UIView {

    private let highlight = CAGradientLayer()
    private let shimmers: Bool

    init(deferral: DSL.Model.Component.`Any`.Deferral, axis: NSLayoutConstraint.Axis) {
        shimmers = deferral.placeholder == .shimmer
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        translatesAutoresizingMaskIntoConstraints = false
        let length = CGFloat(max(0, axis == .vertical ? deferral.estimatedHeight ?? 0 : deferral.estimatedWidth ?? 0))
        let size = axis == .vertical ? heightAnchor.constraint(equalToConstant: length) : widthAnchor.constraint(equalToConstant: length)
        size.priority = .defaultHigh
        size.isActive = true
        guard shimmers else { return }
        backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 0, alpha: 0.06) }
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        clipsToBounds = true
        highlight.startPoint = CGPoint(x: 0, y: 0.5)
        highlight.endPoint = CGPoint(x: 1, y: 0.5)
        highlight.colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor(white: 1, alpha: 0.35).cgColor, UIColor(white: 1, alpha: 0).cgColor]
        highlight.locations = [0, 0.5, 1]
        layer.addSublayer(highlight)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard shimmers else { return }
        highlight.frame = CGRect(x: 0, y: 0, width: bounds.width * 0.6, height: bounds.height)
        guard highlight.animation(forKey: "sweep") == nil, bounds.width > 0,
              !UIAccessibility.isReduceMotionEnabled else { return }
        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -bounds.width * 0.3
        sweep.toValue = bounds.width * 1.3
        sweep.duration = 1.2
        sweep.repeatCount = .infinity
        highlight.add(sweep, forKey: "sweep")
    }
}

extension UIStackView {
    /// Puts a deferred child where its placeholder is, fading it in.
    @MainActor
    func swapInDeferred(_ view: UIView, for placeholder: UIView) {
        guard let index = arrangedSubviews.firstIndex(of: placeholder) else { return }
        removeArrangedSubview(placeholder)
        placeholder.removeFromSuperview()
        insertArrangedSubview(view, at: index)
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.2
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.33, 1, 0.68, 1)
        view.layer.add(fade, forKey: "app8.deferredFadeIn")
    }
}
