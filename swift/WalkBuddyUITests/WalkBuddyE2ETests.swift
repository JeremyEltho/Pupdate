import XCTest

/// End-to-end: the real app, tapping through the demo, against the real backend on localhost:8100.
final class WalkBuddyE2ETests: XCTestCase {
    let server = "https://45-76-67-21.sslip.io"

    override func setUp() { continueAfterFailure = false }

    private func api(_ path: String, _ body: String = "{}") {
        var req = URLRequest(url: URL(string: server + path)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)
        let done = expectation(description: path)
        URLSession.shared.dataTask(with: req) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 10)
    }

    private func launch(role: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-wb.role", role, "-wb.server", server]
        app.launch()
        return app
    }

    /// Scroll until a button exists and is hittable (SwiftUI drops far off-screen rows from the tree).
    @discardableResult
    private func reveal(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let b = app.buttons[label].firstMatch
        var tries = 0
        while !(b.exists && b.isHittable) && tries < 8 { app.swipeUp(); tries += 1 }
        return b
    }

    private func text(_ app: XCUIApplication, _ s: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    /// Walker answers the first check-in by petting: +10 XP and the evolution celebration.
    func testWalkerPetsAndEvolves() {
        api("/demo/reset")
        api("/demo/start")
        let app = launch(role: "walker")
        XCTAssertTrue(text(app, "Still good?").waitForExistence(timeout: 30), "check-in never showed")
        // A tap must not count: petting needs a real rub across the buddy.
        let buddy = app.buttons["Your buddy"].firstMatch
        buddy.tap()
        XCTAssertFalse(app.buttons["Awesome"].waitForExistence(timeout: 2), "a tap should not pet")
        let from = buddy.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
        let to = buddy.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to)
        XCTAssertTrue(app.buttons["Awesome"].waitForExistence(timeout: 8), "evolution overlay never showed")
        app.buttons["Awesome"].tap()
        XCTAssertTrue(text(app, "Walking together").waitForExistence(timeout: 8))
        XCTAssertTrue(text(app, "Chick").waitForExistence(timeout: 5))
    }

    /// Friend runs the demo panel: start, stop answering, the alert takeover, close.
    func testFriendGetsAlertAndClosesIt() {
        let app = launch(role: "friend")
        reveal(app, "Reset").tap()
        reveal(app, "Start walk").tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        XCTAssertTrue(text(app, "All good").waitForExistence(timeout: 10), "walk never appeared for the friend")
        reveal(app, "Stop answering").tap()
        // Wait for the takeover itself (the walk log also mentions "stopped answering" right away).
        let close = app.buttons["I've reached Jordan, close alert"]
        XCTAssertTrue(close.waitForExistence(timeout: 60), "alert takeover never showed")
        XCTAssertTrue(text(app, "Jordan stopped answering").exists)
        XCTAssertTrue(app.buttons["Call Jordan"].exists, "call button missing on the alert")
        close.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.buttons["I've reached Jordan, close alert"])
        waitForExpectations(timeout: 10)
    }

    /// Duress from the API reaches the friend with no call button.
    func testDuressHidesCallButton() {
        let app = launch(role: "friend")
        reveal(app, "Reset").tap()
        reveal(app, "Start walk").tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        XCTAssertTrue(text(app, "All good").waitForExistence(timeout: 10))
        // The walker's long-press calls /duress; trigger the same call directly.
        var walkId = ""
        let got = expectation(description: "user")
        URLSession.shared.dataTask(with: URL(string: server + "/users/jordan")!) { d, _, _ in
            walkId = ((try? JSONSerialization.jsonObject(with: d ?? Data())) as? [String: Any])?["active_walk_id"] as? String ?? ""
            got.fulfill()
        }.resume()
        wait(for: [got], timeout: 10)
        api("/walks/\(walkId)/duress")
        XCTAssertTrue(text(app, "sent a silent alert").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Call Jordan"].exists)
        app.buttons["I've reached Jordan, close alert"].tap()
    }

    /// Settings opens from home and shows the real toggles.
    func testSettingsOpens() {
        api("/demo/reset")
        let app = launch(role: "walker")
        let gear = app.buttons["Settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        gear.tap()
        XCTAssertTrue(app.staticTexts["Default route"].waitForExistence(timeout: 5))
        sleep(6) // the home screen keeps polling underneath; Settings must stay open
        XCTAssertTrue(app.staticTexts["Default route"].exists, "Settings closed by itself")
        XCTAssertTrue(app.switches.count >= 3)
        app.buttons["Close settings"].tap()
    }

    /// Walker plans a destination on the map page and starts a demo walk along Apple's route.
    func testPlanDestinationAndStartWalk() {
        api("/demo/reset")
        let app = launch(role: "walker")
        let whereTo = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Where to tonight?")).firstMatch
        XCTAssertTrue(whereTo.waitForExistence(timeout: 10))
        whereTo.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Tooker House\n")
        // Safer and quickest options (one card when Apple returns a single route).
        let options = app.buttons.matching(NSPredicate(format: "label == 'Safer route' OR label == 'Quickest route'"))
        let anyOption = options.firstMatch
        XCTAssertTrue(anyOption.waitForExistence(timeout: 20), "no route options")
        if app.buttons["Quickest route"].exists { app.buttons["Quickest route"].tap() }
        let go = app.buttons["Walk with Levin"]
        XCTAssertTrue(go.waitForExistence(timeout: 20), "no trip sheet")
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: go)
        waitForExpectations(timeout: 20)
        go.tap()
        XCTAssertTrue(text(app, "Walking together").waitForExistence(timeout: 15), "walk screen never showed")
        XCTAssertTrue(text(app, "Tooker House").waitForExistence(timeout: 5))
    }
}
