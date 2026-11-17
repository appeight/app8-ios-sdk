//
//  NewComponentRenderTests.swift
//  App8Engine
//

import XCTest
import UIKit
import AVFoundation
@testable import App8Engine

@MainActor
final class NewComponentRenderTests: XCTestCase {

    private var service: App8Service!
    private var window: UIWindow!
    private let renderSize = CGSize(width: 390, height: 844)

    override func setUp() {
        super.setUp()
        service = App8Service(publicDataSource: StubDataSource(), context: App8Context())
        window = UIWindow(frame: CGRect(origin: .zero, size: renderSize))
        window.makeKeyAndVisible()
    }

    override func tearDown() {
        window = nil
        service = nil
        super.tearDown()
    }

    private func render(_ json: String) throws -> UIView {
        let data = json.data(using: .utf8)!
        let component = try JSONDecoder().decode(DSL.Model.Component.Any.self, from: data)

        let superview = UIView(frame: CGRect(origin: .zero, size: renderSize))
        superview.backgroundColor = .black
        window.addSubview(superview)

        service.renderComponent(component, superview: superview)
        superview.layoutIfNeeded()
        return superview
    }

    private func findView<T: UIView>(ofType type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        for sub in view.subviews {
            if let found = findView(ofType: type, in: sub) { return found }
        }
        return nil
    }

    // MARK: - ActivityIndicator

    func testActivityIndicatorRendersSpinner() throws {
        let json = """
        {
            "type": "activityIndicator", "id": "test-spinner",
            "content": {
                "properties": { "isAnimating": "true" },
                "style": { "indicatorStyle": "large" },
                "layout": { "width": 40, "height": 40 }
            }
        }
        """
        let superview = try render(json)
        let indicatorView = findView(ofType: CActivityIndicatorView.self, in: superview)
        XCTAssertNotNil(indicatorView, "CActivityIndicatorView should be rendered")

        let spinner = findView(ofType: UIActivityIndicatorView.self, in: superview)
        XCTAssertNotNil(spinner, "UIActivityIndicatorView should be in hierarchy")
        XCTAssertTrue(spinner?.isAnimating ?? false, "Spinner should be animating")
    }

    func testActivityIndicatorStoppedWhenFalse() throws {
        let json = """
        {
            "type": "activityIndicator", "id": "test-spinner",
            "content": {
                "properties": { "isAnimating": "false", "hidesWhenStopped": false },
                "layout": { "width": 40, "height": 40 }
            }
        }
        """
        let superview = try render(json)
        let spinner = findView(ofType: UIActivityIndicatorView.self, in: superview)
        XCTAssertNotNil(spinner)
        XCTAssertFalse(spinner?.isAnimating ?? true, "Spinner should not be animating")
    }

    // MARK: - Toggle

    func testToggleRendersSwitch() throws {
        let json = """
        {
            "type": "toggle", "id": "test-toggle",
            "content": {
                "properties": { "isOn": "true" },
                "layout": { "width": 51, "height": 31 }
            }
        }
        """
        let superview = try render(json)
        let toggleView = findView(ofType: CToggleView.self, in: superview)
        XCTAssertNotNil(toggleView, "CToggleView should be rendered")

        let uiSwitch = findView(ofType: UISwitch.self, in: superview)
        XCTAssertNotNil(uiSwitch, "UISwitch should be in hierarchy")
    }

    func testToggleRendersWithStyle() throws {
        let json = """
        {
            "type": "toggle", "id": "test-toggle",
            "content": {
                "properties": { "isOn": "false" },
                "style": { "onTintColor": "#FF0000" },
                "layout": { "width": 51, "height": 31 }
            }
        }
        """
        let superview = try render(json)
        let toggleView = findView(ofType: CToggleView.self, in: superview)
        XCTAssertNotNil(toggleView, "CToggleView should be rendered with style")

        let uiSwitch = findView(ofType: UISwitch.self, in: superview)
        XCTAssertNotNil(uiSwitch, "UISwitch should exist")
        XCTAssertFalse(uiSwitch?.isOn ?? true, "Switch should be off")
    }

    // MARK: - Slider

    func testSliderRendersUISlider() throws {
        let json = """
        {
            "type": "slider", "id": "test-slider",
            "content": {
                "properties": { "minimumValue": 0, "maximumValue": 100 },
                "layout": { "width": 200, "height": 31 }
            }
        }
        """
        let superview = try render(json)
        let sliderView = findView(ofType: CSliderView.self, in: superview)
        XCTAssertNotNil(sliderView, "CSliderView should be rendered")

        let uiSlider = findView(ofType: UISlider.self, in: superview)
        XCTAssertNotNil(uiSlider, "UISlider should be in hierarchy")
        XCTAssertEqual(uiSlider?.minimumValue, 0)
        XCTAssertEqual(uiSlider?.maximumValue, 100)
    }

    // MARK: - First render

    /// A component shows its text, style and content in the pass that builds
    /// it, without waiting for the main queue: a screen pushed right after it
    /// is built (zoom transition) must not show a frame with layout only.
    func testFirstRenderAppliesTextAndStyleWithoutMainQueueHop() throws {
        let json = """
        {
            "type": "view", "id": "root",
            "content": {
                "style": { "material": [ { "id": "bg", "type": "fill", "content": { "solid": "#FF0000" } } ] },
                "layout": { "width": 300, "height": 200 },
                "children": [
                    { "type": "label", "id": "title",
                      "content": { "properties": { "text": "Sample" }, "style": { "text": { "fontSize": 17, "color": "#00FF00" } },
                                   "layout": { "constraints": [ { "type": "top", "target": "superview" }, { "type": "leading", "target": "superview" } ] } } },
                    { "type": "icon", "id": "star",
                      "content": { "properties": { "type": "symbol", "name": "star.fill" }, "style": { "color": "#0000FF" },
                                   "layout": { "constraints": [ { "type": "bottom", "target": "superview" }, { "type": "leading", "target": "superview" } ] } } }
                ]
            }
        }
        """
        let superview = try render(json)
        let labels = allViews(ofType: UILabel.self, in: superview)
        let title = try XCTUnwrap(labels.first { $0.text == "Sample" || $0.attributedText?.string == "Sample" }, "label text set during the build")
        XCTAssertEqual(title.textColor?.hexComponents, UIColor(red: 0, green: 1, blue: 0, alpha: 1).hexComponents)
        let icon = try XCTUnwrap(findView(ofType: CIconView.self, in: superview))
        let imageView = try XCTUnwrap(allViews(ofType: UIImageView.self, in: icon).first)
        XCTAssertEqual(imageView.tintColor?.hexComponents, UIColor(red: 0, green: 0, blue: 1, alpha: 1).hexComponents, "icon tint from the style, not the inherited system blue")
        let root = try XCTUnwrap(findView(ofType: CView.self, in: superview))
        XCTAssertFalse(allViews(ofType: MaterialView.self, in: root).isEmpty, "background fill applied during the build")
    }

    private func allViews<T: UIView>(ofType type: T.Type, in view: UIView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { allViews(ofType: type, in: $0) }
    }

    // MARK: - PageControl

    func testPageControlRendersMediaCapsule() throws {
        let json = """
        {
            "type": "pageControl", "id": "test-dots",
            "content": {
                "properties": { "numberOfPages": "5", "currentPage": "2" },
                "layout": { "width": 200, "height": 30 }
            }
        }
        """
        let superview = try render(json)
        let pageView = findView(ofType: CPageControlView.self, in: superview)
        XCTAssertNotNil(pageView, "CPageControlView should be rendered")

        let control = try XCTUnwrap(findView(ofType: MediaPageControl.self, in: superview))
        XCTAssertEqual(control.numberOfPages, 5)
        XCTAssertEqual(control.currentPage, 2)
        // Capsule sized like the web renderer: pages * 16 + 10 by 26.
        XCTAssertEqual(control.intrinsicContentSize, CGSize(width: 90, height: 26))
        XCTAssertNotNil(findView(ofType: UIVisualEffectView.self, in: control), "blurred capsule behind the dots")

        // Without DSL tints the dots are white: current opaque, others at 50 %
        // (with tints they take the DSL colors, as on the web renderer).
        control.frame = CGRect(origin: .zero, size: control.intrinsicContentSize)
        control.layoutIfNeeded()
        let dots = (control.layer.sublayers ?? []).filter { $0.bounds.width == MediaPageControl.dotSize }
        XCTAssertEqual(dots.count, 5)
        let alphas = dots.compactMap { $0.backgroundColor.map { UIColor(cgColor: $0) } }.map { color -> CGFloat in
            var white: CGFloat = 0, alpha: CGFloat = 0
            color.getWhite(&white, alpha: &alpha)
            XCTAssertEqual(white, 1, accuracy: 0.01)
            return alpha
        }
        XCTAssertEqual(alphas.map { ($0 * 10).rounded() / 10 }, [0.5, 0.5, 1, 0.5, 0.5])
        // 7 pt dots, 9 pt apart, centred.
        XCTAssertEqual(dots[1].frame.minX - dots[0].frame.maxX, 9, accuracy: 0.01)
        XCTAssertEqual(dots[0].frame.minX, control.bounds.width - dots[4].frame.maxX, accuracy: 0.01)
    }

    // MARK: - Picker (Menu)

    func testPickerMenuRendersButton() throws {
        let json = """
        {
            "type": "picker", "id": "test-picker",
            "content": {
                "properties": {
                    "options": [{ "value": "a", "label": "Alpha" }, { "value": "b", "label": "Beta" }],
                    "displayMode": "menu",
                    "placeholder": "Pick one"
                },
                "layout": { "width": 200, "height": 44 }
            }
        }
        """
        let superview = try render(json)
        let pickerView = findView(ofType: CPickerView.self, in: superview)
        XCTAssertNotNil(pickerView, "CPickerView should be rendered")

        let button = findView(ofType: UIButton.self, in: superview)
        XCTAssertNotNil(button, "UIButton should be in hierarchy for menu mode")
        XCTAssertNotNil(button?.menu, "Button should have a UIMenu")
        XCTAssertEqual(button?.menu?.children.count, 2, "Menu should have 2 options")
    }

    // MARK: - Picker (Segmented)

    func testPickerSegmentedRendersSegmentedControl() throws {
        let json = """
        {
            "type": "picker", "id": "test-seg",
            "content": {
                "properties": {
                    "options": [{ "value": "s", "label": "S" }, { "value": "m", "label": "M" }, { "value": "l", "label": "L" }],
                    "displayMode": "segmented",
                    "selectedValue": "m"
                },
                "layout": { "width": 200, "height": 32 }
            }
        }
        """
        let superview = try render(json)
        let sc = findView(ofType: UISegmentedControl.self, in: superview)
        XCTAssertNotNil(sc, "UISegmentedControl should be in hierarchy")
        XCTAssertEqual(sc?.numberOfSegments, 3)
        XCTAssertEqual(sc?.selectedSegmentIndex, 1, "Middle segment 'M' should be selected")
    }

    // MARK: - Shimmer

    func testShimmerRendersChildren() throws {
        let json = """
        {
            "type": "shimmer", "id": "test-shimmer",
            "content": {
                "properties": { "isAnimating": "true" },
                "layout": { "width": 300, "height": 100 },
                "children": [
                    {
                        "id": "child1", "type": "view",
                        "content": {
                            "properties": {},
                            "layout": { "width": 100, "height": 20, "constraints": [{ "type": "leading", "target": "superview" }, { "type": "top", "target": "superview" }] }
                        }
                    }
                ]
            }
        }
        """
        let superview = try render(json)
        let shimmerView = findView(ofType: CShimmerView.self, in: superview)
        XCTAssertNotNil(shimmerView, "CShimmerView should be rendered")

        let childView = superview.subviews.first?.firstDescendant(ofType: CView.self)
        XCTAssertNotNil(childView, "Child CView should be rendered inside shimmer")
    }

    // MARK: - Shape Polyline

    func testShapePolylineRendersPath() throws {
        let json = """
        {
            "type": "shape", "id": "test-polyline",
            "content": {
                "properties": {
                    "kind": "polyline",
                    "lineWidth": 2,
                    "strokeColor": "#34C759",
                    "points": [
                        { "x": "0", "y": "0.8" },
                        { "x": "0.5", "y": "0.3" },
                        { "x": "1.0", "y": "0.5" }
                    ]
                },
                "layout": { "width": 200, "height": 60 }
            }
        }
        """
        let superview = try render(json)
        let shapeView = findView(ofType: CShapeView.self, in: superview)
        XCTAssertNotNil(shapeView, "CShapeView should be rendered for polyline")
    }

    // MARK: - DatePicker

    // MARK: - Video

    func testVideoRendersPlayerLayer() throws {
        let json = """
        {
            "type": "video", "id": "test-video",
            "content": {
                "properties": { "type": "localAsset", "name": "intro", "loop": true, "muted": true },
                "style": { "contentMode": "scaleAspectFill", "corner": { "radius": 16, "curve": "continuous" } },
                "layout": { "width": 300, "height": 200 }
            }
        }
        """
        let superview = try render(json)
        let videoView = findView(ofType: CVideoView.self, in: superview)
        XCTAssertNotNil(videoView, "CVideoView should be rendered")

        // The player is hosted on an AVPlayerLayer-backed view, with gravity from style.
        let playerLayer = findPlayerLayer(in: superview)
        XCTAssertNotNil(playerLayer, "An AVPlayerLayer should be in the hierarchy")
        XCTAssertEqual(playerLayer?.videoGravity, .resizeAspectFill)
    }

    func testVideoAspectFitMapsGravity() throws {
        let json = """
        {
            "type": "video", "id": "test-video-fit",
            "content": {
                "properties": { "type": "localAsset", "name": "intro" },
                "style": { "contentMode": "scaleAspectFit" },
                "layout": { "width": 300, "height": 200 }
            }
        }
        """
        let superview = try render(json)
        let playerLayer = findPlayerLayer(in: superview)
        XCTAssertEqual(playerLayer?.videoGravity, .resizeAspect)
    }

    private func findPlayerLayer(in view: UIView) -> AVPlayerLayer? {
        if let layer = view.layer as? AVPlayerLayer { return layer }
        for sub in view.subviews {
            if let found = findPlayerLayer(in: sub) { return found }
        }
        return nil
    }

    func testDatePickerCompactRendersUIDatePicker() throws {
        let json = """
        {
            "type": "datePicker", "id": "test-date-compact",
            "content": {
                "properties": { "displayStyle": "compact", "datePickerMode": "date" },
                "layout": { "width": 200, "height": 40 }
            }
        }
        """
        let superview = try render(json)
        let datePickerView = findView(ofType: CDatePickerView.self, in: superview)
        XCTAssertNotNil(datePickerView, "CDatePickerView should be rendered")

        let uiDatePicker = findView(ofType: UIDatePicker.self, in: superview)
        XCTAssertNotNil(uiDatePicker, "UIDatePicker should be in hierarchy")
        XCTAssertEqual(uiDatePicker?.datePickerMode, .date)
        XCTAssertEqual(uiDatePicker?.preferredDatePickerStyle, .compact)
    }

    func testDatePickerInlineRendersFullCalendar() throws {
        let json = """
        {
            "type": "datePicker", "id": "test-date-inline",
            "content": {
                "properties": { "displayStyle": "inline", "datePickerMode": "date" },
                "layout": { "width": 350, "height": 350 }
            }
        }
        """
        let superview = try render(json)
        let uiDatePicker = findView(ofType: UIDatePicker.self, in: superview)
        XCTAssertNotNil(uiDatePicker)
        XCTAssertEqual(uiDatePicker?.preferredDatePickerStyle, .inline)
    }

    func testDatePickerWheelsMode() throws {
        let json = """
        {
            "type": "datePicker", "id": "test-date-wheels",
            "content": {
                "properties": { "displayStyle": "wheels", "datePickerMode": "dateAndTime" },
                "layout": { "width": 350, "height": 200 }
            }
        }
        """
        let superview = try render(json)
        let uiDatePicker = findView(ofType: UIDatePicker.self, in: superview)
        XCTAssertNotNil(uiDatePicker)
        XCTAssertEqual(uiDatePicker?.datePickerMode, .dateAndTime)
        XCTAssertEqual(uiDatePicker?.preferredDatePickerStyle, .wheels)
    }
}

// MARK: - Stub

private final class StubDataSource: App8DataSource, @unchecked Sendable {
    func getApp() async throws -> Data { Data() }
    func getStyles() async throws -> [Data] { [] }
    func getComponents() async throws -> [Data] { [] }
    func getComponent(componentId: String) async throws -> Data { Data() }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getScreen(screenId: String) async throws -> Data { Data() }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data { Data() }
}

private extension UIView {
    func firstDescendant<T: UIView>(ofType type: T.Type) -> T? {
        if let match = self as? T { return match }
        for sub in subviews {
            if let found = sub.firstDescendant(ofType: type) { return found }
        }
        return nil
    }
}

private extension UIColor {
    /// RGBA rounded to 2 decimals, for comparing colors across color spaces.
    var hexComponents: [CGFloat] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { ($0 * 100).rounded() / 100 }
    }
}
