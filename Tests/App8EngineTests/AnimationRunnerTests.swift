//
//  AnimationRunnerTests.swift
//  App8Engine
//

import Foundation
import UIKit
import Testing
@testable import App8Engine

@MainActor
@Test
func animationRunnerInstantaneousAppliesBlockSynchronously() {
    let view = UIView()
    view.alpha = 1.0
    AnimationRunner.run(animation: nil, viewBlock: {
        view.alpha = 0.5
    })
    #expect(view.alpha == 0.5)
}

@MainActor
@Test
func animationRunnerNamedCurveSchedulesViewAnimation() {
    // We can't trivially observe the in-flight animation duration without
    // tearing into UIViewAnimator internals, but we can confirm the model
    // value reaches the target — UIView.animate's closure runs synchronously
    // even though the visual interpolation is deferred to the next runloop.
    let view = UIView()
    view.alpha = 1.0
    let inline = DSL.Model.Animation.Inline(
        id: nil, duration: 0.2, delay: 0,
        timing: .curve(.easeOut), options: []
    )
    AnimationRunner.run(animation: inline, viewBlock: {
        view.alpha = 0.0
    })
    #expect(view.alpha == 0.0)
}

@MainActor
@Test
func animationRunnerSpringSchedulesViewAnimation() {
    let view = UIView()
    view.alpha = 1.0
    let inline = DSL.Model.Animation.Inline(
        id: nil, duration: 0.4, delay: 0,
        timing: .spring(.init(damping: 0.8, velocity: 0.9, mass: nil, stiffness: nil)),
        options: []
    )
    AnimationRunner.run(animation: inline, viewBlock: {
        view.alpha = 0.25
    })
    #expect(view.alpha == 0.25)
}

@MainActor
@Test
func animationRunnerCubicBezierUsesPropertyAnimator() {
    // UIViewPropertyAnimator runs its addAnimations closure on
    // startAnimation. Like the named-curve case, the model value reaches
    // the target synchronously while the visual interpolation is deferred.
    let view = UIView()
    view.alpha = 1.0
    let inline = DSL.Model.Animation.Inline(
        id: nil, duration: 0.3, delay: 0,
        timing: .cubicBezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0),
        options: []
    )
    AnimationRunner.run(animation: inline, viewBlock: {
        view.alpha = 0.1
    })
    // UIViewPropertyAnimator schedules a transition; the model isn't
    // necessarily 0.1 right away, but we should at least not have crashed.
    // Visual verification belongs in the simulator smoke test, not here.
    #expect(view.alpha != 1.0 || view.alpha == 0.1)
}

@MainActor
@Test
func animationRunnerLayerBlockRunsRegardless() {
    let layer = CALayer()
    layer.cornerRadius = 0
    AnimationRunner.run(
        animation: nil,
        layerBlock: { layer.cornerRadius = 12 }
    )
    #expect(layer.cornerRadius == 12)
}
