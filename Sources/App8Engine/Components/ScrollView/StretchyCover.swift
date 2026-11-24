import UIKit

/// One pull of a stretchy top (scroll-view.md, "Stretchy top"), from the
/// first frame the content is pulled down past its top until it is back at
/// rest.
///
/// At a pull of `d` points the hero's frame grows taller by `d`: its top
/// stays on the scroll view's top edge and its bottom moves down with the
/// content. Only the hero's background scales to cover the taller frame: its
/// own material (fill, texture, glass) and every child that covers the whole
/// hero at rest (a photo, a video, a photo pager, a scrim). They get the
/// uniform scale `(h + d) / h` about the hero's bottom centre, so a pager
/// keeps its bounds and paging. Every other child keeps its constraints and
/// is laid out again in the taller frame: a block pinned to the hero's
/// bottom moves down with it at its own size, one pinned to the top stays at
/// the top, a centred one re-centres.
///
/// The hero's height is held at its rest value for the whole pull. A hero
/// whose height comes from its content (a minimum such as `height >= width`
/// plus children pinned to the safe area) would otherwise follow the pull:
/// inside a scroll view the safe area stays put on screen, so the hero lost
/// height as fast as it was pulled and nothing moved.
///
/// A hero that is not a `view` (an image, a video, a pager, a stack with a
/// height of its own) is all background: it scales as a whole.
@MainActor
final class StretchyCoverSession {

    let hero: UIView
    private let restHeight: CGFloat
    private var heightLock: NSLayoutConstraint?
    /// `view` heroes: the content view the children are laid out in, and its
    /// top constraint to the hero (moved up by the pull).
    private var contentTop: NSLayoutConstraint?
    private var contentTopRest: CGFloat = 0
    /// Views scaled with the pull: the hero's own background views and the
    /// children covering it (or the whole hero when it has no content view).
    private var scaled: [UIView] = []
    /// Covering children's top constraints, held at their rest frame (offset
    /// by the pull) so they scale instead of growing.
    private var coverTops: [(constraint: NSLayoutConstraint, rest: CGFloat, childFirst: Bool)] = []
    /// Children pinned to both the top and the bottom: their top constraint
    /// is lifted and their height held, so they follow the bottom edge at
    /// their own size instead of stretching.
    private var liftedTops: [NSLayoutConstraint] = []
    private var heldHeights: [NSLayoutConstraint] = []
    private let heroClipped: Bool

    init(hero: UIView) {
        self.hero = hero
        restHeight = hero.bounds.height
        heroClipped = hero.clipsToBounds
        guard let view = hero as? CView, let top = Self.topConstraint(of: view.contentView, to: view) else {
            scaled = [hero]
            return
        }
        let content = view.contentView
        contentTop = top
        contentTopRest = top.constant

        let lock = hero.heightAnchor.constraint(equalToConstant: restHeight)
        lock.identifier = "app8.stretchyTop.height"
        lock.isActive = true
        heightLock = lock
        hero.clipsToBounds = false

        // The hero's own background: everything in it below the content view.
        if let index = hero.subviews.firstIndex(of: content) {
            scaled += hero.subviews[..<index].filter { !$0.isHidden }
        }
        let bounds = content.bounds
        for child in content.subviews where !child.isHidden {
            let constraints = Self.constraints(of: child, in: content)
            let tops = constraints.filter { Self.pins(child, .top, to: content, $0) }
            let bottoms = constraints.filter { Self.pins(child, .bottom, to: content, $0) }
            if child.frame.insetBy(dx: 1, dy: 1).contains(bounds.insetBy(dx: 1, dy: 1)) || child.frame == bounds {
                // Covers the hero: background. Held at its rest frame, scaled.
                scaled.append(child)
                coverTops += tops.map { ($0, $0.constant, $0.firstItem === child) }
            } else if !tops.isEmpty, !bottoms.isEmpty {
                liftedTops += tops
                let hold = child.heightAnchor.constraint(equalToConstant: child.bounds.height)
                hold.identifier = "app8.stretchyTop.childHeight"
                heldHeights.append(hold)
            }
        }
        NSLayoutConstraint.deactivate(liftedTops)
        NSLayoutConstraint.activate(heldHeights)
    }

    func update(pull d: CGFloat) {
        let transform = Self.scale(height: restHeight, pull: d)
        if let contentTop {
            contentTop.constant = contentTopRest - d
            // The content view's top moved up by `d`: a covering child keeps
            // its rest frame (`child.top == content.top + c` gets `c + d`).
            for cover in coverTops {
                cover.constraint.constant = cover.rest + (cover.childFirst ? d : -d)
            }
            hero.layoutIfNeeded()
        }
        for view in scaled {
            view.transform = Self.transform(transform, for: view, in: hero, restHeight: restHeight)
        }
    }

    func end() {
        for view in scaled { view.transform = .identity }
        contentTop?.constant = contentTopRest
        for cover in coverTops { cover.constraint.constant = cover.rest }
        NSLayoutConstraint.deactivate(heldHeights)
        NSLayoutConstraint.activate(liftedTops)
        heightLock?.isActive = false
        hero.clipsToBounds = heroClipped
        hero.setNeedsLayout()
    }

    // MARK: - Geometry

    /// Uniform scale `(h + d) / h` about the bottom edge's centre, for a view
    /// `h` tall whose anchor is its centre.
    nonisolated static func scale(height h: CGFloat, pull d: CGFloat) -> CGAffineTransform {
        guard h > 0.5, d > 0 else { return .identity }
        let s = (h + d) / h
        return CGAffineTransform(translationX: 0, y: -(h * (s - 1)) / 2).scaledBy(x: s, y: s)
    }

    /// The hero's scale, applied to `view` (the hero itself or a view inside
    /// it): about the hero's bottom centre, whatever the view's own frame.
    private static func transform(_ heroTransform: CGAffineTransform, for view: UIView, in hero: UIView, restHeight h: CGFloat) -> CGAffineTransform {
        guard view !== hero, heroTransform != .identity else { return heroTransform }
        let s = heroTransform.a
        // The view's centre relative to the hero's bottom centre, at rest.
        let center = view.superview?.convert(view.center, to: hero) ?? view.center
        let pivot = CGPoint(x: hero.bounds.midX, y: h)
        let dx = (center.x - pivot.x) * (s - 1)
        let dy = (center.y - pivot.y) * (s - 1)
        return CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
    }

    // MARK: - Constraints

    private static func topConstraint(of content: UIView, to hero: UIView) -> NSLayoutConstraint? {
        hero.constraints.first { c in
            c.isActive && c.relation == .equal && c.firstAttribute == .top && c.secondAttribute == .top
                && ((c.firstItem === content && c.secondItem === hero) || (c.firstItem === hero && c.secondItem === content))
        }.flatMap { c in
            // Normalise to `content.top == hero.top + constant`.
            c.firstItem === content ? c : nil
        }
    }

    private static func constraints(of child: UIView, in content: UIView) -> [NSLayoutConstraint] {
        var all = content.constraints + child.constraints
        if let owner = child as? App8ConstraintOwning { all += owner.app8InstalledConstraints }
        var seen = Set<ObjectIdentifier>()
        return all.filter { $0.isActive && seen.insert(ObjectIdentifier($0)).inserted }
    }

    /// Whether `c` ties `child`'s `edge` to the same edge of `content` (or of
    /// its safe area / margins).
    private static func pins(_ child: UIView, _ edge: NSLayoutConstraint.Attribute, to content: UIView, _ c: NSLayoutConstraint) -> Bool {
        func isContent(_ item: AnyObject?) -> Bool {
            if item === content { return true }
            if let guide = item as? UILayoutGuide { return guide.owningView === content }
            return false
        }
        guard c.relation == .equal else { return false }
        if c.firstItem === child, c.firstAttribute == edge, c.secondAttribute == edge, isContent(c.secondItem) { return true }
        if c.secondItem === child, c.secondAttribute == edge, c.firstAttribute == edge, isContent(c.firstItem) { return true }
        return false
    }
}
