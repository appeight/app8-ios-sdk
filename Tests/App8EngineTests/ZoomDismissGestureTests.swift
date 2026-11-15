//
//  ZoomDismissGestureTests.swift
//  App8EngineTests
//
//  `interactiveDismissShouldBegin` for a zoom-pushed screen shaped like the
//  A detail page: a stretchy-top vertical scroll view whose top child
//  is a 500 pt horizontal paging gallery. A back drag over the gallery on its
//  first page, at rest, starts the full-width pop; any drag the gallery can
//  use (it is moving, has content that way, or the drag is forward) stays
//  with the gallery, so the two never fight over one drag.
//

import Testing
import UIKit
@testable import App8Engine

@MainActor
@Suite("Zoom transition interactive dismiss")
struct ZoomDismissGestureTests {

    private let width: CGFloat = 390
    private let pages = 4

    /// root ⊃ stretchy-top scroll ⊃ gallery pager ⊃ page content.
    private func makeScreen(
        page: Int,
        rtl: Bool = false,
        scrollClass: UIScrollView.Type = UIScrollView.self,
        configure: (UIScrollView) -> Void = { _ in }
    ) -> (root: UIView, gallery: UIScrollView) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 844))
        if rtl { root.semanticContentAttribute = .forceRightToLeft }

        let scroll = App8ZoomingScrollView(frame: root.bounds)
        scroll.claimsPullDown = true
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentSize = CGSize(width: width, height: 1400)
        root.addSubview(scroll)

        let gallery = scrollClass.init(frame: CGRect(x: 0, y: 0, width: width, height: 500))
        gallery.isPagingEnabled = true
        if rtl { gallery.semanticContentAttribute = .forceRightToLeft }
        gallery.contentInsetAdjustmentBehavior = .never
        gallery.contentSize = CGSize(width: width * CGFloat(pages), height: 500)
        for i in 0..<pages {
            gallery.addSubview(UIView(frame: CGRect(x: width * CGFloat(i), y: 0, width: width, height: 500)))
        }
        gallery.contentOffset = CGPoint(x: width * CGFloat(page), y: 0)
        configure(gallery)
        scroll.addSubview(gallery)

        let info = UIView(frame: CGRect(x: 0, y: 500, width: width, height: 900))
        scroll.addSubview(info)
        return (root, gallery)
    }

    private func begins(_ root: UIView, at point: CGPoint, velocity: CGPoint, willBegin: Bool = true) -> Bool {
        NativeZoomTransition.shouldBeginDismiss(
            gesture: .any, location: point, velocity: velocity, willBegin: willBegin, zoomedView: root
        )
    }

    private let right = CGPoint(x: 290, y: 9)
    private let left = CGPoint(x: -290, y: 9)
    private let midGallery = CGPoint(x: 202, y: 350)

    @Test func backDragMidGalleryOnFirstPagePops() {
        let (root, _) = makeScreen(page: 0)
        #expect(begins(root, at: midGallery, velocity: right))
    }

    @Test func backDragMidGalleryOnLaterPagePagesBack() {
        let (root, _) = makeScreen(page: 1)
        #expect(!begins(root, at: midGallery, velocity: right))
    }

    @Test func forwardDragAlwaysStaysWithTheGallery() {
        let (root, _) = makeScreen(page: 0)
        #expect(!begins(root, at: midGallery, velocity: left))
        // On the last page it rubber-bands; it never dismisses.
        let (last, _) = makeScreen(page: pages - 1)
        #expect(!begins(last, at: midGallery, velocity: left))
    }

    @Test func movingGalleryKeepsABackDragOnItsFirstPage() {
        // Snapping back to page 0 from a fling: offset already at 0, still decelerating.
        let (decelerating, _) = makeScreen(page: 0, scrollClass: MovingScrollView.self) { ($0 as! MovingScrollView).movingByMomentum = true }
        #expect(!begins(decelerating, at: midGallery, velocity: right))
        let (dragging, _) = makeScreen(page: 0, scrollClass: MovingScrollView.self) { ($0 as! MovingScrollView).movingByFinger = true }
        #expect(!begins(dragging, at: midGallery, velocity: right))
        // Bouncing back after being pulled past its leading end.
        let (bouncing, gallery) = makeScreen(page: 0)
        gallery.contentOffset.x = -30
        #expect(!begins(bouncing, at: midGallery, velocity: right))
    }

    @Test func galleryWithLeadingInsetAtRestLeavesABackDragToThePop() {
        let (root, gallery) = makeScreen(page: 0)
        gallery.contentInset.left = 16
        gallery.contentOffset.x = -16
        #expect(begins(root, at: midGallery, velocity: right))
    }

    @Test func leadingEdgeDragPopsOverAnyPage() {
        let (root, _) = makeScreen(page: 2)
        #expect(begins(root, at: CGPoint(x: 12, y: 350), velocity: right))
    }

    @Test func backDragBelowGalleryPops() {
        let (root, _) = makeScreen(page: 2)
        #expect(begins(root, at: CGPoint(x: 202, y: 700), velocity: right))
    }

    @Test func pullDownBelongsToStretchyTop() {
        let (root, _) = makeScreen(page: 0)
        #expect(!begins(root, at: midGallery, velocity: CGPoint(x: 5, y: 400)))
    }

    @Test func zoomedGalleryKeepsThePan() {
        let (root, gallery) = makeScreen(page: 0)
        gallery.maximumZoomScale = 3
        let content = gallery.subviews[0]
        gallery.delegate = ZoomDelegate.shared
        ZoomDelegate.shared.view = content
        gallery.zoomScale = 2
        #expect(!begins(root, at: midGallery, velocity: right))
    }

    @Test func rightToLeftBackDragOnFirstPagePops() {
        // RTL pagers show their first page at the maximum offset; back is a
        // drag to the left.
        let (root, _) = makeScreen(page: pages - 1, rtl: true)
        #expect(begins(root, at: midGallery, velocity: left))
        let (later, _) = makeScreen(page: pages - 2, rtl: true)
        #expect(!begins(later, at: midGallery, velocity: left))
    }

    // UIKit asks with `willBegin == false` for a back drag over the pager's
    // later page (measured on device, SDK 0.5.2: the old early `return true`
    // popped the screen instead of paging back).
    @Test func uikitDefaultDoesNotOverrideTheGallerysClaim() {
        let (later, _) = makeScreen(page: 1)
        #expect(!begins(later, at: midGallery, velocity: right, willBegin: false))
        let (last, _) = makeScreen(page: pages - 1)
        #expect(!begins(last, at: midGallery, velocity: left, willBegin: false))
        let (zoomed, gallery) = makeScreen(page: 0)
        gallery.maximumZoomScale = 3
        gallery.delegate = ZoomDelegate.shared
        ZoomDelegate.shared.view = gallery.subviews[0]
        gallery.zoomScale = 2
        #expect(!begins(zoomed, at: midGallery, velocity: CGPoint(x: 9, y: 400), willBegin: false))
        // Nothing claims it: the pop still begins.
        let (first, _) = makeScreen(page: 0)
        #expect(begins(first, at: midGallery, velocity: right, willBegin: false))
    }

    // On a real drag the pager's pan has often begun (not yet scrolled) when
    // the dismiss is asked; once the dismiss begins the pager must let go.
    @Test func dismissReleasesThePagersPan() {
        let (root, gallery) = makeScreen(page: 0, scrollClass: ToggleCountingScrollView.self)
        let pan = gallery.panGestureRecognizer as UIGestureRecognizer
        let counter = gallery as! ToggleCountingScrollView
        counter.watch(pan)
        NativeZoomTransition.releaseHorizontalScrollers(at: midGallery, in: root)
        #expect(counter.disabledCount == 1)
        #expect(pan.isEnabled)
    }

    @Test func disabledScrollerNeverKeepsThePan() {
        let (root, gallery) = makeScreen(page: 1)
        gallery.isScrollEnabled = false
        #expect(begins(root, at: midGallery, velocity: right))
    }
}

@MainActor
private final class ZoomDelegate: NSObject, UIScrollViewDelegate {
    static let shared = ZoomDelegate()
    weak var view: UIView?
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { view }
}

/// A scroll view whose motion state a test can set.
private final class MovingScrollView: UIScrollView {
    var movingByMomentum = false
    var movingByFinger = false
    override var isDecelerating: Bool { movingByMomentum }
    override var isDragging: Bool { movingByFinger }
}

/// Counts how often its pan was switched off (the release toggles it).
@MainActor
private final class ToggleCountingScrollView: UIScrollView {
    private(set) var disabledCount = 0
    private var observation: NSKeyValueObservation?
    func watch(_ pan: UIGestureRecognizer) {
        observation = pan.observe(\.isEnabled, options: [.new]) { [weak self] _, change in
            MainActor.assumeIsolated {
                if change.newValue == false { self?.disabledCount += 1 }
            }
        }
    }
}
