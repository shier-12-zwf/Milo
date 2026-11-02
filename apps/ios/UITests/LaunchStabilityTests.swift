import XCTest
import CryptoKit

/// Normal routes and owner login only. Each test uses a fresh UUID store;
/// no pre-authentication/parity fixture, remote email or production store writes.
final class LaunchStabilityTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let executable = try XCTUnwrap(Bundle(for: Self.self).executableURL)
        let digest = SHA256.hash(data: try Data(contentsOf: executable)).map { String(format: "%02x", $0) }.joined()
        print("MILO_LOADED_TEST_BUNDLE_SHA256=" + digest)
    }

    @MainActor private func isolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-id", UUID().uuidString]
        return app
    }

    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let accessibility = XCTAttachment(string: app.debugDescription)
        accessibility.name = name + "-accessibility"; accessibility.lifetime = .keepAlways; add(accessibility)
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

    @MainActor private func assertLogin(_ app: XCUIApplication) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.textFields["login-email"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["login-submit"].isHittable)
        XCTAssertFalse(app.buttons["confirm-mood"].exists)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.textFields["login-email"].isHittable)
    }

    @MainActor private func assertHome(_ app: XCUIApplication) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.buttons["confirm-mood"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["confirm-mood"].isHittable)
        XCTAssertFalse(app.textFields["login-email"].exists)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.buttons["confirm-mood"].isHittable)
    }

    @MainActor func testFiveCleanColdLaunchesShowLogin() {
        let app = isolatedApp()
        defer { app.terminate() }
        for launch in 1...5 {
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
            app.launch()
            assertLogin(app)
            capture("stability-login-cold-\(launch)", app)
        }
    }

    @MainActor func testOwnerSurvivesFiveColdLaunchesAndThreeBackgroundReturns() {
        let app = isolatedApp()
        defer { app.terminate() }
        app.launch(); assertLogin(app)
        let email = app.textFields["login-email"]
        email.tap(); email.typeText("milo")
        app.buttons["login-submit"].tap()
        assertHome(app)
        capture("stability-owner-normal-login", app)
        for launch in 1...5 {
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
            app.launch()
            assertHome(app)
            capture("stability-owner-cold-\(launch)", app)
        }

        let account = app.buttons["open-account"]
        XCTAssertTrue(account.isHittable); account.tap()
        let settings = app.buttons["account-ai-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        let enabled = app.switches["ai-enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 10))
        let initialValue = enabled.value as? String
        for cycle in 1...3 {
            let backgroundObserver = enterVerifiedBackground(app, name: "stability-background-\(cycle)")
            // Keep the existing UUID-isolated process alive; activation must not
            // start an ordinary no-argument process against the user's store.
            Thread.sleep(forTimeInterval: 1)
            XCTAssertTrue(backgroundObserver.state == .runningBackground || backgroundObserver.state == .runningBackgroundSuspended)
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            XCTAssertTrue(enabled.waitForExistence(timeout: 10), "Must remain on AI settings after background cycle \(cycle)")
            XCTAssertEqual(enabled.value as? String, initialValue)
            XCTAssertFalse(app.textFields["login-email"].exists)
            capture("stability-settings-background-\(cycle)", app)
        }

        app.buttons["back"].tap()
        XCTAssertTrue(app.buttons["account-ai-settings"].waitForExistence(timeout: 5))
        app.buttons["back"].tap(); assertHome(app)
        let iconObserver = enterVerifiedBackground(app, name: "stability-icon-entry-background")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["MILO"].firstMatch
        // Return via the real icon only while the test process remains alive.
        // Cold no-argument icon launches would select the user's normal store.
        XCTAssertTrue(icon.waitForExistence(timeout: 10))
        XCTAssertTrue(icon.isHittable)
        XCTAssertTrue(iconObserver.state == .runningBackground || iconObserver.state == .runningBackgroundSuspended)
        capture("stability-springboard-icon", springboard)
        icon.tap()
        assertHome(app)
        capture("stability-home-via-springboard-icon", app)
    }
}
