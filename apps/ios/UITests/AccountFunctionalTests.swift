import XCTest
import CryptoKit

/// Normal navigation uses only a UUID-isolated store and the real owner login.
/// No remote email, password reset or account deletion is sent by these tests.
final class AccountFunctionalTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).executableURL)
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        print("MILO_LOADED_TEST_BUNDLE_SHA256=" + digest)
    }
    @MainActor private func launch(_ id: String, fixture: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-id", id]
        if let fixture { app.launchArguments += ["--parity-case", fixture] }
        app.launch(); return app
    }
    @MainActor private func tap(_ id: String, in app: XCUIApplication) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 10), id)
        for _ in 0..<8 { if button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.isHittable, id); button.tap()
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name
        image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"
        tree.lifetime = .keepAlways; add(tree)
    }
    @MainActor private func ownerLogin(_ app: XCUIApplication) {
        let email = app.textFields["login-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10)); email.tap(); email.typeText("milo")
        tap("login-submit", in: app)
        XCTAssertTrue(app.buttons["confirm-mood"].waitForExistence(timeout: 10))
    }
    @MainActor private func openAccount(_ app: XCUIApplication) {
        tap("open-account", in: app)
        XCTAssertTrue(app.buttons["account-export-json"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["account-ai-settings"].exists)
    }
    @MainActor func testFirstLaunchLoginModesAndPasswordVisibility() {
        let app = launch(UUID().uuidString)
        XCTAssertTrue(app.textFields["login-email"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["confirm-mood"].exists)
        capture("functional-login-first-launch", app)
        tap("login-mode-password", in: app)
        let password = app.secureTextFields["login-password"]
        XCTAssertTrue(password.exists); password.tap(); password.typeText("sample-password")
        tap("login-password-visibility", in: app)
        XCTAssertEqual(app.textFields["login-password"].value as? String, "sample-password")
        tap("login-password-visibility", in: app)
        XCTAssertTrue(app.secureTextFields["login-password"].exists)
        tap("login-forgot-password", in: app)
        XCTAssertTrue(app.staticTexts["找回密码"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["login-submit"].isEnabled)
        capture("functional-login-reset-entry", app)
        tap("back", in: app)
        tap("login-mode-code", in: app)
        ownerLogin(app)
        capture("functional-login-owner-home", app)
    }
    @MainActor func testPausedAIStaysHiddenThroughNormalNavigationRestartAndLogout() {
        let id = UUID().uuidString
        let app = launch(id); ownerLogin(app); openAccount(app)
        capture("functional-account-normal-entry", app)
        XCTAssertFalse(app.staticTexts["AI 与会员"].exists)
        XCTAssertTrue(app.buttons["account-export-markdown"].exists)
        tap("back", in: app)
        app.terminate(); app.launchArguments = ["--uitest-id", id]; app.launch()
        XCTAssertTrue(app.buttons["confirm-mood"].waitForExistence(timeout: 10))
        openAccount(app)
        tap("account-logout", in: app)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        XCTAssertFalse(app.buttons["account-ai-settings"].exists)
        XCTAssertTrue(app.buttons["account-export-json"].exists)
        tap("account-logout", in: app); app.alerts.buttons["退出登录"].tap()
        XCTAssertTrue(app.textFields["login-email"].waitForExistence(timeout: 10))
        capture("functional-logged-out", app)
        app.terminate(); app.launchArguments = ["--uitest-id", id]; app.launch()
        XCTAssertTrue(app.textFields["login-email"].waitForExistence(timeout: 10))
        ownerLogin(app); openAccount(app)
        XCTAssertFalse(app.switches["ai-enabled"].exists)
    }
    @MainActor func testRestoredAISettingsRouteOffersLocalRecordingOnly() {
        let app = launch(UUID().uuidString, fixture: "ai-settings--consent")
        XCTAssertTrue(app.staticTexts["AI 功能暂时下架"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["ai-test-connection"].exists)
        XCTAssertFalse(app.buttons["ai-save"].exists)
        XCTAssertFalse(app.secureTextFields["ai-api-key"].exists)
        XCTAssertFalse(app.staticTexts["MILO 星球会员"].exists)
        app.buttons["继续本地记录"].tap()
        XCTAssertTrue(app.buttons["confirm-mood"].waitForExistence(timeout: 10))
    }
    @MainActor func testEditingPasswordClearsPreviousFeedbackWithoutRemoteRequest() {
        // Explicit error fixtures only: no provider succeeds and no code is sent.
        for (fixture, identifier, secure) in [("password-error", "login-password", true), ("code-error", "login-code", false)] {
            let app = launch(UUID().uuidString, fixture: "login--" + fixture)
            XCTAssertTrue(app.staticTexts["login-error-message"].waitForExistence(timeout: 10))
            let field = secure ? app.secureTextFields[identifier] : app.textFields[identifier]
            XCTAssertTrue(field.exists); field.tap(); field.typeText("1")
            XCTAssertFalse(app.staticTexts["login-error-message"].exists)
            capture("functional-login-feedback-cleared-" + fixture, app)
            app.terminate()
        }
    }
}
