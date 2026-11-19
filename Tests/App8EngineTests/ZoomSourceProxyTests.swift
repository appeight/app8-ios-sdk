//
//  ZoomSourceProxyTests.swift
//  App8EngineTests
//
//  A zoom source that fills the presenting screen (a full-screen pager page's
//  photo) stays visible during the transition: UIKit gets a transparent
//  stand-in at its frame to hide. A smaller source (a card in a grid) is
//  handed over as is, so its slot empties as the system does.
//

import XCTest
@testable import App8Engine

@MainActor
final class ZoomSourceProxyTests: XCTestCase {

    private func screen() -> UIView { UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874)) }

    func testFullScreenSourceGetsAStandIn() {
        let root = screen()
        let photo = UIView(frame: root.bounds)
        photo.layer.cornerRadius = 12
        root.addSubview(photo)
        let source = SourceProxy.source(for: photo, in: root, coordinator: nil)
        XCTAssertFalse(source === photo, "the photo itself stays visible")
        XCTAssertTrue(source.superview === root)
        XCTAssertEqual(source.frame, photo.frame)
        XCTAssertEqual(source.layer.cornerRadius, 12)
        XCTAssertFalse(source.isUserInteractionEnabled)
        // Asked again (the dismissal): one stand-in, not two.
        let again = SourceProxy.source(for: photo, in: root, coordinator: nil)
        XCTAssertNil(source.superview)
        XCTAssertTrue(again.superview === root)
        again.removeFromSuperview()
    }

    func testCardSourceIsHandedOverAsIs() {
        let root = screen()
        let card = UIView(frame: CGRect(x: 16, y: 120, width: 180, height: 240))
        root.addSubview(card)
        XCTAssertTrue(SourceProxy.source(for: card, in: root, coordinator: nil) === card)
    }

    func testCoverageCountsOnlyTheVisiblePart() {
        let root = screen()
        // A tall page scrolled mostly off screen.
        let page = UIView(frame: CGRect(x: 0, y: -700, width: 402, height: 874))
        root.addSubview(page)
        XCTAssertFalse(SourceProxy.covers(page, root))
        page.frame.origin.y = -60
        XCTAssertTrue(SourceProxy.covers(page, root))
    }
}
