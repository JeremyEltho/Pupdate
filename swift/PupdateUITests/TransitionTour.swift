import XCTest

/// Walks the main flows and, after every tap that changes screens, takes a burst of screenshots so the
/// in-between frames of each transition can be inspected. Attachments are named
///   <step>-f<frame>
/// Run against a local server (TEST_RUNNER_WB_SERVER=http://localhost:8100).
final class TransitionTour: XCTestCase {
    let server = ProcessInfo.processInfo.environment["WB_SERVER"] ?? "http://localhost:8100"

    override func setUp() { continueAfterFailure = true }

    private func api(_ path: String, _ body: String = "{}") {
        var req = URLRequest(url: URL(string: server + path)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)
        let done = expectation(description: path)
        URLSession.shared.dataTask(with: req) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 15)
    }

    /// About 10 frames over ~1.2 s, starting right after the action.
    private func burst(_ step: String, frames: Int = 10, _ action: () -> Void) {
        action()
        for f in 0..<frames {
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            a.name = String(format: "%@-f%02d", step, f)
            a.lifetime = .keepAlways
            add(a)
        }
    }

    private func text(_ app: XCUIApplication, _ s: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    private func launch(_ role: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-wb.role", role, "-wb.server", server] + extra
        app.launch()
        return app
    }

    func testWalkerTour() {
        api("/demo/reset")
        api("/users/jordan/buddy", #"{"name":"Melvin","species":"dog"}"#)
        // No -wb.role argument here: an argument would pin the role for the whole run, so the tap
        // could not change it. The shell clears the saved role before this test.
        let app = XCUIApplication()
        app.launchArguments = ["-wb.server", server]
        app.launch()
        let walker = app.buttons["I'm walking home (Jordan)"]
        if walker.waitForExistence(timeout: 6) {
            burst("01-role-to-home") { walker.tap() }
        } else {
            burst("01-launch-to-home", frames: 14) {}   // a saved role skips the role screen
        }

        let gear = app.buttons["Settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        burst("02-open-settings") { gear.tap() }
        burst("03-close-settings") { app.buttons["Close settings"].tap() }

        let customize = app.buttons["Customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 5))
        burst("04-open-customize") { customize.tap() }
        burst("05-close-customize") { app.buttons["Close"].firstMatch.tap() }

        let trips = app.buttons["open-trips"]
        if !trips.isHittable { app.swipeUp() }
        burst("06-open-trips") { trips.tap() }
        burst("07-close-trips") { app.buttons.element(boundBy: 0).tap() }
        app.swipeDown()

        let whereTo = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Where to tonight?")).firstMatch
        XCTAssertTrue(whereTo.waitForExistence(timeout: 10))
        burst("08-open-plan") { whereTo.tap() }
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Tooker House\n")
        let go = app.buttons["Walk with Melvin"]
        XCTAssertTrue(go.waitForExistence(timeout: 25), "no trip sheet")
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: go)
        waitForExpectations(timeout: 25)
        burst("09-start-walk-from-plan", frames: 14) { go.tap() }
        XCTAssertTrue(text(app, "Walking together").waitForExistence(timeout: 15), "walk screen never showed")

        // Check-in arrives (server), then the walker pets it away.
        burst("10-checkin-arrives", frames: 14) { api("/demo/checkin") }
        let buddy = app.buttons["Your buddy"].firstMatch
        XCTAssertTrue(text(app, "Still good?").waitForExistence(timeout: 10))
        burst("11-pet-answers", frames: 14) {
            buddy.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: buddy.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)))
        }
        if app.buttons["Awesome"].waitForExistence(timeout: 4) { burst("12-close-evolution") { app.buttons["Awesome"].tap() } }

        // End early card opens and cancels, then the walk ends and Home returns.
        let early = app.buttons["End walk early"]
        var tries = 0
        while !(early.exists && early.isHittable) && tries < 10 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.3)))
            tries += 1
        }
        burst("13-open-end-early") { early.tap() }
        let cancel = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'keep walking' OR label CONTAINS[c] 'cancel'")).firstMatch
        if cancel.exists { burst("14-cancel-end-early") { cancel.tap() } }
        let end = app.buttons["End demo walk"]
        if end.exists && end.isHittable { burst("15-end-walk-to-home", frames: 14) { end.tap() } }
        XCTAssertTrue(text(app, "Where to tonight?").waitForExistence(timeout: 10), "Home never came back")
    }

    func testFriendTour() {
        api("/demo/reset")
        api("/demo/start")
        let app = launch("friend")
        XCTAssertTrue(text(app, "Walking now").waitForExistence(timeout: 15))
        burst("21-friend-open-settings") { app.buttons["Settings"].tap() }
        burst("22-friend-close-settings") { app.buttons["Close settings"].tap() }
        // Alert arrives while the friend is in Settings: it should close Settings and show the takeover.
        app.buttons["Settings"].tap()
        sleep(1)
        api("/demo/speed", #"{"x":40}"#)
        api("/demo/stop-answering")
        let close = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "close alert")).firstMatch
        burst("23-alert-arrives-over-settings", frames: 20) { sleep(2) }
        XCTAssertTrue(close.waitForExistence(timeout: 30), "alert takeover never showed")
        api("/demo/speed", #"{"x":null}"#)
        burst("24-close-alert", frames: 12) { close.tap() }
    }
}
