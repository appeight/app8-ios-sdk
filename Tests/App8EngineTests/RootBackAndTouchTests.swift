//
//  RootBackAndTouchTests.swift
//  App8EngineTests
//
//  - A `localAsset` image name is an expression (`{{item.image}}` in a cell).
//  - `backLabel` shows a back button only where there is something to go back to.
//  - A child laid out outside an unclipped parent takes taps (as on the web).
//  - An item touch that stops a moving or rubber-banding parent scroll view
//    does not also select the item.
//  - The top edge effect follows the content under the bar (dark or light).
//

import XCTest
import UIKit
@testable import App8Engine

@MainActor
final class RootBackAndTouchTests: XCTestCase {
    private typealias Harness = TopEdgeEffectTests

    /// Wraps the test bundle and records the asset names the engine asks for.
    final class RecordingDataSource: App8DataSource, @unchecked Sendable {
        let base: SearchFillsBarTests.BundleDataSource
        private let lock = NSLock()
        private var names: [String] = []
        var requestedNames: [String] { lock.withLock { names } }

        init(envelope: [String: Any]) throws { base = try SearchFillsBarTests.BundleDataSource(envelope: envelope) }

        func getApp() async throws -> Data { try await base.getApp() }
        func getStyles() async throws -> [Data] { try await base.getStyles() }
        func getComponents() async throws -> [Data] { try await base.getComponents() }
        func getComponent(componentId: String) async throws -> Data { try await base.getComponent(componentId: componentId) }
        func getScreen(screenId: String) async throws -> Data { try await base.getScreen(screenId: screenId) }
        func getDatasource(screenId: String, datasourceId: String) async throws -> Data {
            try await base.getDatasource(screenId: screenId, datasourceId: datasourceId)
        }
        func getAllScreenIds() async throws -> [String]? { try await base.getAllScreenIds() }
        func streamScreen(screenId: String) -> AsyncStream<Data>? { nil }
        func streamDatasource(screenId: String, datasourceId: String, componentPath: String?) -> AsyncStream<Data>? { nil }
        func streamStyles() -> AsyncStream<Data>? { nil }

        private func record(_ name: String) { lock.withLock { names.append(name) } }

        func getAsset(assetId: String?, assetName: String?) async throws -> Data? {
            if let assetName { record(assetName) }
            return UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { ctx in
                UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }.pngData()
        }
    }

    private static func start(_ ds: App8DataSource) async throws -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.makeKeyAndVisible()
        let instance = App8.instance(dataSource: ds)
        window.rootViewController = try await instance.startApp()
        window.layoutIfNeeded()
        for _ in 0..<8 { try await Task.sleep(nanoseconds: 100_000_000) }
        return window
    }

    private static func view(_ id: String, in window: UIWindow) -> UIView? {
        Harness.views(window).first { $0.accessibilityIdentifier == id }
    }

    // MARK: - localAsset name expressions

    func testLocalAssetNameResolvesInCells() async throws {
        let screen = """
        { "type": "screen", "id": "s", "content": {
          "variables": { "pics": { "type": "array", "initialValue": [ { "image": "pic-a" }, { "image": "pic-b" } ] } },
          "children": [
            { "type": "collection", "id": "list", "content": {
                "properties": { "data": "{{pics}}", "layout": { "type": "horizontal", "itemWidth": 120, "itemHeight": 120 } },
                "layout": { "height": 120, "constraints": [
                  { "type": "top", "target": "safeArea" }, { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" } ] },
                "template": { "type": "image", "id": "pic", "content": {
                    "properties": { "type": "localAsset", "name": "{{item.image}}" },
                    "layout": { "constraints": [
                      { "type": "top", "target": "superview" }, { "type": "bottom", "target": "superview" },
                      { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" } ] } } } } }
          ] } }
        """
        let ds = try RecordingDataSource(envelope: try Harness.envelope(screen, id: "s"))
        let window = try await Self.start(ds)
        defer { window.rootViewController = nil }
        let names = Set(ds.requestedNames)
        XCTAssertTrue(names.contains("pic-a"), "\(names)")
        XCTAssertTrue(names.contains("pic-b"), "\(names)")
        XCTAssertFalse(names.contains { $0.contains("{{") }, "unresolved name requested: \(names)")
        let images = Harness.views(window).compactMap { $0 as? UIImageView }.filter { $0.image != nil && $0.bounds.width >= 100 }
        XCTAssertGreaterThanOrEqual(images.count, 2, "cell images drawn")
    }

    // MARK: - backLabel on a stack root

    nonisolated static func labelled(_ id: String, push next: String?) -> String {
        let action = next.map { #""actions": { "tap": [ { "type": "navigation", "nextScreen": "\#($0)", "presentation": "push" } ] },"# } ?? ""
        return """
        { "type": "screen", "id": "\(id)", "content": {
          "navigationBar": { "backLabel": "" },
          "children": [
            { "type": "button", "id": "go-\(id)", "content": {
                "properties": { "text": "Next" }, \(action)
                "layout": { "width": 200, "height": 44, "constraints": [ { "type": "centerX", "target": "superview" }, { "type": "centerY", "target": "superview" } ] } } }
          ] } }
        """
    }

    func testBackLabelOnlyWhereThereIsSomethingToGoBackTo() async throws {
        var env = try Harness.envelope(Self.labelled("root", push: "detail"), id: "root")
        var bundle = env["bundle"] as! [String: Any]
        var screens = bundle["screens"] as! [String: Any]
        screens["detail"] = try JSONSerialization.jsonObject(with: Data(Self.labelled("detail", push: nil).utf8))
        bundle["screens"] = screens
        env["bundle"] = bundle
        let window = try await Self.start(try SearchFillsBarTests.BundleDataSource(envelope: env))
        defer { window.rootViewController = nil }

        let root = try Harness.screen("root", in: window)
        XCTAssertFalse(root.canGoBack)
        XCTAssertNil(root.navigationItem.leftBarButtonItem, "a stack root shows no back button, backLabel or not")

        NotificationCenter.default.post(name: .app8NavigationRequest,
                                        object: NavigationRequest(type: .push(screenId: "detail", params: [:])))
        for _ in 0..<10 { try await Task.sleep(nanoseconds: 100_000_000) }
        let detail = try Harness.screen("detail", in: window)
        XCTAssertTrue(detail.canGoBack)
        XCTAssertNotNil(detail.navigationItem.leftBarButtonItem, "a pushed screen keeps its backLabel button")
    }

    // MARK: - Overflowing children take taps

    func testChildOutsideAZeroHeightParentTakesTaps() async throws {
        // `box` has no height (its content has no bottom constraint): 0 pt high.
        let screen = """
        { "type": "screen", "id": "s", "content": {
          "children": [
            { "type": "view", "id": "box", "content": {
                "layout": { "constraints": [
                  { "type": "top", "target": "safeArea", "constant": 100 },
                  { "type": "leading", "target": "superview" }, { "type": "trailing", "target": "superview" } ] },
                "children": [
                  { "type": "view", "id": "option", "content": {
                      "layout": { "height": 60, "constraints": [
                        { "type": "top", "target": "superview", "constant": 20 },
                        { "type": "leading", "target": "superview", "constant": 16 },
                        { "type": "trailing", "target": "superview", "constant": -16 } ] } } }
                ] } }
          ] } }
        """
        let window = try await Self.start(try SearchFillsBarTests.BundleDataSource(envelope: try Harness.envelope(screen, id: "s")))
        defer { window.rootViewController = nil }
        let box = try XCTUnwrap(Self.view("box", in: window))
        let option = try XCTUnwrap(Self.view("option", in: window))
        XCTAssertEqual(box.bounds.height, 0, accuracy: 0.5, "precondition: the parent has no height")
        let center = option.convert(CGPoint(x: option.bounds.midX, y: option.bounds.midY), to: window)
        let hit = try XCTUnwrap(window.hitTest(center, with: nil))
        XCTAssertTrue(hit.isDescendant(of: option), "hit \(hit), expected inside the option")
    }

    func testClippedParentKeepsItsBounds() {
        let parent = CView(frame: CGRect(x: 0, y: 0, width: 100, height: 0))
        let child = UIView(frame: CGRect(x: 0, y: 10, width: 100, height: 40))
        parent.addSubview(child)
        XCTAssertTrue(parent.hitTest(CGPoint(x: 50, y: 30), with: nil) === child, "unclipped: the child takes it")
        parent.clipsToBounds = true
        XCTAssertNil(parent.hitTest(CGPoint(x: 50, y: 30), with: nil), "clipped: nothing outside the bounds")
    }

    // MARK: - Touches that stop a moving parent

    func testRubberBandingAndDeceleratingParents() {
        let outer = UIScrollView(frame: CGRect(x: 0, y: 0, width: 402, height: 800))
        outer.contentSize = CGSize(width: 402, height: 2000)
        let inner = App8CollectionView(frame: CGRect(x: 0, y: 0, width: 402, height: 300),
                                       collectionViewLayout: UICollectionViewFlowLayout())
        outer.addSubview(inner)
        XCTAssertFalse(App8CollectionView.hasMovingAncestor(inner), "at rest")
        outer.contentOffset = CGPoint(x: 0, y: 400)
        XCTAssertFalse(App8CollectionView.hasMovingAncestor(inner), "scrolled, inside its bounds")
        outer.contentOffset = CGPoint(x: 0, y: -60)
        XCTAssertTrue(App8CollectionView.isRubberBanding(outer), "pulled past the top")
        XCTAssertTrue(App8CollectionView.hasMovingAncestor(inner), "a pull in progress or bouncing back")
        outer.contentOffset = CGPoint(x: 0, y: 2000 - 800 + 40)
        XCTAssertTrue(App8CollectionView.isRubberBanding(outer), "past the end")
    }

    // MARK: - Backdrop sampling

    func testMeanLuminanceReadsThePixels() throws {
        func image(_ color: UIColor) throws -> CGImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 4), format: format).image { ctx in
                color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
            }.cgImage)
        }
        XCTAssertEqual(try XCTUnwrap(BackdropLuminance.meanLuminance(try image(.white))), 1, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(BackdropLuminance.meanLuminance(try image(.black))), 0, accuracy: 0.02)
    }
}
