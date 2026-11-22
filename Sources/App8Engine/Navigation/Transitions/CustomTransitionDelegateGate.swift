//
//  CustomTransitionDelegateGate.swift
//  App8Engine
//
//  iOS 26's full-width content back swipe
//  (`UINavigationController.interactiveContentPopGestureRecognizer`) only
//  begins when the navigation controller's delegate does not answer
//  `navigationController(_:animationControllerFor:from:to:)`: a delegate that
//  merely implements it (and returns nil) turned the swipe off on every
//  pushed screen, so only the edge swipe popped. UIKit reads which delegate
//  methods exist when the delegate is set, so the engine's delegates answer
//  the transition methods only while a custom transition is in play (the top
//  screen's, or a push about to start) and the navigation controller re-reads
//  them when that changes.
//

import UIKit

@MainActor
enum CustomTransitionDelegateGate {

    static let animationSelector = #selector(UINavigationControllerDelegate.navigationController(_:animationControllerFor:from:to:))
    static let interactionSelector = #selector(UINavigationControllerDelegate.navigationController(_:interactionControllerFor:))

    static func isTransitionSelector(_ selector: Selector?) -> Bool {
        selector == animationSelector || selector == interactionSelector
    }

    /// Makes `navigationController` re-read which methods its delegate answers.
    static func refresh(_ navigationController: UINavigationController?) {
        guard let navigationController, let delegate = navigationController.delegate else { return }
        navigationController.delegate = nil
        navigationController.delegate = delegate
    }
}
