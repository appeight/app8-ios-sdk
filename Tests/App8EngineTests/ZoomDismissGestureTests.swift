//
//  ZoomDismissGestureTests.swift
//  App8EngineTests
//
//  `interactiveDismissShouldBegin` for a zoom-pushed screen shaped like the
//  DemoStore product page: a stretchy-top vertical scroll view whose top child
//  is a 500 pt horizontal paging gallery. A back drag over the gallery on its
//  first page must start the full-width pop instead of being vetoed for the
//  pager (it used to be, so a pop begun mid-screen did nothing).
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
    private func makeScreen(page: Int, rtl: Bool = false) -> (root: UIView, gallery: UIScrollView) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 844))
        if rtl { root.semanticContentAttribute = .forceRightToLeft }

        let scroll = App8ZoomingScrollView(frame: root.bounds)
        scroll.claimsPullDown = true
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentSize = CGSize(width: width, height: 1400)
        root.addSubview(scroll)

        let gallery = UIScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 500))
        gallery.isPagingEnabled = true
        gallery.contentInsetAdjustmentBehavior = .never
        gallery.contentSize = CGSize(width: width * CGFloat(pages), height: 500)
        for i in 0..<pages {
            gallery.addSubview(UIView(frame: CGRect(x: width * CGFloat(i), y: 0, width: width, height: 500)))
        }
        gallery.contentOffset = CGPoint(x: width * CGFloat(page), y: 0)
        scroll.addSubview(gallery)

        let info = UIView(frame: CGRect(x: 0, y: 500, width: width, height: 900))
        scroll.addSubview(info)
        return (root, gallery)
    }

    private func begins(_ root: UIView, at point: CGPoint, velocity: CGPoint) -> Bool {
        NativeZoomTransition.shouldBeginDismiss(
            gesture: .any, location: point, velocity: velocity, willBegin: true, zoomedView: root
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

    @Test func forwardDragPagesWhileGalleryHasMorePages() {
        let (root, _) = makeScreen(page: 0)
        #expect(!begins(root, at: midGallery, velocity: left))
        let (last, _) = makeScreen(page: pages - 1)
        #expect(begins(last, at: midGallery, velocity: left))
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
