import XCTest

/// Taps every button on every screen, one per fresh launch, and records where it lands.
/// Not part of the normal suite's intent: it's a crash-and-dead-end sweep. Each tap logs a line
///   SWEEP <screen> | <button> | <result> | <first texts on the screen after the tap>
/// and attaches a screenshot. Run it against a local server (TEST_RUNNER_WB_SERVER=http://localhost:8100):
/// it starts, escalates and ends demo walks.
final class ButtonSweep: XCTestCase {
    let server = ProcessInfo.processInfo.environment["WB_SERVER"] ?? "http://localhost:8100"
    /// Buttons that leave the app (phone, Maps) are not tapped.
    let skip = ["Call ", "Open in Maps"]

    override func setUp() { continueAfterFailure = true }

    // MARK: server helpers

    private func send(_ method: String, _ path: String, _ body: String? = "{}") -> Any? {
        var req = URLRequest(url: URL(string: server + path)!)
        req.httpMethod = method
        if let body, method != "GET" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body.data(using: .utf8)
        }
        var out: Any?
        let done = expectation(description: path)
        URLSession.shared.dataTask(with: req) { d, _, _ in
            out = d.flatMap { try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 15)
        return out
    }
    private func activeWalk() -> [String: Any]? { send("GET", "/users/jordan/active", nil) as? [String: Any] }
    private func state() -> String { (activeWalk()?["engine"] as? [String: Any])?["state"] as? String ?? "none" }

    private func closeAlerts() {
        let feed = send("GET", "/friends/maya/feed", nil) as? [String: Any]
        for a in (feed?["open_alerts"] as? [[String: Any]]) ?? [] {
            if let id = a["id"] as? String { _ = send("POST", "/alerts/\(id)/close", #"{"friend_id":"maya"}"#) }
        }
    }
    private func noWalk() {
        if let w = activeWalk(), let id = w["id"] as? String { _ = send("POST", "/walks/\(id)/end") }
        closeAlerts()
    }
    private func calmWalk() {
        closeAlerts()
        if let w = activeWalk(), let e = w["engine"] as? [String: Any], (e["state"] as? String) == "calm" { return }
        noWalk()
        _ = send("POST", "/demo/start")
    }
    private func alertWalk() {
        noWalk()
        _ = send("POST", "/demo/start")
        _ = send("POST", "/demo/speed", #"{"x":40}"#)
        _ = send("POST", "/demo/stop-answering")
        for _ in 0..<40 where state() != "alert" { Thread.sleep(forTimeInterval: 0.5) }
        _ = send("POST", "/demo/speed", #"{"x":null}"#)
    }

    // MARK: screens

    struct Screen { let name: String; let role: String; let args: [String]; let setup: String }
    var screens: [Screen] {
        [
            Screen(name: "welcome", role: "", args: [], setup: "none"),
            Screen(name: "home", role: "walker", args: [], setup: "none"),
            Screen(name: "plan", role: "walker", args: ["-previewPlan", "Tooker House"], setup: "none"),
            Screen(name: "settings", role: "walker", args: ["-panel", "settings"], setup: "none"),
            Screen(name: "flags", role: "walker", args: ["-panel", "flags"], setup: "none"),
            Screen(name: "trips", role: "walker", args: ["-panel", "trips"], setup: "none"),
            Screen(name: "customize", role: "walker", args: ["-panel", "customize"], setup: "none"),
            Screen(name: "walk", role: "walker", args: [], setup: "calm"),
            Screen(name: "friend", role: "friend", args: [], setup: "calm"),
            Screen(name: "friend-settings", role: "friend", args: ["-panel", "settings"], setup: "none"),
            Screen(name: "friend-alert", role: "friend", args: [], setup: "alert"),
        ]
    }

    private func prepare(_ s: Screen) {
        switch s.setup {
        case "calm": calmWalk()
        case "alert": alertWalk()
        default: noWalk()
        }
    }

    private func open(_ s: Screen) -> XCUIApplication {
        prepare(s)
        let app = XCUIApplication()
        app.launchArguments = ["-wb.role", s.role, "-wb.server", server] + s.args
        app.launch()
        sleep(3)
        return app
    }

    /// Scroll from the left margin so a swipe never lands on a map.
    private func scrollDown(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.8))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.3)))
        usleep(500_000)
    }

    private func key(_ b: XCUIElement) -> String {
        let id = b.identifier, label = b.label
        return id.isEmpty ? label : id
    }

    private func find(_ app: XCUIApplication, _ k: String) -> XCUIElement {
        let byId = app.buttons.matching(identifier: k).firstMatch
        if byId.exists { return byId }
        return app.buttons.matching(NSPredicate(format: "label == %@", k)).firstMatch
    }

    private func summary(_ app: XCUIApplication) -> String {
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(4).map { $0.label }.filter { !$0.isEmpty }
        return texts.joined(separator: " / ").replacingOccurrences(of: "\n", with: " ")
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func sweep(_ s: Screen) {
        // Inventory: every hittable button at each scroll position (up to 6 screens down).
        var plan: [(depth: Int, key: String)] = []
        var seen = Set<String>()
        let app = open(s)
        shot("\(s.name)-00-start")
        for depth in 0...6 {
            for b in app.buttons.allElementsBoundByIndex where b.exists && b.isHittable {
                let k = key(b)
                if k.isEmpty || seen.contains(k) || skip.contains(where: { k.hasPrefix($0) }) { continue }
                seen.insert(k)
                plan.append((depth, k))
            }
            scrollDown(app)
        }
        print("SWEEP \(s.name) | inventory | \(plan.count) buttons | \(plan.map(\.key).joined(separator: ", "))")

        for (i, item) in plan.enumerated() {
            let app = open(s)
            for _ in 0..<item.depth { scrollDown(app) }
            let b = find(app, item.key)
            guard b.exists && b.isHittable else {
                print("SWEEP \(s.name) | \(item.key) | NOT FOUND after relaunch |")
                continue
            }
            let before = summary(app)
            b.tap()
            sleep(2)
            let alive = app.state == .runningForeground
            let after = alive ? summary(app) : ""
            let result = !alive ? "APP NOT RUNNING" : (after == before ? "same screen" : "changed")
            print("SWEEP \(s.name) | \(item.key) | \(result) | \(after)")
            shot(String(format: "%@-%02d-%@", s.name, i + 1, item.key))
            XCTAssertTrue(alive, "\(s.name): tapping \(item.key) left the app")
        }
    }

    func testSweepAllScreens() {
        for s in screens { sweep(s) }
        noWalk()
    }
}
