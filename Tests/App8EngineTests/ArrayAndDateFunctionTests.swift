//
//  ArrayAndDateFunctionTests.swift
//  App8EngineTests
//
//  Array literals with expressions, prepend / append / uniqueBy / remove,
//  now / today / addDays / addHours / startOfDay, and the clock pulse that
//  re-evaluates `now()` readers.
//

import XCTest
@testable import App8Engine

@MainActor
final class ArrayAndDateFunctionTests: XCTestCase {

    private var store: VariableStore!

    override func setUp() {
        super.setUp()
        store = VariableStore()
        try! store.defineVariable(name: "name", definition: VariableDefinition(type: .string, initialValue: "Ann"))
        try! store.defineVariable(name: "event", definition: VariableDefinition(type: .object, initialValue: ["item": ["id": 3]]))
        try! store.defineVariable(name: "recent", definition: VariableDefinition(type: .array, initialValue: [["id": 1], ["id": 2]]))
        try! store.defineVariable(name: "nothing", definition: VariableDefinition(type: .array))
    }

    private func eval(_ expression: String) throws -> Any? {
        try ExpressionEvaluator().evaluate(ExpressionParser().parse(expression), context: VariableContext(store: store))
    }

    func testArrayLiteralEvaluatesEveryElement() throws {
        let result = try XCTUnwrap(eval("{{[event.item, 1, name + '!', event.missing]}}") as? [Any])
        XCTAssertEqual((result[0] as? [String: Any])?["id"] as? Int, 3)
        XCTAssertEqual(result[1] as? Int, 1)
        XCTAssertEqual(result[2] as? String, "Ann!")
        XCTAssertTrue(result[3] is NSNull)
    }

    func testPrependAppendUniqueByRemove() throws {
        let ids: (Any?) -> [Int?] = { ($0 as? [Any])?.map { ($0 as? [String: Any])?["id"] as? Int } ?? [] }
        XCTAssertEqual(ids(try eval("{{prepend(recent, event.item)}}")), [3, 1, 2])
        XCTAssertEqual(ids(try eval("{{append(recent, event.item)}}")), [1, 2, 3])
        XCTAssertEqual((try eval("{{append(nothing, 1)}}") as? [Int]), [1])
        XCTAssertEqual((try eval("{{append([1], [2, 3])}}") as? [Any])?.count, 2, "one element, also for arrays")
        XCTAssertEqual(ids(try eval("{{uniqueBy(concat(prepend(recent, event.item), recent), 'id')}}")), [3, 1, 2])
        XCTAssertEqual((try eval("{{uniqueBy([1, 2, 3], 'id')}}") as? [Int]), [1], "elements without the key share the key null")
        XCTAssertEqual((try eval("{{remove(['a', 'b', 'a'], 'a')}}") as? [String]), ["b"])
        XCTAssertEqual(ids(try eval("{{remove(recent, recent[0])}}")), [2], "objects compare by value")
        // Pure: the source is unchanged.
        XCTAssertEqual(ids(store.getValue(name: "recent")), [1, 2])
    }

    func testNowAndToday() throws {
        let now = try XCTUnwrap(eval("{{now()}}") as? String)
        XCTAssertNotNil(now.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"#, options: .regularExpression), now)
        let today = try XCTUnwrap(eval("{{today()}}") as? String)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(today, fmt.string(from: Date()))
    }

    func testDateArithmeticKeepsShapeAndAcceptsOffsets() throws {
        XCTAssertEqual(try eval("{{addDays('2026-03-14', 7)}}") as? String, "2026-03-21")
        XCTAssertEqual(try eval("{{addDays('2026-03-14', -1.7)}}") as? String, "2026-03-13", "whole days, truncated")
        XCTAssertEqual(try eval("{{addDays('2026-03-14T09:26:53Z', 7)}}") as? String, "2026-03-21T09:26:53Z")
        XCTAssertEqual(try eval("{{addHours('2026-03-14T10:26:53+01:00', 2)}}") as? String, "2026-03-14T11:26:53Z")
        XCTAssertEqual(try eval("{{addHours('2026-03-14T09:26:53.250+00:00', 0.5)}}") as? String, "2026-03-14T09:56:53Z")
        XCTAssertNil(try eval("{{addDays('soon', 1)}}") as? String)
        let start = try XCTUnwrap(eval("{{startOfDay('2026-03-14T09:26:53Z')}}") as? String)
        let expected = ArrayAndDateFunctionTests.isoUTC(Calendar.current.startOfDay(for: ISO8601DateFormatter().date(from: "2026-03-14T09:26:53Z")!))
        XCTAssertEqual(start, expected)
        XCTAssertEqual(try eval("{{daysBetween('2026-03-14T00:00:00+00:00', '2026-03-16T00:00:00Z')}}") as? Int, 2)
        XCTAssertNotEqual(try eval("{{formatDate('2026-03-14T09:26:53+00:00', 'yyyy')}}") as? String, "")
    }

    func testClockPulseRecomputesNowReaders() throws {
        try store.defineVariable(name: "stamp", definition: VariableDefinition(type: .string, computed: "{{now()}}"))
        let first = try XCTUnwrap(store.getValue(name: "stamp") as? String)
        var changed: [String] = []
        let sub = store.anyVariableChanged.sink { changed.append($0) }
        defer { sub.cancel() }
        RunLoop.main.run(until: Date().addingTimeInterval(1.05))
        store.pulseClock()
        let second = try XCTUnwrap(store.getValue(name: "stamp") as? String)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(changed.contains(DependencyExtractor.clockDependency))
        XCTAssertTrue(changed.contains("stamp"))
    }

    private static func isoUTC(_ date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }
}
