import XCTest

final class SpeechInputUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false; recordTestBundleProvenance(Self.self) }

    @MainActor private func chat() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-id", UUID().uuidString, "--parity-case", "chat--keyboard"]
        app.launch()
        XCTAssertTrue(app.buttons["speech-input"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let state = XCTAttachment(string: app.debugDescription); state.name = name + "-state"; state.lifetime = .keepAlways; add(state)
    }
    @MainActor private func acceptAlert(_ alert: XCUIElement, deny: Bool = false) {
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let labels = deny ? ["Don't Allow", "不允许"] : ["Allow", "允许", "OK", "好"]
        guard let button = labels.map({ alert.buttons[$0] }).first(where: { $0.exists }) else {
            XCTFail("Actual permission alert needs a known explicit action: \(alert.debugDescription)"); return
        }
        button.tap()
    }
    @MainActor private func start(_ app: XCUIApplication, denyMicrophone: Bool = false) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.buttons["speech-input"].tap()
        // Speech may already be authorized; microphone was explicitly reset.
        for _ in 0..<2 {
            let alert = springboard.alerts.firstMatch
            if !alert.waitForExistence(timeout: 3) { break }
            let text = alert.label + alert.staticTexts.allElementsBoundByIndex.map(\.label).joined()
            let mic = text.localizedCaseInsensitiveContains("microphone") || text.contains("麦克风")
            capture(mic ? "speech-microphone-prompt" : "speech-recognition-prompt", app)
            let prompt = XCTAttachment(string: alert.debugDescription)
            prompt.name = "speech-actual-permission-alert"; prompt.lifetime = .keepAlways; add(prompt)
            if mic {
                XCTAssertEqual(app.buttons["speech-input"].value as? String, "starting")
                XCTAssertFalse(app.textFields["chat-input"].isEnabled, "Pending authorization must not permit edits that a stale prefix could overwrite")
            }
            acceptAlert(alert, deny: mic && denyMicrophone)
        }
        let settled = NSPredicate { _, _ in
            app.state == .runningForeground && (app.buttons["speech-input"].value as? String) != "starting"
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 15), .completed)
        XCTAssertEqual(app.state, .runningForeground)
    }
    @MainActor private func assertFallbackOrStop(_ app: XCUIApplication) {
        let button = app.buttons["speech-input"]
        if (button.value as? String) == "recording" {
            capture("speech-native-recording", app); button.tap()
        } else {
            XCTAssertTrue(app.staticTexts["speech-error"].exists, "A failed native start must explain keyboard fallback")
            capture("speech-native-unavailable", app)
        }
        XCTAssertEqual(button.value as? String, "idle")
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor func testAMicrophoneRefusalPreservesTextAndKeyboard() {
        let app = chat(); app.terminate(); app.resetAuthorizationStatus(for: .microphone); app.launch()
        start(app, denyMicrophone: true)
        XCTAssertTrue(app.staticTexts["speech-error"].label.contains("麦克风权限"))
        let field = app.textFields["chat-input"]
        XCTAssertTrue((field.value as? String)?.contains("今天慢慢走") == true)
        field.tap(); field.typeText(" 拒绝后还可以输入")
        XCTAssertTrue((field.value as? String)?.contains("拒绝后还可以输入") == true)
        app.buttons["chat-editor-done"].tap()
        XCTAssertTrue(app.buttons["send-message"].isEnabled)
        capture("speech-mic-denied-keyboard-retained", app)
        app.buttons["send-message"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "拒绝后还可以输入")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground); app.terminate()
    }

    @MainActor func testBRepeatedNativeVoiceAndBackgroundReturn() {
        let app = chat(); app.terminate(); app.resetAuthorizationStatus(for: .microphone); app.launch()
        for cycle in 1...3 {
            start(app); assertFallbackOrStop(app)
            capture("speech-real-entry-cycle-\(cycle)", app)
        }
        start(app)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 5))
        let observer = XCUIApplication(bundleIdentifier: "com.milo.echoes.ios")
        XCTAssertTrue(observer.wait(for: .runningBackground, timeout: 5) || observer.wait(for: .runningBackgroundSuspended, timeout: 5))
        app.activate()
        XCTAssertTrue(app.buttons["speech-input"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["speech-input"].value as? String, "idle")
        XCTAssertEqual(app.state, .runningForeground)
        capture("speech-background-return-idle", app)
        let field = app.textFields["chat-input"]
        XCTAssertTrue((field.value as? String)?.contains("今天慢慢走") == true)
        field.tap(); field.typeText(" 回来后可输入")
        XCTAssertTrue((field.value as? String)?.contains("回来后可输入") == true)
        app.buttons["chat-editor-done"].tap()
        app.buttons["send-message"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "回来后可输入")).firstMatch.waitForExistence(timeout: 10))
        app.terminate()
    }

    @MainActor func testCVisibleKeyboardAppendAndSend() {
        let app = chat()
        let field = app.textFields["chat-input"]
        XCTAssertTrue((field.value as? String)?.contains("今天慢慢走") == true)
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Screen keyboard must actually appear")
        XCTAssertTrue(app.keyboards.firstMatch.isHittable)
        field.typeText(" 键盘实际可见")
        XCTAssertTrue((field.value as? String)?.contains("今天慢慢走") == true)
        XCTAssertTrue((field.value as? String)?.contains("键盘实际可见") == true)
        capture("input-visible-keyboard-and-retained-draft", app)
        app.buttons["chat-editor-done"].tap()
        app.buttons["send-message"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "键盘实际可见")).firstMatch.waitForExistence(timeout: 10))
        app.terminate()
    }

    @MainActor func testDRealRecordingRemainsActive() {
        let app = chat()
        start(app)
        let button = app.buttons["speech-input"]
        capture("input-actual-speech-start-result", app)
        XCTAssertEqual(button.value as? String, "recording", "A fallback error is not usable speech")
        for _ in 0..<5 {
            let idle = NSPredicate(format: "value == %@", "idle")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: idle, object: button)], timeout: 1), .timedOut,
                           "Real recording must remain active, not return a service error")
            XCTAssertEqual(button.value as? String, "recording")
        }
        capture("input-actual-speech-five-seconds", app)
        button.tap()
        XCTAssertEqual(button.value as? String, "idle")
        app.terminate()
    }
}
