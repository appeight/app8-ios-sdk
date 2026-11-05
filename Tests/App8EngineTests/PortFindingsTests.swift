//
//  PortFindingsTests.swift
//  App8EngineTests
//
//  Regression tests for engine bugs found while porting App8 to Android.
//  See NOTES-android.md at the repo root for the cross-platform contract.
//

import XCTest
import UIKit
@testable import App8Engine

@MainActor
final class PortFindingsTests: XCTestCase {

    // MARK: - #1 datePicker time / dateAndTime keep the time

    private func renderDatePicker(mode: String, harness: RenderHarness) throws {
        try harness.render("""
        {
          "type": "view", "id": "root",
          "content": {
            "properties": {},
            "variables": { "when": { "type": "string", "initialValue": "2026-01-01" } },
            "layout": { "width": 390, "height": 400 },
            "children": [
              { "type": "datePicker", "id": "dp",
                "content": {
                  "properties": { "datePickerMode": "\(mode)", "displayStyle": "wheels", "bindVariable": "when" },
                  "layout": { "top": 0, "leading": 0 }
                } }
            ]
          }
        }
        """)
    }

    private func pick(_ date: Date, harness: RenderHarness) throws -> String? {
        let picker = try XCTUnwrap(harness.find(UIDatePicker.self))
        picker.date = date
        harness.fire(picker, .valueChanged)
        harness.drain()
        let rootVM = try XCTUnwrap(harness.viewModel("root", as: CViewModel.self))
        return rootVM.variableStore.getValue(name: "when") as? String
    }

    private func localDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testDatePickerTimeModeStoresTime() throws {
        let harness = RenderHarness()
        try renderDatePicker(mode: "time", harness: harness)
        let date = localDate(2026, 3, 4, 14, 30)
        let stored = try XCTUnwrap(try pick(date, harness: harness))
        XCTAssertTrue(stored.contains("T14:30:00"), "time mode must keep the time, got \(stored)")
        let parsed = ISO8601DateFormatter().date(from: stored)
        XCTAssertEqual(parsed, date)
    }

    func testDatePickerDateAndTimeModeStoresTime() throws {
        let harness = RenderHarness()
        try renderDatePicker(mode: "dateAndTime", harness: harness)
        let date = localDate(2026, 3, 4, 9, 5)
        let stored = try XCTUnwrap(try pick(date, harness: harness))
        XCTAssertTrue(stored.hasPrefix("2026-03-04T09:05:00"), "got \(stored)")
        XCTAssertEqual(ISO8601DateFormatter().date(from: stored), date)
    }

    func testDatePickerDateModeStillStoresDateOnly() throws {
        let harness = RenderHarness()
        try renderDatePicker(mode: "date", harness: harness)
        let stored = try pick(localDate(2026, 3, 4, 14, 30), harness: harness)
        XCTAssertEqual(stored, "2026-03-04")
    }
}
