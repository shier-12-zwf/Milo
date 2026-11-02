import XCTest

/// Motion fixtures bypass only the static screenshot clock. Reduce Motion is
/// changed in Settings so these tests exercise SwiftUI's real environment.
final class GalaxyMotionTests: XCTestCase {
    override func setUp() { continueAfterFailure = false; recordTestBundleProvenance(Self.self) }

    @MainActor private func launch(caseID: String = "home--mood-calm") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-id", UUID().uuidString, "--parity-case", caseID, "--motion-test"]
        app.launch()
        XCTAssertTrue(parityProbe("galaxy-motion", in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(parityValues("galaxy-motion", in: app)["renderReady"] ?? -1, 1)
        return app
    }

    @MainActor private func frame(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        let data = XCTAttachment(string: parityProbe("galaxy-motion", in: app).value as? String ?? "missing")
        data.name = name + "-clock"; data.lifetime = .keepAlways; add(data)
    }

    /// Home is visibly delivered in the source recordings, but polling state
    /// with Thread.sleep on MainActor failed to observe the async state change.
    /// Synchronize with SpringBoard and use XCTest's event-pumping public wait
    /// on a separate observer; never infer background from a Home command alone.
    @MainActor private func enterVerifiedBackground(_ app: XCUIApplication, name: String) -> XCUIApplication {
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()
        let desktopVisible = springboard.wait(for: .runningForeground, timeout: 10)
        let icon = springboard.icons["MILO"].firstMatch
        let iconExists = icon.waitForExistence(timeout: 5)
        let observer = XCUIApplication(bundleIdentifier: "com.milo.echoes.ios")
        let background = observer.wait(for: .runningBackground, timeout: 5)
            || observer.wait(for: .runningBackgroundSuspended, timeout: 5)
        // Preserve evidence before any assertion aborts the test.
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name + "-desktop"; image.lifetime = .keepAlways; add(image)
        let state = XCTAttachment(string: "original=\(app.state.rawValue), observer=\(observer.state.rawValue), springboard=\(springboard.state.rawValue), iconExists=\(iconExists), iconHittable=\(icon.isHittable)")
        state.name = name + "-states"; state.lifetime = .keepAlways; add(state)
        XCTAssertTrue(desktopVisible, "SpringBoard must actually be foreground")
        XCTAssertTrue(iconExists && icon.isHittable, "The real desktop MILO icon must be visible and hittable")
        XCTAssertTrue(background, "MILO must actually be running in background or suspended, not terminated")
        return observer
    }

    @MainActor private func hold(_ name: String, in app: XCUIApplication, action: () -> Void) {
        let before = parityValues("galaxy-motion", in: app)
        frame(name + "-before", app)
        let start = Date().timeIntervalSince1970
        action()
        let end = Date().timeIntervalSince1970
        let after = parityValues("galaxy-motion", in: app)
        frame(name + "-after", app)
        let metadata: [String: Any] = [
            "gesture": name, "commandStartUnixSeconds": start,
            "commandEndUnixSeconds": end, "requestedHoldSeconds": 0.8,
            "actualTouchDurationSeconds": after["touchDuration"] ?? -1,
            "actualTouchPeakActive": after["touchPeakActive"] ?? -1,
            "actualTouchSequence": after["touchSequence"] ?? -1,
            "evidence": "Extract during-hold frames from the original source-bound simulator video; these screenshots are before and after release."
        ]
        let json = try! JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: json, uniformTypeIdentifier: "public.json")
        attachment.name = name + "-gesture-timing"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(after["touchSequence"] ?? -1, (before["touchSequence"] ?? -2) + 1,
                       "One physical press must be observed exactly once")
        XCTAssertGreaterThan(after["touchDuration"] ?? -1, 0.5, "The real touch must stay down for at least half a second")
        XCTAssertGreaterThan(after["touchPeakActive"] ?? -1, 0.3, "Live touch must actually deform the shader")
    }

    @MainActor func testLiveTouchNavigationAndResume() throws {
        let settings = try openMotionSettings()
        let original = try reduceMotionIsOn(settings)
        registerSystemSettingRestoration(original, settings: settings)
        try setReduceMotion(false, in: settings)
        attachSettings("motion-system-setting-off", settings)
        let app = launch()
        defer { app.terminate() }
        XCTAssertEqual(parityValues("galaxy-motion", in: app)["paused"] ?? -1, 0)
        let before = parityValues("galaxy-motion", in: app)["time"] ?? -1
        frame("motion-natural-0", app)
        Thread.sleep(forTimeInterval: 1)
        frame("motion-natural-1", app)
        Thread.sleep(forTimeInterval: 1)
        frame("motion-natural-2", app)
        XCTAssertGreaterThan(parityValues("galaxy-motion", in: app)["time"] ?? -1, before + 1)

        let blank = app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.8))
        hold("motion-blank", in: app) { blank.press(forDuration: 0.8) }
        Thread.sleep(forTimeInterval: 1)
        XCTAssertLessThan(parityValues("galaxy-motion", in: app)["active"] ?? 1, 0.02)
        frame("motion-blank-recovered", app)

        let mood = app.buttons["mood-bright"]
        XCTAssertTrue(mood.isHittable)
        hold("motion-mood-change", in: app) { mood.press(forDuration: 0.8) }
        XCTAssertTrue(mood.isSelected)
        XCTAssertFalse(app.buttons["mood-calm"].isSelected)
        frame("motion-mood-selected", app)

        let confirm = app.buttons["confirm-mood"]
        XCTAssertTrue(confirm.isHittable)
        hold("motion-control", in: app) { confirm.press(forDuration: 0.8) }
        XCTAssertTrue(app.buttons["confirm-words"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["confirm-mood"].exists)
        frame("motion-control-navigated-once", app)

        let prior = parityValues("galaxy-motion", in: app)
        let backgroundObserver = enterVerifiedBackground(app, name: "motion-actual-background")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let homeImage = XCTAttachment(screenshot: springboard.screenshot())
        homeImage.name = "motion-actual-background"; homeImage.lifetime = .keepAlways; add(homeImage)
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertTrue(backgroundObserver.state == .runningBackground || backgroundObserver.state == .runningBackgroundSuspended,
                      "MILO must remain alive in the background for the entire pause interval")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        // activate() returned before the transition finished on iOS 26.5. AX
        // can return the old snapshot while SpringBoard is still on screen.
        let resumed = waitForResume(after: prior, in: app)
        frame("motion-fresh-resume-state", app)
        XCTAssertEqual(resumed["clockInstance"] ?? -1, prior["clockInstance"] ?? -2)
        XCTAssertEqual(resumed["applicationState"] ?? -1, 0)
        XCTAssertGreaterThan(resumed["inactiveDuration"] ?? -1, (prior["inactiveDuration"] ?? 0) + 2)
        XCTAssertGreaterThan(resumed["pauseCount"] ?? -1, prior["pauseCount"] ?? 0)
        XCTAssertGreaterThan(resumed["resumeCount"] ?? -1, prior["resumeCount"] ?? 0)
        XCTAssertGreaterThan(resumed["pauseTime"] ?? -1, 0)
        XCTAssertEqual(resumed["resumeTime"] ?? -1, resumed["pauseTime"] ?? -2, accuracy: 0.000001,
                       "Animation time must be identical at pause and resume, before the first resumed frame")
        XCTAssertGreaterThanOrEqual(resumed["time"] ?? -1, resumed["resumeTime"] ?? 0)
        frame("motion-resumed", app)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertGreaterThan(parityValues("galaxy-motion", in: app)["time"] ?? -1, (resumed["time"] ?? 0) + 0.3)
        frame("motion-resumed-advancing", app)
        app.terminate()
        verifyLiveScrollAndInput()
    }

    @MainActor func testReducedMotionKeepsControlsUsable() throws {
        let settings = try openMotionSettings()
        let original = try reduceMotionIsOn(settings)
        registerSystemSettingRestoration(original, settings: settings)
        try setReduceMotion(true, in: settings)
        attachSettings("motion-system-setting-on", settings)
        let app = launch()
        defer { app.terminate() }
        XCTAssertEqual(parityValues("galaxy-motion", in: app)["paused"] ?? -1, 1,
                       "The actual system Reduce Motion setting must reach SwiftUI")
        let before = parityValues("galaxy-motion", in: app)["time"] ?? -1
        frame("motion-reduced-before", app)
        Thread.sleep(forTimeInterval: 1.2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.8)).press(forDuration: 0.8)
        XCTAssertEqual(parityValues("galaxy-motion", in: app)["time"] ?? -2, before, accuracy: 0.001)
        XCTAssertEqual(parityValues("galaxy-motion", in: app)["active"] ?? -1, 0)
        let mood = app.buttons["mood-bright"]
        XCTAssertTrue(mood.isHittable)
        mood.tap()
        XCTAssertTrue(mood.isSelected)
        frame("motion-reduced-mood-selected", app)
        app.buttons["confirm-mood"].tap()
        XCTAssertTrue(app.buttons["confirm-words"].waitForExistence(timeout: 5))
        XCTAssertEqual(parityValues("galaxy-motion", in: app)["time"] ?? -2, before, accuracy: 0.001)
        XCTAssertEqual(parityValues("galaxy-motion", in: app)["active"] ?? -1, 0)
        frame("motion-reduced-after", app)
    }

    @MainActor private func waitForResume(after prior: [String: Double], in app: XCUIApplication) -> [String: Double] {
        let deadline = Date().addingTimeInterval(10)
        var value = parityValues("galaxy-motion", in: app)
        while Date() < deadline {
            if (value["resumeCount"] ?? -1) > (prior["resumeCount"] ?? 0), value["paused"] == 0 { return value }
            Thread.sleep(forTimeInterval: 0.1)
            value = parityValues("galaxy-motion", in: app)
        }
        frame("motion-resume-timeout", app)
        XCTFail("No new resume event; cannot use cached accessibility data as lifecycle evidence")
        return value
    }

    @MainActor private func verifyLiveScrollAndInput() {
        let diary = launch(caseID: "diary--long")
        let before = parityViewport("parity-scroll-journey-diary", in: diary)
        let clock = parityValues("galaxy-motion", in: diary)
        XCTAssertGreaterThan(before.maxOffset, 200)
        frame("motion-long-page-before-drag", diary)
        parityDrag(before.frame, downward: false, in: diary, edge: true)
        let after = parityViewport("parity-scroll-journey-diary", in: diary)
        XCTAssertGreaterThan(after.offset, before.offset + 50, "The passive touch observer must not consume scrolling")
        XCTAssertGreaterThan(parityValues("galaxy-motion", in: diary)["time"] ?? -1, clock["time"] ?? 0)
        frame("motion-long-page-after-drag", diary)
        let offsetEvidence = XCTAttachment(string: "{\"beforeOffset\":\(before.offset),\"afterOffset\":\(after.offset),\"contentHeight\":\(after.contentHeight)}")
        offsetEvidence.name = "motion-live-scroll-measurement"; offsetEvidence.lifetime = .keepAlways; add(offsetEvidence)
        diary.terminate()

        let note = launch(caseID: "now-note--empty")
        defer { note.terminate() }
        let field = parityProbe("note-input", in: note)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(note.keyboards.firstMatch.waitForExistence(timeout: 5))
        parityAssertKeyboardVisible(in: note)
        let inputClock = parityValues("galaxy-motion", in: note)["time"] ?? -1
        field.typeText("Live stars keep typing usable.")
        XCTAssertTrue((field.value as? String ?? "").contains("Live stars keep typing usable."))
        XCTAssertGreaterThan(parityValues("galaxy-motion", in: note)["time"] ?? -1, inputClock)
        XCTAssertTrue(note.buttons["save-now"].isHittable)
        frame("motion-live-text-entry", note)
    }

    @MainActor private func registerSystemSettingRestoration(_ original: Bool, settings: XCUIApplication) {
        // XCTest aborts a test on the first assertion and can skip Swift defer.
        // Its registered async teardown still restores the actual device state.
        addTeardownBlock { @MainActor [settings] () async throws in
            await Task.yield()
            settings.activate()
            let control = settings.switches.matching(NSPredicate(format: "label IN %@", ["Reduce Motion", "减弱动态效果", "减少动态效果"])).firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5), "Restoration requires the real Motion settings page")
            let wanted = original ? "1" : "0"
            if control.value as? String != wanted {
                control.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5)).tap()
                let deadline = Date().addingTimeInterval(5)
                while Date() < deadline, control.value as? String != wanted { try await Task.sleep(for: .milliseconds(100)) }
            }
            XCTAssertEqual(control.value as? String, wanted, "Restore the prior Reduce Motion setting even after failure")
            XCTContext.runActivity(named: "Restore original system Reduce Motion setting") { activity in
                let image = XCTAttachment(screenshot: settings.screenshot())
                image.name = "motion-system-setting-restored"; image.lifetime = .keepAlways
                activity.add(image)
            }
            settings.terminate()
        }
    }

    @MainActor private func reduceMotionSwitch(_ settings: XCUIApplication) -> XCUIElement {
        settings.switches.matching(NSPredicate(format: "label IN %@", ["Reduce Motion", "减弱动态效果", "减少动态效果"])).firstMatch
    }

    @MainActor private func settingsText(_ labels: [String], _ settings: XCUIApplication) -> XCUIElement {
        settings.staticTexts.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    @MainActor private func openMotionSettings() throws -> XCUIApplication {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        if reduceMotionSwitch(settings).waitForExistence(timeout: 2) { return settings }
        // Settings may resume an already-open subsection. Navigate using public
        // back buttons, never private preference URLs or preference-file writes.
        let motionLabels = ["Motion", "动态效果", "动作"]
        for _ in 0..<5 {
            if reduceMotionSwitch(settings).exists { return settings }
            let motion = settingsText(motionLabels, settings)
            if motion.exists && motion.isHittable {
                motion.tap()
                if reduceMotionSwitch(settings).waitForExistence(timeout: 5) { return settings }
            }
            let back = settings.navigationBars.buttons.matching(NSPredicate(
                format: "label IN %@", ["Settings", "设置", "Accessibility", "辅助功能", "Back", "返回"])).firstMatch
            if back.exists && back.isHittable { back.tap() } else { break }
        }
        try tapSettingsRow(["Accessibility", "辅助功能"], in: settings)
        try tapSettingsRow(motionLabels, in: settings)
        _ = try XCTUnwrap(reduceMotionSwitch(settings).waitForExistence(timeout: 5) ? settings : nil,
                          "Cannot reach the real Reduce Motion switch in Settings")
        return settings
    }

    @MainActor private func tapSettingsRow(_ labels: [String], in settings: XCUIApplication) throws {
        for scrollUp in [true, false] {
            for _ in 0..<8 {
                let row = settingsText(labels, settings)
                if row.exists && row.isHittable { row.tap(); return }
                if scrollUp { settings.swipeUp() } else { settings.swipeDown() }
            }
        }
        XCTFail("Settings row unavailable: \(labels.joined(separator: ", "))")
        throw NSError(domain: "GalaxyMotionTests", code: 1)
    }

    @MainActor private func reduceMotionIsOn(_ settings: XCUIApplication) throws -> Bool {
        let control = reduceMotionSwitch(settings)
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        let value = try XCTUnwrap(control.value as? String, "Missing system switch value")
        XCTAssertTrue(value == "0" || value == "1", "Unrecognized system switch value: \(value)")
        return value == "1"
    }

    @MainActor private func setReduceMotion(_ enabled: Bool, in settings: XCUIApplication) throws {
        if try reduceMotionIsOn(settings) != enabled {
            let control = reduceMotionSwitch(settings)
            XCTAssertTrue(control.isHittable)
            attachSettings("motion-system-before-switch", settings)
            let description = XCTAttachment(string: control.debugDescription)
            description.name = "motion-system-switch-frame"; description.lifetime = .keepAlways; add(description)
            // iOS 26 exposes the entire 358pt row as a switch. Its center is
            // empty text space (observed x195,y145); the actual control is at
            // the trailing edge (observed x330,y145). Tap the switch itself.
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5)).tap()
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if try reduceMotionIsOn(settings) == enabled { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            attachSettings("motion-system-after-switch", settings)
        }
        XCTAssertEqual(try reduceMotionIsOn(settings), enabled)
    }

    @MainActor private func attachSettings(_ name: String, _ settings: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: settings.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
