//
//  Engine0711Tests.swift
//  App8EngineTests
//
//  Spec 0.7.11: edge tab bar, stretchy-top hero, `contentInsetAdjustment:
//  bottom` and the bottom bar inset, context menu preview, zoom from a
//  full-screen source, one-line labels, search-only bars.
//

import XCTest
import UIKit
@testable import App8Engine

@MainActor
final class Engine0711Tests: XCTestCase {

    // MARK: - Decoding

    private func scrollProps(_ json: String) throws -> DSL.Model.Component.ScrollView.Properties {
        try JSONDecoder().decode(DSL.Model.Component.ScrollView.Properties.self, from: Data(json.utf8))
    }

    func testContentInsetAdjustmentDecodesBottomAndUnknownAsAutomatic() throws {
        XCTAssertEqual(try scrollProps(#"{ "contentInsetAdjustment": "bottom" }"#).contentInsetAdjustment, .bottom)
        XCTAssertEqual(try scrollProps(#"{ "contentInsetAdjustment": "never" }"#).contentInsetAdjustment, .never)
        XCTAssertEqual(try scrollProps(#"{ "contentInsetAdjustment": "sideways" }"#).contentInsetAdjustment, .automatic)
        XCTAssertNil(try scrollProps("{}").contentInsetAdjustment)
    }

    private func barStyle(_ json: String) throws -> DSL.Model.TabBarContent.BarStyle {
        try JSONDecoder().decode(DSL.Model.TabBarContent.BarStyle.self, from: Data(json.utf8))
    }

    func testBarStyleShape() throws {
        let edge = try barStyle(#"{ "variant": "text", "shape": "edge", "height": 32 }"#)
        XCTAssertEqual(edge.shape, .edge)
        XCTAssertTrue(edge.isEdge)
        XCTAssertEqual(edge.drawnHeight, 32)
        XCTAssertEqual(try barStyle(#"{ "variant": "text", "shape": "edge", "height": 12 }"#).drawnHeight, 28)
        XCTAssertEqual(try barStyle(#"{ "variant": "text", "shape": "edge" }"#).drawnHeight, 49)
        XCTAssertEqual(try barStyle(#"{ "variant": "text", "shape": "blob" }"#).shape, .floating)
        XCTAssertEqual(try barStyle(#"{ "variant": "text" }"#).shape, .floating)
        // The system items have no stripe of their own.
        XCTAssertFalse(try barStyle(#"{ "shape": "edge" }"#).isEdge)
    }

    func testFlatBarStyleDecodes() throws {
        let flat = try barStyle(##"{ "variant": "text", "background": "#000000", "cornerRadius": 0, "height": 32, "badgePlacement": "inline" }"##)
        XCTAssertTrue(flat.isEngineDrawn)
        XCTAssertFalse(flat.isEdge)
        XCTAssertEqual(flat.drawnHeight, 32)
        XCTAssertEqual(flat.drawnCornerRadius, 0)
        XCTAssertEqual(flat.badgePlacement, .inline)
        XCTAssertEqual(try barStyle(#"{ "variant": "text", "background": "solid", "height": 40 }"#).drawnCornerRadius, 20)
        XCTAssertEqual(try barStyle(#"{ "variant": "text", "background": "solid" }"#).drawnHeight, 62)
        XCTAssertEqual(try barStyle(#"{ "variant": "text", "badgePlacement": "above" }"#).badgePlacement, .corner)
        // Glass stays the system bar.
        XCTAssertFalse(try barStyle(#"{ "variant": "text" }"#).isEngineDrawn)
        XCTAssertEqual(try barStyle(#"{ "variant": "text", "shape": "edge", "cornerRadius": 9 }"#).drawnCornerRadius, 0)
    }

    /// Measured iOS 26.4 platter (iPhone 17, 402 × 874, home indicator 34):
    /// 21 pt sides, bottom 21 pt above the screen edge.
    func testEngineBarFrames() {
        let size = CGSize(width: 402, height: 874)
        typealias T = TabBarScreenViewController
        XCTAssertEqual(T.engineBarFrame(edge: false, height: 62, in: size, safeAreaBottom: 34), CGRect(x: 21, y: 791, width: 360, height: 62))
        XCTAssertEqual(T.engineBarFrame(edge: false, height: 32, in: size, safeAreaBottom: 34), CGRect(x: 21, y: 821, width: 360, height: 32))
        XCTAssertEqual(T.engineBarFrame(edge: false, height: 32, in: size, safeAreaBottom: 0), CGRect(x: 21, y: 834, width: 360, height: 32))
        XCTAssertEqual(T.engineBarFrame(edge: true, height: 32, in: size, safeAreaBottom: 34), CGRect(x: 0, y: 808, width: 402, height: 32))
        // bottomOffset: 10 pt above the bottom safe area; -10 pt into it.
        XCTAssertEqual(T.engineBarFrame(edge: false, height: 40, in: size, safeAreaBottom: 34, bottomOffset: 10), CGRect(x: 21, y: 790, width: 360, height: 40))
        XCTAssertEqual(T.engineBarFrame(edge: false, height: 40, in: size, safeAreaBottom: 34, bottomOffset: -10), CGRect(x: 21, y: 810, width: 360, height: 40))
        XCTAssertEqual(T.engineBarFrame(edge: false, height: 50, in: size, safeAreaBottom: 34, bottomOffset: 10, sideInset: 16), CGRect(x: 16, y: 780, width: 370, height: 50))
        // Safe area to the bar's top: 874 − 821 = 53 = 34 + 19.
        XCTAssertEqual(T.engineBarInset(barFrame: CGRect(x: 21, y: 821, width: 360, height: 32), viewHeight: 874, safeAreaBottom: 34), 19)
        XCTAssertEqual(T.engineBarInset(barFrame: CGRect(x: 0, y: 808, width: 402, height: 32), viewHeight: 874, safeAreaBottom: 34), 32)
    }

    func testInlineBadgeLayout() {
        let layout = StyledTabBarView.inlineBadgeLayout(slotCenterX: 100, midY: 16, labelWidth: 40, badgeSize: CGSize(width: 20, height: 16), shown: true)
        // label 40 + 4 + badge 20 = 64 centred on 100: 68...132.
        XCTAssertEqual(layout.labelShift, -12)            // label centre 100 → 88
        XCTAssertEqual(layout.badge, CGRect(x: 112, y: 8, width: 20, height: 16))
        let hidden = StyledTabBarView.inlineBadgeLayout(slotCenterX: 100, midY: 16, labelWidth: 40, badgeSize: CGSize(width: 20, height: 16), shown: false)
        XCTAssertEqual(hidden.labelShift, 0)
    }

    func testEdgeStripeInset() {
        XCTAssertEqual(TabBarScreenViewController.edgeStripeInset(height: 32, hidesTabBar: false), 32)
        XCTAssertEqual(TabBarScreenViewController.edgeStripeInset(height: 32, hidesTabBar: true), 0)
    }

    func testPreviewCornerRadiusDecodes() throws {
        let json = #"{ "preview": { "component": { "templateId": "QuickView" }, "width": 300, "cornerRadius": 0 }, "items": [] }"#
        let menu = try JSONDecoder().decode(DSL.Model.ContextMenu.self, from: Data(json.utf8))
        XCTAssertEqual(menu.preview?.cornerRadius, 0)
        let none = try JSONDecoder().decode(DSL.Model.ContextMenu.self, from: Data(#"{ "preview": { "component": { "templateId": "Q" } } }"#.utf8))
        XCTAssertNil(none.preview?.cornerRadius)
    }

    // MARK: - Bottom inset

    func testBottomContentInset() {
        typealias S = App8ZoomingScrollView
        XCTAssertEqual(S.bottomContentInset(mode: .automatic, authored: 10, safeAreaBottom: 84, underBottomBar: true), 10)
        XCTAssertEqual(S.bottomContentInset(mode: .bottom, authored: 10, safeAreaBottom: 84, underBottomBar: false), 94)
        XCTAssertEqual(S.bottomContentInset(mode: .never, authored: 10, safeAreaBottom: 84, underBottomBar: false), 10)
        XCTAssertEqual(S.bottomContentInset(mode: .never, authored: 0, safeAreaBottom: 100, underBottomBar: true), 100)
    }

    /// `never` + a bottom bar: the safe area the bar adds reaches the main
    /// scroll view's bottom inset (product screens with a buy bar).
    func testNeverScrollUnderBottomBarGetsTheSafeArea() throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 844))
        try harness.render(#"""
        { "type": "scrollView", "id": "s", "content": {
            "properties": { "contentInsetAdjustment": "never", "contentInset": { "bottom": 8 } },
            "layout": { "constraints": [ { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
                                         { "type": "trailing", "target": "superview" }, { "type": "bottom", "target": "superview" } ] },
            "children": [ { "type": "view", "id": "tall", "content": { "layout": { "height": 2000, "constraints": [
                { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" },
                { "type": "trailing", "target": "superview" }, { "type": "bottom", "target": "superview" } ] } } } ] } }
        """#)
        let scroll = try XCTUnwrap(harness.find(App8ZoomingScrollView.self))
        XCTAssertEqual(scroll.contentInset.bottom, 8)
        XCTAssertEqual(scroll.contentInsetAdjustmentBehavior, .never)
        scroll.isUnderBottomBar = true
        XCTAssertEqual(scroll.contentInset.bottom, 8 + scroll.safeAreaInsets.bottom)
        scroll.isUnderBottomBar = false
        XCTAssertEqual(scroll.contentInset.bottom, 8)
    }

    // MARK: - Stretchy top

    func testStretchTransformKeepsTopOnTheEdgeAndBottomInPlace() {
        let h: CGFloat = 600, d: CGFloat = 120
        let view = UIView(frame: CGRect(x: 0, y: d, width: 400, height: h))
        view.transform = CScrollViewView.stretchTransform(height: h, pull: d)
        XCTAssertEqual(view.frame.minY, 0, accuracy: 0.01)          // top on the scroll view's top edge
        XCTAssertEqual(view.frame.maxY, d + h, accuracy: 0.01)      // bottom stays
        XCTAssertEqual(view.frame.width, 400 * (h + d) / h, accuracy: 0.01) // uniform: grows sideways
        XCTAssertEqual(view.frame.midX, 200, accuracy: 0.01)
        XCTAssertEqual(CScrollViewView.stretchTransform(height: h, pull: 0), .identity)
    }

    private static let edges = #"[ { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" }, { "type": "bottom", "target": "superview" } ]"#

    private func renderStretchy(_ firstChild: String) throws -> (RenderHarness, UIView) {
        let harness = RenderHarness(size: CGSize(width: 390, height: 844))
        try harness.render(#"""
        { "type": "scrollView", "id": "s", "content": {
            "properties": { "stretchesTopChild": true, "contentInsetAdjustment": "never" },
            "layout": { "constraints": \#(Self.edges) },
            "children": [ \#(firstChild) ] } }
        """#)
        harness.drain()
        harness.superview.layoutIfNeeded()
        let scroll = try XCTUnwrap(harness.find(App8ZoomingScrollView.self))
        let content = try XCTUnwrap(scroll.subviews.first { $0.subviews.contains { $0.accessibilityIdentifier != nil } })
        let first = try XCTUnwrap(content.subviews.first { $0.accessibilityIdentifier != nil })
        return (harness, first)
    }

    /// `scrollView > stackView > heroBox (height = width × 1.5) > pager`: the hero
    /// is the box, not the stack (which moved with the pull before).
    func testHeroIsTheStacksFirstBoxWithARelativeHeight() throws {
        let (_, first) = try renderStretchy(#"""
        { "type": "stackView", "id": "stack", "content": {
            "properties": { "axis": "vertical", "spacing": 0, "alignment": "fill" },
            "layout": { "constraints": \#(Self.edges) },
            "children": [
              { "type": "view", "id": "heroBox", "content": {
                  "layout": { "constraints": [ { "type": "height", "target": "superview", "attribute": "width", "multiplier": 1.5 } ] },
                  "children": [ { "type": "view", "id": "pagerStandIn", "content": { "layout": { "constraints": \#(Self.edges) } } } ] } },
              { "type": "view", "id": "below", "content": { "layout": { "height": 900 } } } ] } }
        """#)
        XCTAssertEqual(first.accessibilityIdentifier, "stack")
        XCTAssertEqual(CScrollViewView.stretchHero(from: first).accessibilityIdentifier, "heroBox")
    }

    /// A stack whose first child has a fixed height (a 400 pt video head).
    func testHeroIsAFixedHeightHead() throws {
        let (_, first) = try renderStretchy(#"""
        { "type": "stackView", "id": "stack", "content": {
            "properties": { "axis": "vertical", "spacing": 0, "alignment": "fill" },
            "layout": { "constraints": \#(Self.edges) },
            "children": [
              { "type": "view", "id": "head", "content": { "layout": { "height": 400 },
                  "children": [ { "type": "view", "id": "media", "content": { "layout": { "constraints": \#(Self.edges) } } } ] } },
              { "type": "view", "id": "below", "content": { "layout": { "height": 900 } } } ] } }
        """#)
        XCTAssertEqual(CScrollViewView.stretchHero(from: first).accessibilityIdentifier, "head")
    }

    /// A content wrapper `view` (no height of its own) around the stack.
    func testHeroDescendsThroughAWrapperView() throws {
        let (_, first) = try renderStretchy(#"""
        { "type": "view", "id": "wrapper", "content": {
            "layout": { "constraints": \#(Self.edges) },
            "children": [ { "type": "stackView", "id": "stack", "content": {
                "properties": { "axis": "vertical", "spacing": 0, "alignment": "fill" },
                "layout": { "constraints": \#(Self.edges) },
                "children": [
                  { "type": "view", "id": "cover", "content": { "layout": { "height": 300 } } },
                  { "type": "view", "id": "below", "content": { "layout": { "height": 900 } } } ] } } ] } }
        """#)
        XCTAssertEqual(CScrollViewView.stretchHero(from: first).accessibilityIdentifier, "cover")
    }

    /// The first child itself when it is not a container (an image with a height).
    func testHeroIsAPlainFirstChild() throws {
        let (_, first) = try renderStretchy(#"""
        { "type": "view", "id": "cover", "content": { "layout": { "height": 300, "constraints": [
            { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" } ] } } }
        """#)
        XCTAssertEqual(CScrollViewView.stretchHero(from: first).accessibilityIdentifier, "cover")
    }

    // MARK: - Context menu preview

    func testPreviewHeightIsTheContentHeightCapped() {
        XCTAssertEqual(ContextMenuPreviewController.previewHeight(content: 431.2, width: 300, maxHeight: 600), 432)
        XCTAssertEqual(ContextMenuPreviewController.previewHeight(content: 900, width: 300, maxHeight: 600), 600)
        XCTAssertEqual(ContextMenuPreviewController.previewHeight(content: 0, width: 300, maxHeight: 600), 300)
    }

    func testPreviewPathIsSquareForZero() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 120)
        XCTAssertEqual(ContextMenuBinder.previewPath(in: rect, cornerRadius: 0).bounds, rect)
        XCTAssertFalse(ContextMenuBinder.previewPath(in: rect, cornerRadius: 0).contains(CGPoint(x: -0.5, y: 0)))
        // A rounded path leaves the very corner out.
        XCTAssertFalse(ContextMenuBinder.previewPath(in: rect, cornerRadius: 20).contains(CGPoint(x: 0.5, y: 0.5)))
        XCTAssertTrue(ContextMenuBinder.previewPath(in: rect, cornerRadius: 0).contains(CGPoint(x: 0.5, y: 0.5)))
    }

    /// Photo (height = width × 1.25), then a stack 12 pt below it pinned 16 pt
    /// above the root's bottom: the preview is exactly that tall, no gaps.
    func testPreviewFitsAQuickViewWithoutGaps() throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 844))
        let template = #"""
        { "type": "view", "id": "QuickView", "content": {
            "children": [
              { "type": "view", "id": "qvImage", "content": { "layout": { "constraints": [
                  { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" },
                  { "type": "height", "target": "superview", "attribute": "width", "multiplier": 1.25 } ] } } },
              { "type": "stackView", "id": "qvText", "content": {
                  "properties": { "axis": "vertical", "spacing": 6, "alignment": "fill" },
                  "layout": { "constraints": [
                    { "type": "top", "target": "qvImage", "attribute": "bottom", "constant": 12 },
                    { "type": "leading", "target": "superview", "constant": 16 }, { "type": "trailing", "target": "superview", "constant": -16 },
                    { "type": "bottom", "target": "superview", "constant": -16 } ] },
                  "children": [
                    { "type": "label", "id": "qvTitle", "content": { "properties": { "text": "A TITLE" }, "style": { "text": { "fontSize": 13 } } } },
                    { "type": "view", "id": "qvPrice", "content": { "layout": { "height": 20 } } } ] } } ] } }
        """#
        let menuJSON = #"{ "preview": { "component": \#(template), "width": 300 }, "items": [] }"#
        let menu = try JSONDecoder().decode(DSL.Model.ContextMenu.self, from: Data(menuJSON.utf8))
        try harness.render(#"{ "type": "view", "id": "host", "content": { "layout": { "width": 100, "height": 100 } } }"#)
        let host = try XCTUnwrap(harness.viewModel("host", as: CViewModel.self))
        let preview = try XCTUnwrap(menu.preview)
        let controller = ContextMenuPreviewController(preview: preview, viewModel: host, hostView: harness.superview)
        harness.drain()
        controller.prepareForPresentation()
        let title = UIFont.systemFont(ofSize: 13).lineHeight
        let expected = 300 * 1.25 + 12 + ceil(title) + 6 + 20 + 16
        XCTAssertEqual(controller.preferredContentSize.width, 300)
        XCTAssertEqual(controller.preferredContentSize.height, expected, accuracy: 3)
    }

    // MARK: - Zoom from a full-screen source

    func testPoseCoversTheSourceWithTheAlignmentElement() {
        let screen = CGSize(width: 402, height: 874)
        let center = CGPoint(x: 201, y: 437)
        let source = CGRect(origin: .zero, size: screen)                  // a full-screen pager page
        let alignment = CGRect(x: 0, y: 0, width: 402, height: 603)       // gallery at the top (w × 1.5)
        let pose = ZoomMorphTransition.pose(source: source, alignment: alignment, bounds: screen, center: center)
        XCTAssertEqual(pose.a, pose.d)                                    // uniform
        XCTAssertEqual(pose.a, 874.0 / 603.0, accuracy: 0.001)            // cover
        // The alignment element maps onto the source's height, centred on it.
        let parent = UIView(frame: CGRect(origin: .zero, size: screen))
        let view = UIView(frame: CGRect(origin: .zero, size: screen))
        parent.addSubview(view)
        view.transform = pose
        let mapped = view.convert(alignment, to: parent)
        XCTAssertEqual(mapped.minY, 0, accuracy: 0.5)
        XCTAssertEqual(mapped.maxY, 874, accuracy: 0.5)
        XCTAssertEqual(mapped.midX, 201, accuracy: 0.5)
        // The clip in the screen's own coordinates maps back onto the source.
        let local = ZoomMorphTransition.localRect(source, pose: pose, bounds: screen, center: center)
        XCTAssertEqual(view.convert(local, to: parent).minX, 0, accuracy: 0.5)
        XCTAssertEqual(view.convert(local, to: parent).maxY, 874, accuracy: 0.5)
        XCTAssertTrue(alignment.insetBy(dx: -0.5, dy: -0.5).contains(local))
    }

    func testPoseIsIdentityWhenAlignmentIsTheSource() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 800)
        let pose = ZoomMorphTransition.pose(source: rect, alignment: rect, bounds: rect.size, center: CGPoint(x: 200, y: 400))
        XCTAssertEqual(pose.a, 1, accuracy: 0.0001)
        XCTAssertEqual(pose.tx, 0, accuracy: 0.0001)
        XCTAssertEqual(pose.ty, 0, accuracy: 0.0001)
    }

    func testInteractiveProgress() {
        let size = CGSize(width: 400, height: 800)
        typealias I = ZoomMorphInteraction
        XCTAssertEqual(I.progress(translation: CGPoint(x: 100, y: 0), size: size, edgeSwipe: true, downOnly: false, rtl: false), 0.25)
        XCTAssertEqual(I.progress(translation: CGPoint(x: -100, y: 0), size: size, edgeSwipe: true, downOnly: false, rtl: false), 0)
        XCTAssertEqual(I.progress(translation: CGPoint(x: 0, y: 240), size: size, edgeSwipe: false, downOnly: true, rtl: false), 0.5)
        XCTAssertEqual(I.progress(translation: CGPoint(x: 0, y: -240), size: size, edgeSwipe: false, downOnly: true, rtl: false), 0)
        XCTAssertEqual(I.progress(translation: CGPoint(x: -200, y: 0), size: size, edgeSwipe: false, downOnly: false, rtl: false), 0.5)
    }

    func testInteractiveDismissFinishesPastAQuarterOrOnAFling() {
        XCTAssertTrue(ZoomMorphInteraction.finishes(progress: 0.3, fling: 0))
        XCTAssertTrue(ZoomMorphInteraction.finishes(progress: 0.05, fling: 1200))
        XCTAssertFalse(ZoomMorphInteraction.finishes(progress: 0.1, fling: 100))
    }

    // MARK: - Context menu destination built ahead

    func testPreparedPushIsTakenOnlyForTheSameScreenAndParams() {
        let context = App8Context()
        let screen = UIViewController()
        context.preparedPush = ("product", ["product": ["id": "p1"]], screen)
        XCTAssertNil(context.takePreparedPush(screenId: "product", params: ["product": ["id": "p2"]]))
        XCTAssertNil(context.takePreparedPush(screenId: "cart", params: ["product": ["id": "p1"]]))
        XCTAssertTrue(context.takePreparedPush(screenId: "product", params: ["product": ["id": "p1"]]) === screen)
        XCTAssertNil(context.preparedPush, "taken once")
    }

    // MARK: - Search-only bar

    func testSearchOnlyBarSitsInTheBarOnIOS26() {
        let stacked = ScreenViewController.searchLayout(placement: .stacked, fillsBar: nil, hasTitle: false, iOS26: true)
        XCTAssertEqual(stacked.placement, .integrated)
        XCTAssertTrue(stacked.fillsBar)
        let automatic = ScreenViewController.searchLayout(placement: nil, fillsBar: nil, hasTitle: false, iOS26: true)
        XCTAssertEqual(automatic.placement, .integrated)
        XCTAssertTrue(automatic.fillsBar)
        // With a title, or before iOS 26, the authored placement holds.
        XCTAssertEqual(ScreenViewController.searchLayout(placement: .stacked, fillsBar: nil, hasTitle: true, iOS26: true).placement, .stacked)
        XCTAssertEqual(ScreenViewController.searchLayout(placement: .stacked, fillsBar: nil, hasTitle: false, iOS26: false).placement, .stacked)
        let inline = ScreenViewController.searchLayout(placement: .inline, fillsBar: nil, hasTitle: false, iOS26: true)
        XCTAssertEqual(inline.placement, .inline)
        XCTAssertFalse(inline.fillsBar)
    }

    // MARK: - One-line labels

    /// A trailing-pinned total whose text grows never wraps, multi-line or not.
    private func renderTotal(numberOfLines: String) throws -> (RenderHarness, UILabel) {
        let harness = RenderHarness(size: CGSize(width: 390, height: 844))
        try harness.render(#"""
        { "type": "view", "id": "bar", "content": {
            "variables": { "total": { "type": "string", "initialValue": "9 EUR" } },
            "layout": { "height": 50, "constraints": [ { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" }, { "type": "top", "target": "superview" } ] },
            "children": [
              { "type": "label", "id": "checkout", "content": { "properties": { "text": "CHECK OUT" }, "style": { "text": { "fontSize": 13, "letterSpacing": 0.1 } },
                "layout": { "constraints": [ { "type": "leading", "target": "superview", "constant": 14 }, { "type": "centerY", "target": "superview" } ] } } },
              { "type": "label", "id": "total", "content": { "properties": { "text": "{{total}}"\#(numberOfLines) }, "style": { "text": { "fontSize": 13, "letterSpacing": 0.1 } },
                "layout": { "constraints": [ { "type": "trailing", "target": "superview", "constant": -14 }, { "type": "centerY", "target": "superview" } ] } } } ] } }
        """#)
        harness.drain()
        harness.superview.layoutIfNeeded()
        let labels = allLabels(in: harness.superview)
        let total = try XCTUnwrap(labels.first { $0.text == "9 EUR" || $0.attributedText?.string == "9 EUR" })
        return (harness, total)
    }

    private func allLabels(in view: UIView) -> [UILabel] {
        (view as? UILabel).map { [$0] } ?? view.subviews.flatMap(allLabels(in:))
    }

    private func assertGrowsOnOneLine(numberOfLines: String) throws {
        let (harness, label) = try renderTotal(numberOfLines: numberOfLines)
        let vm = try XCTUnwrap(harness.viewModel("bar", as: CViewModel.self))
        let oneLine = ceil(UIFont.systemFont(ofSize: 13).lineHeight)
        for value in ["129 EUR", "1,249.90 EUR", "12,349.90 EUR"] {
            try vm.variableStore.setValue(name: "total", value: value)
            harness.drain()
            harness.superview.layoutIfNeeded()
            harness.superview.layoutIfNeeded()
            XCTAssertLessThanOrEqual(label.bounds.height, oneLine + 1, "'\(value)' wrapped (\(numberOfLines))")
            let needed = ceil((label.attributedText ?? NSAttributedString(string: label.text ?? "")).size().width)
            XCTAssertGreaterThanOrEqual(label.bounds.width + 1, needed, "'\(value)' cut")
        }
    }

    func testOneLineTotalNeverWraps() throws {
        try assertGrowsOnOneLine(numberOfLines: #", "numberOfLines": 1"#)
    }

    func testHuggingMultiLineTotalGrowsOnOneLine() throws {
        try assertGrowsOnOneLine(numberOfLines: #", "numberOfLines": 0"#)
    }
}
