import UIKit

protocol HoverResponder {
    func shouldHover(point: CGPoint) -> Bool
    func hover()
    func unhover()
}

extension HoverResponder {
    func shouldHover(point: CGPoint) -> Bool {
        true
    }
    func hover() {}
    func unhover() {}
}

extension HoverResponder where Self: UIView {
    @MainActor
    func shouldHover(point: CGPoint) -> Bool {
        bounds.contains(point)
    }
}

protocol PassThroughHoverResponder: HoverResponder {}

protocol HoverAnimationsProvider: HoverResponder {
    func hoverAnimations()
    func unhoverAnimations()
}

protocol CustomHoverAnimationApplicable: HoverAnimationsProvider {
    @MainActor func performCustomHoverAnimation()
    @MainActor func performCustomUnhoverAnimation()
}

struct DefaultHoverAnimationApplicable: CustomHoverAnimationApplicable {
    let provider: HoverAnimationsProvider

    func hoverAnimations() {
        provider.hoverAnimations()
    }

    func unhoverAnimations() {
        provider.unhoverAnimations()
    }
}

extension CustomHoverAnimationApplicable {

    @MainActor
    func performCustomHoverAnimation() {
        UIView.animate(withDuration: 0.1, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 1, options: [.curveEaseOut, .allowUserInteraction], animations: {
            self.hoverAnimations()
        }, completion: nil)
    }
    
    @MainActor
    func performCustomUnhoverAnimation() {
        UIView.animate(withDuration: 0.4, delay: 0.1, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.9, options: [.curveEaseOut, .allowUserInteraction], animations: {
            self.unhoverAnimations()
        }, completion: nil)
    }
}

protocol HoverTouchesHandler: AnyObject {
    @MainActor var mostParentView: UIView { get }
    @MainActor var selfAsView: UIView { get }
}

extension UIView: HoverTouchesHandler {
    @MainActor
    var selfAsView: UIView { self }
}

extension UIViewController: HoverTouchesHandler {
    @MainActor
    var mostParentView: UIView { view }
    @MainActor
    var selfAsView: UIView { view }
}

extension HoverTouchesHandler {

    @MainActor
    func handlePassThroughHoverResponder(_ touches: Set<UITouch>, action: (PassThroughHoverResponder, CGPoint?, Bool) -> Void) {
        var capturedResponders: Set<UIView> = Set([selfAsView])
        selfAsView.traverseTopToBottomAcrossParents { view in
            if let responder = view as? PassThroughHoverResponder, !capturedResponders.contains(view) {
                if let touch = touches.first {
                    let point = selfAsView.convert(touch.location(in: selfAsView), to: view)
                    if view.bounds.contains(point) {
                        action(responder, point, view.bounds.contains(point))
                        return false
                    }
                }
                action(responder, nil, false)
                capturedResponders.insert(view)
            }
            return true
        }
    }
    
    @MainActor
    func hover(_ responder: Any, point: CGPoint) {
        guard
            let responder = responder as? HoverResponder,
            responder.shouldHover(point: point)
        else { return }
        responder.hover()
        if let applicable = responder as? CustomHoverAnimationApplicable {
            applicable.performCustomHoverAnimation()
        }
        else if let provider = responder as? HoverAnimationsProvider {
            let applicable = DefaultHoverAnimationApplicable(provider: provider)
            applicable.performCustomHoverAnimation()
        }
    }
    
    @MainActor
    func unhover(_ responder: Any) {
        guard let responder = responder as? HoverResponder else { return }
        responder.unhover()
        if let applicable = responder as? CustomHoverAnimationApplicable {
            applicable.performCustomUnhoverAnimation()
        }
        else if let provider = responder as? HoverAnimationsProvider {
            let applicable = DefaultHoverAnimationApplicable(provider: provider)
            applicable.performCustomUnhoverAnimation()
        }
    }
}
