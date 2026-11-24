//
//  WeekStartTests.swift
//  App8EngineTests
//
//  startOfWeek / weekdayIndex (app8-dsl docs/variables.md, 0.7.16): the week
//  starts on the locale's first weekday (en-US Sunday, de-AT Monday). The
//  shared input/output table from app8-conformance
//  (fixtures/functions/week-start.json) is kept here as
//  Fixtures/week-start.table (not .json: the parsing tests load every .json
//  fixture as an app).
//

import XCTest
@testable import App8Engine

@MainActor
final class WeekStartTests: XCTestCase {

    private var savedTimeZone: TimeZone!

    override func setUp() {
        super.setUp()
        savedTimeZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "Europe/Vienna")!
    }

    override func tearDown() {
        NSTimeZone.default = savedTimeZone
        super.tearDown()
    }

    private func eval(_ expression: String, locale: String, variables: [String: Any] = [:]) throws -> Any? {
        let store = VariableStore()
        for (name, value) in variables {
            let type: VariableType = value is [Any] ? .array : (value is String ? .string : .object)
            try store.defineVariable(name: name, definition: VariableDefinition(type: type, initialValue: nil))
            try store.setValue(name: name, value: value is NSNull ? nil : value)
        }
        let evaluator = ExpressionEvaluator()
        evaluator.firstWeekdayLocale = Locale(identifier: locale)
        return try evaluator.evaluate(ExpressionParser().parse(expression), context: VariableContext(store: store))
    }

    // MARK: - Named cases

    func testWednesdayInUSAndAustria() throws {
        XCTAssertEqual(try eval("{{startOfWeek('2026-11-25')}}", locale: "en_US") as? String, "2026-11-22")
        XCTAssertEqual(try eval("{{weekdayIndex('2026-11-25')}}", locale: "en_US") as? Int, 3)
        XCTAssertEqual(try eval("{{startOfWeek('2026-11-25')}}", locale: "de_AT") as? String, "2026-11-23")
        XCTAssertEqual(try eval("{{weekdayIndex('2026-11-25')}}", locale: "de_AT") as? Int, 2)
    }

    func testRegionDecidesNotLanguage() throws {
        XCTAssertEqual(try eval("{{weekdayIndex('2026-11-25')}}", locale: "en_GB") as? Int, 2, "en-GB starts on Monday")
        XCTAssertEqual(try eval("{{weekdayIndex('2026-11-25')}}", locale: "de_DE") as? Int, 2)
    }

    func testDateThatIsTheFirstWeekday() throws {
        XCTAssertEqual(try eval("{{startOfWeek('2026-11-22')}}", locale: "en_US") as? String, "2026-11-22")
        XCTAssertEqual(try eval("{{weekdayIndex('2026-11-22')}}", locale: "en_US") as? Int, 0)
        XCTAssertEqual(try eval("{{startOfWeek('2026-11-23')}}", locale: "de_AT") as? String, "2026-11-23")
        XCTAssertEqual(try eval("{{weekdayIndex('2026-11-23')}}", locale: "de_AT") as? Int, 0)
    }

    func testSaturdayAndSundayEdges() throws {
        XCTAssertEqual(try eval("{{weekdayIndex('2026-11-28')}}", locale: "en_US") as? Int, 6)
        XCTAssertEqual(try eval("{{startOfWeek('2026-11-29')}}", locale: "en_US") as? String, "2026-11-29", "a Sunday starts a new US week")
        XCTAssertEqual(try eval("{{weekdayIndex('2026-11-29')}}", locale: "de_AT") as? Int, 6)
        XCTAssertEqual(try eval("{{startOfWeek('2026-11-29')}}", locale: "de_AT") as? String, "2026-11-23", "a Sunday ends the Austrian week")
    }

    func testAcrossMonthAndYear() throws {
        XCTAssertEqual(try eval("{{startOfWeek('2026-12-01')}}", locale: "en_US") as? String, "2026-11-29")
        XCTAssertEqual(try eval("{{startOfWeek('2026-12-01')}}", locale: "de_AT") as? String, "2026-11-30")
        XCTAssertEqual(try eval("{{startOfWeek('2027-01-01')}}", locale: "en_US") as? String, "2026-12-27")
        XCTAssertEqual(try eval("{{startOfWeek('2027-01-01')}}", locale: "de_AT") as? String, "2026-12-28")
    }

    func testDateTimeGivesStartOfDayInUTCAcrossDST() throws {
        XCTAssertEqual(try eval("{{startOfWeek('2026-11-25T10:00:00Z')}}", locale: "de_AT") as? String, "2026-11-22T23:00:00Z")
        // Sunday 29 March is the switch to summer time in Vienna.
        XCTAssertEqual(try eval("{{startOfWeek('2026-03-31T10:00:00Z')}}", locale: "en_US") as? String, "2026-03-28T23:00:00Z")
        XCTAssertEqual(try eval("{{startOfWeek('2026-03-31T10:00:00Z')}}", locale: "de_AT") as? String, "2026-03-29T22:00:00Z")
        XCTAssertEqual(try eval("{{weekdayIndex('2026-11-28T23:30:00Z')}}", locale: "de_AT") as? Int, 6, "Sunday 00:30 in Vienna")
    }

    func testInvalidInputIsNullAndArityThrows() throws {
        XCTAssertNil(try eval("{{startOfWeek('soon')}}", locale: "de_AT"))
        XCTAssertNil(try eval("{{weekdayIndex(5)}}", locale: "de_AT"))
        XCTAssertThrowsError(try eval("{{startOfWeek()}}", locale: "de_AT"))
        XCTAssertThrowsError(try eval("{{weekdayIndex('2026-11-25', 1)}}", locale: "de_AT"))
    }

    func testDeviceDefaultFollowsCurrentCalendar() throws {
        let evaluator = ExpressionEvaluator()
        let index = try XCTUnwrap(evaluator.evaluate(ExpressionParser().parse("{{weekdayIndex('2026-11-22')}}"), context: VariableContext(store: VariableStore())) as? Int)
        XCTAssertEqual(index, (1 - Calendar.autoupdatingCurrent.firstWeekday + 7) % 7, "2026-11-22 is a Sunday (weekday 1)")
    }

    // MARK: - Shared table

    /// JSON-normalized, so 1 == 1.0 and NSNull == null.
    private func normalized(_ value: Any?) throws -> NSObject {
        let data = try JSONSerialization.data(withJSONObject: value ?? NSNull(), options: [.fragmentsAllowed, .sortedKeys])
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as! NSObject
    }

    private func tableData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "week-start", withExtension: "table"))
        return try Data(contentsOf: url)
    }

    func testSharedTable() throws {
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: tableData()) as? [String: Any])
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: try XCTUnwrap(raw["timeZone"] as? String)))
        let variables = try XCTUnwrap(raw["variables"] as? [String: Any])
        let cases = try XCTUnwrap(raw["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 30)
        for c in cases {
            let expression = try XCTUnwrap(c["expression"] as? String)
            let locale = try XCTUnwrap(c["locale"] as? String).replacingOccurrences(of: "-", with: "_")
            let result = try eval(expression, locale: locale, variables: variables)
            XCTAssertEqual(try normalized(result), try normalized(c["expected"]), "\(locale): \(expression)")
        }
    }

    /// The vendored copy equals app8-conformance's when that checkout is next to this repo.
    func testVendoredTableMatchesConformance() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("app8-conformance/fixtures/functions/week-start.json")
        guard let other = try? Data(contentsOf: url) else { return }
        XCTAssertEqual(try normalized(JSONSerialization.jsonObject(with: other)), try normalized(JSONSerialization.jsonObject(with: tableData())), "\(url.path) differs: copy it to Fixtures/week-start.table")
    }
}
