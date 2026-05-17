//
//  FocusManagerTests.swift
//  App8EngineTests
//

import XCTest
import Combine
@testable import App8Engine

@MainActor
final class FocusManagerTests: XCTestCase {

    var manager: FocusManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        manager = FocusManager()
        cancellables = []
    }

    override func tearDown() {
        manager = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Registration Tests

    func testRegisterView() {
        let view = UIView()
        manager.register(id: "field1", view: view)

        XCTAssertEqual(manager.registeredIds, ["field1"])
    }

    func testRegisterMultipleViews() {
        let view1 = UIView()
        let view2 = UIView()
        let view3 = UIView()

        manager.register(id: "field1", view: view1)
        manager.register(id: "field2", view: view2)
        manager.register(id: "field3", view: view3)

        XCTAssertEqual(manager.registeredIds, ["field1", "field2", "field3"])
    }

    func testRegisterSameIdTwice() {
        let view1 = UIView()
        let view2 = UIView()

        manager.register(id: "field1", view: view1)
        manager.register(id: "field1", view: view2)

        // Should not duplicate in order
        XCTAssertEqual(manager.registeredIds, ["field1"])
    }

    func testUnregisterView() {
        let view1 = UIView()
        let view2 = UIView()

        manager.register(id: "field1", view: view1)
        manager.register(id: "field2", view: view2)
        manager.unregister(id: "field1")

        XCTAssertEqual(manager.registeredIds, ["field2"])
    }

    func testUnregisterCurrentlyFocused() {
        let view = UIView()
        manager.register(id: "field1", view: view)
        manager.didFocus(id: "field1")

        XCTAssertEqual(manager.currentFocusId, "field1")

        manager.unregister(id: "field1")

        XCTAssertNil(manager.currentFocusId)
    }

    func testClearAll() {
        let view1 = UIView()
        let view2 = UIView()

        manager.register(id: "field1", view: view1)
        manager.register(id: "field2", view: view2)
        manager.didFocus(id: "field1")

        manager.clearAll()

        XCTAssertEqual(manager.registeredIds, [])
        XCTAssertNil(manager.currentFocusId)
    }

    // MARK: - Focus State Tests

    func testDidFocus() {
        let view = UIView()
        manager.register(id: "field1", view: view)

        manager.didFocus(id: "field1")

        XCTAssertEqual(manager.currentFocusId, "field1")
    }

    func testDidFocusNil() {
        let view = UIView()
        manager.register(id: "field1", view: view)
        manager.didFocus(id: "field1")

        manager.didFocus(id: nil)

        XCTAssertNil(manager.currentFocusId)
    }

    // MARK: - Focus Change Publisher Tests

    func testFocusChangePublisher() {
        let view = UIView()
        manager.register(id: "field1", view: view)

        var receivedIds: [String?] = []
        manager.focusChange
            .sink { receivedIds.append($0) }
            .store(in: &cancellables)

        manager.didFocus(id: "field1")
        manager.didFocus(id: nil)

        XCTAssertEqual(receivedIds.count, 2)
        XCTAssertEqual(receivedIds[0], "field1")
        XCTAssertNil(receivedIds[1])
    }

    // MARK: - Focus Navigation Tests

    func testFocusNextWithNoCurrentFocus() {
        let view1 = UIView()
        let view2 = UIView()

        manager.register(id: "field1", view: view1)
        manager.register(id: "field2", view: view2)

        manager.focusNext()

        XCTAssertEqual(manager.currentFocusId, "field1")
    }

    func testFocusPreviousWithNoCurrentFocus() {
        let view1 = UIView()
        let view2 = UIView()

        manager.register(id: "field1", view: view1)
        manager.register(id: "field2", view: view2)

        manager.focusPrevious()

        XCTAssertEqual(manager.currentFocusId, "field2")
    }

    // MARK: - Cleanup Tests

    func testCleanUpRemovesDeadReferences() {
        var view1: UIView? = UIView()
        let view2 = UIView()

        manager.register(id: "field1", view: view1!)
        manager.register(id: "field2", view: view2)

        XCTAssertEqual(manager.registeredIds.count, 2)

        view1 = nil

        manager.cleanUp()

        XCTAssertEqual(manager.registeredIds, ["field2"])
    }

    // MARK: - Reset Tests

    func testReset() {
        let view = UIView()
        manager.register(id: "field1", view: view)
        manager.didFocus(id: "field1")

        manager.reset()

        XCTAssertEqual(manager.registeredIds, [])
        XCTAssertNil(manager.currentFocusId)
    }
}
