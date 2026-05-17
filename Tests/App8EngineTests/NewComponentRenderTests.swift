//
//  NewComponentRenderTests.swift
//  App8Engine
//

import XCTest
import UIKit
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

    // MARK: - PageControl

    func testPageControlRendersUIPageControl() throws {
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

        let uiPageControl = findView(ofType: UIPageControl.self, in: superview)
        XCTAssertNotNil(uiPageControl, "UIPageControl should be in hierarchy")
        XCTAssertEqual(uiPageControl?.numberOfPages, 5)
        XCTAssertEqual(uiPageControl?.currentPage, 2)
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
