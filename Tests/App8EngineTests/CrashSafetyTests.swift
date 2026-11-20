//
//  CrashSafetyTests.swift
//  App8EngineTests
//
//  One regression per crash path that DSL input could reach: each used to
//  trap (a crash of the test process) and now degrades. See also
//  RobustnessFuzzTests, which found several of them.
//

import XCTest
import UIKit
import MapKit
@testable import App8Engine

@MainActor
final class CrashSafetyTests: XCTestCase {

    private var store: VariableStore!
    private var context: VariableContext!

    override func setUp() async throws {
        try await super.setUp()
        store = VariableStore()
        try store.defineVariable(name: "huge", definition: VariableDefinition(type: .number, initialValue: 1e300))
        try store.defineVariable(name: "big", definition: VariableDefinition(type: .number, initialValue: Int.max))
        try store.defineVariable(name: "nanText", definition: VariableDefinition(type: .string, initialValue: "NaN"))
        try store.defineVariable(name: "infText", definition: VariableDefinition(type: .string, initialValue: "1e309"))
        try store.defineVariable(name: "list", definition: VariableDefinition(type: .array, initialValue: [1, 2, 3]))
        context = VariableContext(store: store)
    }

    private func eval(_ expression: String) throws -> Any? {
        try ExpressionEvaluator().evaluate(try ExpressionParser().parse(expression), context: context)
    }

    private func action(_ json: [String: Any]) throws -> DSL.Model.Action {
        try JSONDecoder().decode(DSL.Model.Action.self, from: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: - Int(Double) traps in expressions

    func testHugeWholeNumberArithmeticStaysDouble() throws {
        // Int(1e300) traps; whole results past 2^53 stay Double.
        XCTAssertEqual(try eval("huge + 1") as? Double, 1e300)
        XCTAssertEqual(try eval("huge * 2") as? Double, 2e300)
        XCTAssertEqual(try eval("huge - 1") as? Double, 1e300)
        XCTAssertEqual(try eval("-huge") as? Double, -1e300)
        XCTAssertEqual(try eval("abs(huge)") as? Double, 1e300)
        XCTAssertEqual(try eval("max(huge, 1)") as? Double, 1e300)
        XCTAssertEqual(try eval("min(huge, huge * 10)") as? Double, 1e300)
        XCTAssertEqual(try eval("2 + 3") as? Int, 5, "small whole numbers stay Int")
    }

    func testRoundingFunctionsSaturate() throws {
        XCTAssertEqual(try eval("round(huge)") as? Int, Int.max)
        XCTAssertEqual(try eval("floor(-huge)") as? Int, Int.min)
        XCTAssertEqual(try eval("ceil(huge)") as? Int, Int.max)
        XCTAssertNotNil(try eval("formatDuration(huge)"))
        XCTAssertNotNil(try eval("formatMinutes(huge)"))
        XCTAssertNotNil(try eval("plural(huge, 'item', 'items')"))
        XCTAssertEqual((try eval("slice(list, huge)") as? [Any])?.count, 0)
        XCTAssertEqual((try eval("slice(list, -huge, huge)") as? [Any])?.count, 3)
    }

    func testNonFiniteStringsAreNotNumbers() throws {
        // "NaN" / "1e309" parse as Double.nan / .infinity; they are not DSL numbers.
        XCTAssertEqual(try eval("round(nanText)") as? Int, 0)
        XCTAssertEqual(try eval("floor(infText)") as? Int, 0)
    }

    // MARK: - Variable actions

    func testIncrementPastIntMaxDoesNotOverflow() throws {
        try VariableActionHandler().execute(
            action: try action(["type": "incrementVariable", "variableName": "big", "by": 1]),
            store: store, context: context)
        XCTAssertNotNil(store.getValue(name: "big"))
    }

    func testArrayIndexActionsWithHugeIndexes() throws {
        let handler = VariableActionHandler()
        try handler.execute(action: try action(["type": "insertArrayItem", "variableName": "list", "value": 9, "index": 1e300]),
                            store: store, context: context)
        try handler.execute(action: try action(["type": "insertArrayItem", "variableName": "list", "value": 8, "index": -1e300]),
                            store: store, context: context)
        try handler.execute(action: try action(["type": "removeArrayItem", "variableName": "list", "index": 1e300]),
                            store: store, context: context)
        XCTAssertEqual((store.getValue(name: "list") as? [Any])?.count, 5)
    }

    // MARK: - Numeric properties

    func testSaturatingIntConversion() {
        XCTAssertEqual(Int(saturating: Double.nan), 0)
        XCTAssertEqual(Int(saturating: Double.infinity), .max)
        XCTAssertEqual(Int(saturating: -Double.infinity), .min)
        XCTAssertEqual(Int(saturating: 1e300), .max)
        XCTAssertEqual(Int(saturating: -1e300), .min)
        XCTAssertEqual(Int(saturating: 42.9), 42)
        XCTAssertEqual(Int(saturating: -42.9), -42)
    }

    func testPageControlWithHugeCountRenders() throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 100))
        try harness.render(#"""
        { "type": "pageControl", "id": "dots", "content": {
            "properties": { "numberOfPages": "1e300", "currentPage": "-1e300" },
            "layout": { "top": 0, "leading": 0, "width": 200, "height": 30 } } }
        """#)
        let control = harness.find(MediaPageControl.self)
        XCTAssertNotNil(control)
        XCTAssertLessThanOrEqual(control?.numberOfPages ?? 0, EngineLimits.maxPageControlPages)
    }

    func testNonFiniteExpressionInLayoutIsIgnored() throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 300))
        try harness.render(#"""
        { "type": "view", "id": "root", "content": {
            "variables": { "bad": { "type": "string", "initialValue": "NaN" } },
            "layout": { "width": 390, "height": 300 },
            "children": [ { "type": "shape", "id": "s", "content": {
              "properties": { "type": "progress", "progress": "{{ bad }}" },
              "layout": { "top": 0, "leading": 0, "width": 100, "height": 20 } } } ] } }
        """#)
        harness.drain(0.05)
    }

    // MARK: - Error results

    /// A section header whose template is a bare pointer (its content dropped)
    /// renders the error view; the header pinned that detached view and UIKit
    /// threw "no common ancestor" (found by RobustnessFuzzTests).
    func testErrorResultIsAttachedToItsSuperview() throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 400))
        let host = UIView(frame: harness.superview.bounds)
        harness.superview.addSubview(host)
        let pointer = try JSONDecoder().decode(DSL.Model.Component.`Any`.self,
                                               from: Data(#"{ "type": "view", "id": "section-header" }"#.utf8))
        let result = harness.service.renderComponent(pointer, superview: host)
        XCTAssertTrue(result.view.superview === host)
        result.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([result.view.topAnchor.constraint(equalTo: host.topAnchor)])
    }

    // MARK: - Map

    /// MKMapView.setRegion throws "Invalid Region" on a huge span or an
    /// invalid center (found by RobustnessFuzzTests).
    func testMapRegionIsValidatedBeforeMapKit() {
        let sf = CLLocationCoordinate2D(latitude: 37.77, longitude: -122.42)
        let huge = CMapView.validRegion(center: sf, span: MKCoordinateSpan(latitudeDelta: 1e18, longitudeDelta: -5))
        XCTAssertEqual(huge?.span.latitudeDelta, 180)
        XCTAssertEqual(huge?.span.longitudeDelta, 0)
        XCTAssertNil(CMapView.validRegion(center: CLLocationCoordinate2D(latitude: 999, longitude: 0),
                                          span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)))
        XCTAssertNil(CMapView.validRegion(center: sf, span: MKCoordinateSpan(latitudeDelta: .nan, longitudeDelta: 1)))
    }

    // MARK: - Layout constraints

    /// A self constraint other than width/height had an assertionFailure: a
    /// debug host (preview, development build) crashed on the DSL input.
    func testConstraintWithoutTargetIsSkipped() throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 200))
        try harness.render(#"""
        { "type": "view", "id": "root", "content": { "layout": { "width": 390, "height": 200 }, "children": [
          { "type": "view", "id": "box", "content": { "layout": { "constraints": [
              { "type": "bottom", "constant": 10 },
              { "type": "centerX", "constant": 0 },
              { "type": "width", "constant": 50 },
              { "type": "height", "constant": 50 },
              { "type": "top", "target": "superview", "constant": 0 },
              { "type": "leading", "target": "superview", "constant": 0 } ] } } }
        ] } }
        """#)
        func all(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(all) }
        XCTAssertTrue(all(harness.superview).contains { $0.frame.size == CGSize(width: 50, height: 50) },
                      "the valid constraints still lay the box out")
    }

    /// An unsupported view → guide pairing (leading → top of the safe area) also asserted.
    func testUnsupportedGuideConstraintIsSkipped() throws {
        let harness = RenderHarness(size: CGSize(width: 390, height: 200))
        try harness.render(#"""
        { "type": "view", "id": "root", "content": { "layout": { "width": 390, "height": 200 }, "children": [
          { "type": "view", "id": "box", "content": { "layout": { "constraints": [
              { "type": "leading", "target": "safeArea", "attribute": "top", "constant": 0 },
              { "type": "width", "constant": 50 }, { "type": "height", "constant": 50 },
              { "type": "top", "target": "superview", "constant": 0 },
              { "type": "leading", "target": "superview", "constant": 0 } ] } } }
        ] } }
        """#)
        harness.drain(0.02)
    }
}
