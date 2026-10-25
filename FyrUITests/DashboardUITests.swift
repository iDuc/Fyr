import XCTest

/// Main flows against a fake DRU bridge on 127.0.0.1 (`FakeDRUBridge`).
/// Never talks to a real fireplace: the app is pointed at the fake with
/// `-FyrBridgeEndpoint`, which only DEBUG builds read.
@MainActor
final class DashboardUITests: XCTestCase {

    private var bridge: FakeDRUBridge!
    private var app: XCUIApplication!

    /// The app reads the bridge once on launch (connect, 1.5 s settle, reads).
    private let statusTimeout: TimeInterval = 20

    /// Right after a new build is installed, the Home Screen may still be
    /// finishing the install; a launch then can lose its launch arguments.
    /// One throwaway launch first makes every test start the same way.
    nonisolated(unsafe) private static var warmedUp = false

    override func setUp() async throws {
        continueAfterFailure = false
        if !Self.warmedUp {
            Self.warmedUp = true
            let warmup = XCUIApplication()
            warmup.launch()
            _ = warmup.wait(for: .runningForeground, timeout: 20)
            warmup.terminate()
        }
    }

    override func tearDown() async throws {
        app?.terminate()
        bridge?.stop()
    }

    private func launch(burning: Bool = false, wave: Bool = false, startBridge: Bool = true, port: UInt16? = nil) throws {
        bridge = try FakeDRUBridge(burning: burning, wave: wave)
        var endpoint = "127.0.0.1:\(port ?? 1)"
        if startBridge {
            try bridge.start()
            endpoint = bridge.endpoint
        }
        app = XCUIApplication()
        app.launchArguments += [
            "-FyrBridgeEndpoint", endpoint,
            "-FyrUITestReset", "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
    }

    /// The big state word. The header combines it with its details for
    /// VoiceOver, so the identifier can match more than one element.
    private var stateLabel: XCUIElement { app.staticTexts.matching(identifier: "dashboard.state").firstMatch }

    private func waitForState(_ text: String, timeout: TimeInterval? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: stateLabel)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout ?? statusTimeout)
        XCTAssertEqual(result, .completed, "State is '\(stateLabel.label)', expected '\(text)'", file: file, line: line)
    }

    private func waitUntil(_ timeout: TimeInterval = 15, _ condition: () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            RunLoop.current.run(until: .now.addingTimeInterval(0.25))
        }
        return condition()
    }

    // MARK: - On and off

    /// Off: only the swipe lights the fire. On: one tap turns it off.
    func testSwipeToIgniteThenTapToTurnOff() throws {
        try launch(burning: false)
        waitForState("Off")
        XCTAssertFalse(app.switches["dashboard.wave"].exists, "Wave is only offered while the fire burns")

        let slider = app.descendants(matching: .any)["dashboard.ignite"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))

        // A short drag does nothing.
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)))
        RunLoop.current.run(until: .now.addingTimeInterval(1.5))
        XCTAssertFalse(bridge.writes.contains { $0.register == 40200 }, "A partial swipe must not light the fire")

        // The full swipe lights it.
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)))
        waitForState("Burning")
        XCTAssertEqual(bridge.writes.filter { $0.register == 40200 }.map(\.value), [101])

        let turnOff = app.buttons["dashboard.turnOff"]
        XCTAssertTrue(turnOff.waitForExistence(timeout: 5))
        turnOff.tap()
        waitForState("Off")
        XCTAssertEqual(bridge.writes.filter { $0.register == 40200 }.map(\.value), [101, 3])
    }

    // MARK: - Wave mode

    func testWaveModeToggleFollowsTheBridge() throws {
        try launch(burning: true)
        waitForState("Burning")

        let wave = app.switches["dashboard.wave"]
        XCTAssertTrue(wave.waitForExistence(timeout: 5))
        XCTAssertEqual(wave.value as? String, "0")

        // The switch sits at the trailing edge of the card; its label does not toggle.
        wave.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(waitUntil { self.bridge.waveMode }, "Wave mode was not sent")
        XCTAssertTrue(waitUntil { (wave.value as? String) == "1" }, "The toggle does not show wave mode")

        // Changed elsewhere (the remote or the DRU app): the toggle follows on the next read.
        bridge.setStatus(FakeDRUBridge.statusOn)
        // Pull to refresh on the controls (on an open Duo the middle of the
        // screen is the fold); polling would also catch it within a minute.
        let controls = app.scrollViews["dashboard.controlsPane"]
        (controls.exists ? controls : app.scrollViews.firstMatch).swipeDown()
        XCTAssertTrue(waitUntil(45) { (wave.value as? String) == "0" }, "The toggle did not follow the bridge")
    }

    // MARK: - Flame height

    func testFlameHeightIsSentOnceOnRelease() throws {
        try launch(burning: true)
        waitForState("Burning")

        let slider = app.sliders["dashboard.flameHeight"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.8)

        XCTAssertTrue(waitUntil(20) { self.bridge.writes.contains { $0.register == 40201 } },
                      "No flame height sent; slider shows \(slider.value as? String ?? "?")")
        let heights = bridge.writes.filter { $0.register == 40201 }.map(\.value)
        XCTAssertEqual(heights.count, 1, "One release sends one value: \(heights)")
        XCTAssertTrue((70...90).contains(heights[0]), "Unexpected flame height \(heights[0])")
    }

    // MARK: - Thermostat tucked away

    func testThermostatOpensFromTheQuietRow() throws {
        try launch(burning: true)
        waitForState("Burning")

        let row = app.buttons["dashboard.thermostat"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.steppers.firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: - Bridge problems

    func testUnreachableBridgeExplainsWhatToDo() throws {
        // Nothing listens on port 1: the connection is refused.
        try launch(startBridge: false)
        let error = app.descendants(matching: .any)["dashboard.error"]
        XCTAssertTrue(error.waitForExistence(timeout: statusTimeout), "No connection message shown")
        XCTAssertFalse(app.buttons["dashboard.turnOff"].exists)
    }
}
