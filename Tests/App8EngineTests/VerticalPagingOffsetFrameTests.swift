//
//  VerticalPagingOffsetFrameTests.swift
//  App8EngineTests
//
//  A vertical pager (`pagingStyle: paging`, `itemHeight: "fill"`) whose frame
//  does not start at the screen's top: under a band, inside the safe area, or
//  both. Every page is the pager's own frame and every page rests flush: the
//  rest offset of page n is n × the frame height, also after the frame got
//  its final height in a later layout pass (a safe area that arrives after
//  the first layout).
//

import XCTest
@testable import App8Engine

@MainActor
final class VerticalPagingOffsetFrameTests: XCTestCase {

    private static let pages = 8

    /// `top` / `bottom`: the pager's vertical constraints.
    private func screenJSON(top: String, bottom: String) -> String {
        let items = (0..<Self.pages).map { #"{ "n": \#($0 + 1) }"# }.joined(separator: ", ")
        return """
        {
          "type": "view", "id": "root",
          "content": {
            "variables": { "items": { "type": "array", "initialValue": [\(items)] }, "page": { "type": "number", "initialValue": 0 } },
            "layout": { "constraints": [
              { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
              { "type": "trailing", "target": "superview" }, { "type": "bottom", "target": "superview" } ] },
            "children": [
              { "type": "view", "id": "band",
                "content": { "layout": { "constraints": [
                  { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
                  { "type": "trailing", "target": "superview" },
                  { "type": "bottom", "target": "safeArea", "attribute": "top", "constant": 52 } ] } } },
              { "type": "collection", "id": "pager",
                "content": {
                  "properties": {
                    "data": "{{items}}",
                    "layout": { "type": "vertical", "pagingStyle": "paging", "itemHeight": "fill", "currentPageVariable": "page", "showsScrollIndicator": false }
                  },
                  "layout": { "constraints": [
                    \(top), \(bottom),
                    { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" } ] },
                  "template": { "id": "cell", "type": "view", "content": { "children": [
                    { "type": "label", "id": "n", "content": { "properties": { "text": "{{item.n}}" }, "layout": { "constraints": [
                      { "type": "centerX", "target": "superview" }, { "type": "centerY", "target": "superview" } ] } } }
                  ] } }
                } }
            ]
          }
        }
        """
    }

    private struct Host {
        let window: UIWindow
        let controller: UIViewController
        let harness: RenderHarness
        let pager: UICollectionView
    }

    private func host(top: String, bottom: String, safeArea: UIEdgeInsets, lateSafeArea: Bool = false) throws -> Host {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let vc = UIViewController()
        if !lateSafeArea { vc.additionalSafeAreaInsets = safeArea }
        window.rootViewController = vc
        window.makeKeyAndVisible()
        let harness = RenderHarness(size: CGSize(width: 390, height: 844), inWindow: false)
        harness.superview.frame = vc.view.bounds
        harness.superview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        vc.view.addSubview(harness.superview)
        try harness.render(screenJSON(top: top, bottom: bottom))
        settle(vc)
        if lateSafeArea {
            // The safe area arrives after the first layout, as on a screen
            // whose bars are set up after its content.
            vc.additionalSafeAreaInsets = safeArea
            settle(vc)
        }
        let pager = try XCTUnwrap(collectionViews(in: harness.superview).first)
        return Host(window: window, controller: vc, harness: harness, pager: pager)
    }

    private func settle(_ vc: UIViewController) {
        for _ in 0..<3 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            vc.view.setNeedsLayout()
            vc.view.layoutIfNeeded()
        }
    }

    private func collectionViews(in view: UIView) -> [UICollectionView] {
        if let cv = view as? UICollectionView { return [cv] }
        return view.subviews.flatMap { collectionViews(in: $0) }
    }

    /// Where page `index` rests after a paging scroll: the page's top minus
    /// the pager's visible top, in points (0 = flush).
    private func restOffset(of index: Int, in host: Host) throws -> CGFloat {
        let cv = host.pager
        let frame = cv.bounds.height
        // What the scroll view's own paging (or the engine's snap) rests on.
        var target = CGPoint(x: 0, y: CGFloat(index) * frame)
        if !cv.isPagingEnabled {
            cv.delegate?.scrollViewWillBeginDragging?(cv)
            cv.contentOffset = CGPoint(x: 0, y: CGFloat(index) * frame - frame * 0.4)
            cv.delegate?.scrollViewWillEndDragging?(cv, withVelocity: .zero, targetContentOffset: &target)
        }
        cv.setContentOffset(target, animated: false)
        settle(host.controller)
        let attributes = try XCTUnwrap(cv.layoutAttributesForItem(at: IndexPath(item: index, section: 0)))
        return attributes.frame.minY - (cv.contentOffset.y + cv.adjustedContentInset.top)
    }

    private func check(_ name: String, _ host: Host, file: StaticString = #filePath, line: UInt = #line) throws {
        let cv = host.pager
        let frame = cv.bounds.height
        let page = try XCTUnwrap(cv.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))).frame.height
        var rests: [String] = []
        for index in [1, 2, Self.pages - 1] {
            let offset = try restOffset(of: index, in: host)
            rests.append(String(format: "page %d: %.2f", index + 1, offset))
            XCTAssertEqual(offset, 0, accuracy: 0.5, "\(name): page \(index + 1) rests \(offset) pt off", file: file, line: line)
        }
        let end = cv.contentSize.height - CGFloat(Self.pages) * frame
        print(String(format: "[pager] %@: frame %.1f, page %.1f, adjusted inset top %.1f bottom %.1f, content − pages×frame %.1f; rest offsets %@",
                     name, frame, page, cv.adjustedContentInset.top, cv.adjustedContentInset.bottom, end, rests.joined(separator: ", ")))
        XCTAssertEqual(page, frame, accuracy: 0.5, "\(name): a page is the pager's frame", file: file, line: line)
        XCTAssertEqual(end, 0, accuracy: 0.5, "\(name): the content is pages × frame", file: file, line: line)
    }

    private static let safe = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    private static let underBand = #"{ "type": "top", "target": "sibling(band)", "attribute": "bottom" }"#
    private static let safeTop = #"{ "type": "top", "target": "safeArea" }"#
    private static let screenTop = #"{ "type": "top", "target": "superview" }"#
    private static let screenBottom = #"{ "type": "bottom", "target": "superview" }"#
    private static let safeBottom = #"{ "type": "bottom", "target": "safeArea" }"#

    func testFullScreenPagerRestsFlush() throws {
        try check("full screen", host(top: Self.screenTop, bottom: Self.screenBottom, safeArea: Self.safe))
    }

    func testPagerUnderABandRestsFlush() throws {
        try check("under a band, to the screen's bottom", host(top: Self.underBand, bottom: Self.screenBottom, safeArea: Self.safe))
    }

    func testPagerUnderABandAboveTheBottomSafeAreaRestsFlush() throws {
        try check("under a band, to the safe area's bottom", host(top: Self.underBand, bottom: Self.safeBottom, safeArea: Self.safe))
    }

    func testPagerInTheSafeAreaRestsFlush() throws {
        try check("safe area top to screen bottom", host(top: Self.safeTop, bottom: Self.screenBottom, safeArea: Self.safe))
    }

    func testPagerRestsFlushWhenTheSafeAreaArrivesLate() throws {
        try check("under a band, late safe area", host(top: Self.underBand, bottom: Self.screenBottom, safeArea: Self.safe, lateSafeArea: true))
        try check("safe area to safe area, late safe area", host(top: Self.safeTop, bottom: Self.safeBottom, safeArea: Self.safe, lateSafeArea: true))
    }

    /// The frame changes while page 4 shows (a bar appears): page 4 stays, flush.
    func testThePageShowingStaysWhenTheFrameHeightChanges() throws {
        let host = try host(top: Self.safeTop, bottom: Self.safeBottom, safeArea: Self.safe)
        XCTAssertEqual(try restOffset(of: 3, in: host), 0, accuracy: 0.5)
        host.controller.additionalSafeAreaInsets = UIEdgeInsets(top: 59, left: 0, bottom: 83, right: 0)
        settle(host.controller)
        let cv = host.pager
        let page = try XCTUnwrap(cv.layoutAttributesForItem(at: IndexPath(item: 3, section: 0))).frame
        print(String(format: "[pager] frame change on page 4: frame %.1f, page %.1f, rest offset %.2f", cv.bounds.height, page.height, page.minY - cv.contentOffset.y))
        XCTAssertEqual(page.height, cv.bounds.height, accuracy: 0.5)
        XCTAssertEqual(page.minY - cv.contentOffset.y, 0, accuracy: 0.5)
        try check("after the frame change", host)
    }
}
