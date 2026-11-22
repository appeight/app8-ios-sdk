import XCTest

final class HarnessUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
    }

    private func launch(tab: String = "home") {
        app.launchEnvironment["A8_TAB"] = tab
        app.launch()
        XCTAssertTrue(app.buttons["HOME"].waitForExistence(timeout: 20), "tab bar up")
        sleep(1)
    }

    private func mark(_ s: String) { print("HARNESS-MARK \(Date().timeIntervalSince1970) \(s)") }

    private var productShown: Bool {
        let l = app.staticTexts["ADD TO BAG"]
        return l.exists && l.isHittable
    }

    private func tabBarShown(_ ctx: String, file: StaticString = #filePath, line: UInt = #line) {
        let home = app.buttons["HOME"]
        let ok = home.waitForExistence(timeout: 3) && home.isHittable
        XCTAssertTrue(ok, "tab bar back after \(ctx)", file: file, line: line)
        if !ok { print("HARNESS-TREE \(ctx)\n\(app.debugDescription)") }
    }

    private func openProduct(_ id: String = "p1", file: StaticString = #filePath, line: UInt = #line) {
        mark("open \(id)")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        let l = app.staticTexts["ADD TO BAG"]
        XCTAssertTrue(l.waitForExistence(timeout: 5), "product pushed", file: file, line: line)
        sleep(1)
    }

    private func drag(from: CGVector, to: CGVector, velocity: XCUIGestureVelocity = .default, hold: TimeInterval = 0) {
        let a = app.coordinate(withNormalizedOffset: from)
        let b = app.coordinate(withNormalizedOffset: to)
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: velocity, thenHoldForDuration: hold)
    }

    private func assertGone(_ ctx: String, file: StaticString = #filePath, line: UInt = #line) {
        sleep(1)
        XCTAssertFalse(productShown, "product gone after \(ctx)", file: file, line: line)
        tabBarShown(ctx, file: file, line: line)
    }

    private func assertStill(_ ctx: String, file: StaticString = #filePath, line: UInt = #line) {
        sleep(1)
        XCTAssertTrue(productShown, "product still up after \(ctx)", file: file, line: line)
    }

    /// The nav bar buttons respond: star toggles the saved badge, back pops.
    private func checkButtons(_ ctx: String, file: StaticString = #filePath, line: UInt = #line) {
        let saved = app.buttons["SAVED"]
        let before = saved.value as? String
        let bar = app.navigationBars.firstMatch
        let star = bar.buttons.element(boundBy: bar.buttons.count - 1)
        mark("star \(ctx)")
        star.tap()
        sleep(1)
        let after = saved.value as? String
        XCTAssertNotEqual(before, after, "star responds (\(ctx)): \(before ?? "nil") → \(after ?? "nil")", file: file, line: line)
        mark("back \(ctx)")
        bar.buttons.element(boundBy: 0).tap()
        assertGone("back tap (\(ctx))", file: file, line: line)
    }

    private let back = { (app: XCUIApplication) in app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap() }

    func test1BackTap() {
        launch(); openProduct(); mark("back tap"); back(app); assertGone("back tap")
        openProduct(); checkButtons("second push")
    }
    func test2EdgeSwipeDone() {
        launch(); openProduct(); mark("edge done")
        drag(from: CGVector(dx: 0.003, dy: 0.75), to: CGVector(dx: 0.95, dy: 0.75), velocity: .fast); assertGone("edge swipe done")
        openProduct(); checkButtons("after edge done")
    }
    func test3EdgeSwipeCancelled() {
        launch(); openProduct(); mark("edge cancel")
        drag(from: CGVector(dx: 0.003, dy: 0.75), to: CGVector(dx: 0.08, dy: 0.75), velocity: .slow, hold: 0.3); assertStill("edge swipe cancelled")
        checkButtons("after edge cancel")
    }
    func test4DismissDone() {
        launch(); openProduct(); mark("dismiss done")
        drag(from: CGVector(dx: 0.35, dy: 0.8), to: CGVector(dx: 0.98, dy: 0.8), velocity: .fast); assertGone("interactive dismiss done")
        openProduct(); checkButtons("after dismiss done")
    }
    func test5DismissCancelled() {
        launch(); openProduct(); mark("dismiss cancel")
        drag(from: CGVector(dx: 0.35, dy: 0.8), to: CGVector(dx: 0.42, dy: 0.8), velocity: .slow, hold: 0.3); assertStill("interactive dismiss cancelled")
        checkButtons("after dismiss cancel")
    }

    /// iOS 26: a swipe from anywhere on a plainly pushed screen (a grid)
    /// pops it, also after a hero zoom push came and went.
    func test9NoTabsContentSwipe() {
        app.launchEnvironment["A8_NOTABS"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["OPEN INFO"].waitForExistence(timeout: 15))
        app.buttons["OPEN INFO"].tap()
        XCTAssertTrue(app.navigationBars["Info"].waitForExistence(timeout: 5))
        sleep(1)
        app.swipeRight()
        sleep(1)
        XCTAssertFalse(app.navigationBars["Info"].exists, "no tabs: content swipe pops")
    }

    func test7ContentSwipeBack() {
        launch(tab: "bag")
        app.buttons["OPEN INFO"].tap()
        XCTAssertTrue(app.navigationBars["Info"].waitForExistence(timeout: 5))
        sleep(1); mark("content swipe info")
        app.swipeRight()
        sleep(1)
        XCTAssertFalse(app.navigationBars["Info"].exists, "content swipe popped the plain screen")
        if app.navigationBars["Info"].exists { back(app); sleep(1) }
        contentSwipe("grid, first push")
        app.buttons["HOME"].tap(); sleep(1)
        openProduct(); back(app); sleep(1)
        app.buttons["BAG"].tap(); sleep(1)
        contentSwipe("grid, after a hero push")
        app.buttons["SAVED"].tap(); sleep(1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()
        XCTAssertTrue(app.staticTexts["ADD TO BAG"].waitForExistence(timeout: 5), "card zoom push")
        sleep(1); back(app); sleep(1)
        app.buttons["BAG"].tap(); sleep(1)
        contentSwipe("grid, after a card zoom push")
    }

    private func contentSwipe(_ ctx: String, file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["OPEN GRID"].tap()
        XCTAssertTrue(app.navigationBars["Category"].waitForExistence(timeout: 5), "grid pushed", file: file, line: line)
        sleep(1)
        mark("content swipe \(ctx)")
        app.swipeRight()
        sleep(1)
        XCTAssertTrue(app.buttons["OPEN GRID"].waitForExistence(timeout: 2) && app.buttons["OPEN GRID"].isHittable,
                      "content swipe popped the grid (\(ctx))", file: file, line: line)
        if app.navigationBars["Category"].exists { back(app); sleep(1) }
    }

    /// Screenshots of a material bar background over the photo feed.
    func testMaterialBarScreenshots() {
        for mode in ["blur", "blurtint"] {
            app.launchEnvironment["A8_BAR"] = mode
            launch()
            sleep(2)
            let shot = XCUIScreen.main.screenshot()
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/a8-bar-\(mode).png"))
            app.terminate()
        }
        app.launchEnvironment["A8_BAR"] = nil
    }

    /// Feed photo → product and card → product, push and a slow drag-down
    /// dismiss held half way, for a side-by-side recording.
    func test6CompareZooms() {
        launch()
        mark("cmp feed push"); app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap(); sleep(2)
        mark("cmp feed drag")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.8)).press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.9)), withVelocity: .slow, thenHoldForDuration: 0.8)
        sleep(2)
        assertGone("feed drag dismiss")
        app.buttons["SAVED"].tap(); sleep(1)
        mark("cmp card push"); app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap(); sleep(2)
        mark("cmp card drag")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.8)).press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.9)), withVelocity: .slow, thenHoldForDuration: 0.8)
        sleep(2)
        XCTAssertFalse(productShown, "card drag dismiss")
    }

    func testContextMenuPreviewTap() {
        launch(tab: "saved")
        let card = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25))
        mark("longpress preview")
        card.press(forDuration: 1.2)
        sleep(1)
        mark("tap preview")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(app.staticTexts["ADD TO BAG"].waitForExistence(timeout: 5), "product after preview tap")
        sleep(2)
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        sleep(2)
        mark("longpress view")
        card.press(forDuration: 1.2)
        let view = app.buttons["View product"]
        XCTAssertTrue(view.waitForExistence(timeout: 3), "menu up")
        sleep(1)
        mark("tap view product")
        view.tap()
        XCTAssertTrue(app.staticTexts["ADD TO BAG"].waitForExistence(timeout: 5), "product after View product")
        sleep(2)
    }
}
