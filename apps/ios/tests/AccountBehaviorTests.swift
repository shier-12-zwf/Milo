import XCTest
import CryptoKit
@testable import Milo

@MainActor private final class ControlledAuth: MiloAuthProvider {
    let isConfigured = true
    var user = AccountIdentity(uid: "test-user", email: "person@example.com", provider: .agc)
    var calls: [String] = []
    var failSignIn = false
    var failReset = false
    var failSignOut = false
    var failDelete = false
    func restoreSession() async throws -> AccountIdentity? { user }
    func sendCode(email: String, purpose: VerificationPurpose) async throws { calls.append("code:\(email):\(purpose.rawValue)") }
    func signIn(email: String, code: String) async throws -> AccountIdentity {
        calls.append("verify:\(email)")
        if failSignIn { throw AccountFailure.message("验证码无效。") }
        return user
    }
    func signIn(email: String, password: String) async throws -> AccountIdentity {
        calls.append("password:\(email)")
        if failSignIn { throw AccountFailure.message("登录暂时失败。") }
        return user
    }
    func resetPassword(email: String, code: String, password: String) async throws {
        calls.append("reset:\(email)")
        if failReset { throw AccountFailure.message("验证码已失效。") }
    }
    func changePassword(email: String, code: String, password: String) async throws { calls.append("change:\(email)") }
    func signOut() async throws {
        calls.append("logout")
        if failSignOut { throw URLError(.notConnectedToInternet) }
    }
    func deleteAccount() async throws {
        calls.append("delete")
        if failDelete { throw AccountFailure.message("请重新登录后注销。") }
    }
}

@MainActor final class AccountBehaviorTests: XCTestCase {
    private struct Fixture {
        let directory: URL
        let provider: ControlledAuth
        let model: AccountModel
        func clean() { try? FileManager.default.removeItem(at: directory) }
    }
    private func fixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MILO-AccountTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let provider = ControlledAuth()
        return Fixture(directory: directory, provider: provider, model: AccountModel(directory: directory, authProvider: provider))
    }
    private func login(_ f: Fixture) async -> Bool { await f.model.signIn(email: "person@example.com", password: "test-password") }

    func testProductPauseOverridesEverySavedConfigurationWithoutReadingKeysOrRequestingModel() throws {
        XCTAssertTrue(AppStorage.directory.path.contains("/MILO-UITests/"), "native unit-test host must never initialize the production journal store")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MILO-UITests").appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AccountModel(directory: directory, authProvider: ControlledAuth())
        XCTAssertFalse(AIFeaturePolicy.isAvailable)
        XCTAssertEqual(model.aiUnavailableReason, AIFeaturePolicy.pausedMessage)
        model.configureFixture(state: "personal")
        XCTAssertEqual(model.aiUnavailableReason, AIFeaturePolicy.pausedMessage)
        model.configureFixture(state: "consent")
        XCTAssertEqual(model.aiUnavailableReason, AIFeaturePolicy.pausedMessage)
        let name = Data("milo-local-owner".utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        var settings = PersonalAISettings(); settings.source = .personal; settings.consent = true
        for provider in AIProvider.allCases {
            settings.provider = provider; settings.baseURL = provider.baseURL; settings.model = provider.model
            try JSONEncoder().encode(settings).write(to: directory.appendingPathComponent("ai-\(name).json"))
            model.configureFixture()
            XCTAssertEqual(model.aiUnavailableReason, AIFeaturePolicy.pausedMessage)
            XCTAssertEqual(model.aiSettings, settings, "pause must not erase the saved provider or consent")
        }
        settings.enabled = false
        try JSONEncoder().encode(settings).write(to: directory.appendingPathComponent("ai-\(name).json"))
        model.configureFixture()
        XCTAssertEqual(model.aiUnavailableReason, AIFeaturePolicy.pausedMessage)
    }

    func testPausedAccountCompletionAndConnectionTestStopBeforeCredentials() async throws {
        let f = try fixture(); defer { f.clean() }
        // No identity or key exists: the product pause must win even before the
        // login/configuration/Keychain preflight.
        do {
            _ = try await f.model.completeAI(messages: [AIMessage(role: .user, content: "synthetic pause check")])
            XCTFail("Paused completion must not succeed")
        } catch { XCTAssertEqual(error.localizedDescription, AIFeaturePolicy.pausedMessage) }
        await f.model.testConnection(settings: PersonalAISettings(), newKey: "")
        XCTAssertEqual(f.model.errorMessage, AIFeaturePolicy.pausedMessage)
        XCTAssertFalse(f.model.isBusy)
        XCTAssertTrue(f.model.statusMessage.isEmpty)
        XCTAssertTrue(f.provider.calls.isEmpty)
    }

    func testFirstLaunchRequiresLoginAndOwnerSessionRestores() throws {
        let f = try fixture(); defer { f.clean() }
        XCTAssertFalse(f.model.isAuthenticated)
        XCTAssertTrue(f.model.signInLocally())
        let restored = AccountModel(directory: f.directory, authProvider: f.provider)
        XCTAssertTrue(restored.isLocalAccount)
        XCTAssertEqual(f.provider.calls, [])
    }
    func testPasswordLoginPersistsIdentityWithoutPassword() async throws {
        let f = try fixture(); defer { f.clean() }
        let success = await f.model.signIn(email: " person@example.com ", password: "test-password")
        XCTAssertTrue(success)
        XCTAssertEqual(f.provider.calls, ["password:person@example.com"])
        let raw = try String(contentsOf: f.directory.appendingPathComponent("account.json"), encoding: .utf8)
        XCTAssertFalse(raw.contains("test-password"))
        XCTAssertEqual(AccountModel(directory: f.directory, authProvider: f.provider).identity, f.provider.user)
    }
    func testCodeCooldownIsBoundToNormalizedEmailAndPurpose() async throws {
        let f = try fixture(); defer { f.clean() }
        let first = await f.model.requestCode(email: "person@example.com", purpose: .signIn)
        let repeatRequest = await f.model.requestCode(email: " PERSON@example.com ", purpose: .signIn)
        let reset = await f.model.requestCode(email: "person@example.com", purpose: .resetPassword)
        XCTAssertTrue(first && repeatRequest && reset)
        XCTAssertEqual(f.provider.calls.count, 2)
        XCTAssertGreaterThan(f.model.resendSeconds(email: "person@example.com", purpose: .signIn), 0)
        XCTAssertEqual(f.model.resendSeconds(email: "other@example.com", purpose: .signIn), 0)
    }
    func testFailedCodeDoesNotCreateSessionOrAlterMemories() async throws {
        let f = try fixture(); defer { f.clean() }
        let saved = Data("existing-memory".utf8)
        let url = f.directory.appendingPathComponent("journal.json")
        try saved.write(to: url); f.provider.failSignIn = true
        let success = await f.model.signIn(email: "person@example.com", code: "123456")
        XCTAssertFalse(success); XCTAssertFalse(f.model.isAuthenticated)
        XCTAssertEqual(try Data(contentsOf: url), saved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.directory.appendingPathComponent("account.json").path))
    }
    func testResetThenPasswordLoginUsesTwoDistinctOperations() async throws {
        let f = try fixture(); defer { f.clean() }
        let success = await f.model.resetPassword(email: " person@example.com ", code: "123456", password: "new-password")
        XCTAssertTrue(success)
        XCTAssertEqual(f.provider.calls, ["reset:person@example.com", "password:person@example.com"])
        XCTAssertFalse(f.model.passwordResetRequiresSignIn)
    }
    func testFailedResetNeverAttemptsPasswordLogin() async throws {
        let f = try fixture(); defer { f.clean() }; f.provider.failReset = true
        let success = await f.model.resetPassword(email: "person@example.com", code: "123456", password: "new-password")
        XCTAssertFalse(success); XCTAssertFalse(f.model.passwordResetRequiresSignIn)
        XCTAssertEqual(f.provider.calls, ["reset:person@example.com"])
    }
    func testResetPartialSuccessCanRetryWithoutReusingCode() async throws {
        let f = try fixture(); defer { f.clean() }; f.provider.failSignIn = true
        let reset = await f.model.resetPassword(email: "person@example.com", code: "123456", password: "new-password")
        XCTAssertFalse(reset); XCTAssertTrue(f.model.passwordResetRequiresSignIn)
        XCTAssertTrue(f.model.errorMessage.contains("密码已更新"))
        f.provider.failSignIn = false
        let retry = await f.model.signIn(email: "person@example.com", password: "new-password")
        XCTAssertTrue(retry); XCTAssertFalse(f.model.passwordResetRequiresSignIn)
        XCTAssertEqual(f.provider.calls.filter { $0.hasPrefix("reset:") }.count, 1)
    }
    func testOfflineRemoteLogoutStillClearsLocalSessionAndKeepsData() async throws {
        let f = try fixture(); defer { f.clean() }; let signedIn = await login(f); XCTAssertTrue(signedIn)
        var settings = PersonalAISettings(); settings.enabled = false
        XCTAssertTrue(f.model.saveAISettings(settings, newKey: ""))
        for name in ["journal.json", "draft.json"] { try Data(name.utf8).write(to: f.directory.appendingPathComponent(name)) }
        f.provider.failSignOut = true
        let success = await f.model.signOut()
        XCTAssertTrue(success); XCTAssertFalse(f.model.isAuthenticated)
        XCTAssertFalse(AccountModel(directory: f.directory, authProvider: f.provider).isAuthenticated)
        for name in ["journal.json", "draft.json"] { XCTAssertEqual(try Data(contentsOf: f.directory.appendingPathComponent(name)), Data(name.utf8)) }
        let again = await login(f); XCTAssertTrue(again); XCTAssertFalse(f.model.aiSettings.enabled)
    }
    func testRemoteDeleteFailureNeverCallsLocalDeletion() async throws {
        let f = try fixture(); defer { f.clean() }; let signedIn = await login(f); XCTAssertTrue(signedIn)
        f.provider.failDelete = true; var localDeleted = false
        let success = await f.model.deleteAccount { localDeleted = true; return true }
        XCTAssertFalse(success); XCTAssertFalse(localDeleted); XCTAssertTrue(f.model.isAuthenticated)
    }
    func testLocalDeleteFailureRetainsIdentityForRetry() async throws {
        let f = try fixture(); defer { f.clean() }; XCTAssertTrue(f.model.signInLocally())
        let success = await f.model.deleteAccount { false }
        XCTAssertFalse(success); XCTAssertTrue(f.model.isAuthenticated)
    }
    func testPasswordConfirmationIsCheckedBeforeProviderAndSessionRemains() async throws {
        let f = try fixture(); defer { f.clean() }; let signedIn = await login(f); XCTAssertTrue(signedIn)
        let invalid = await f.model.changePassword(code: "123456", password: "new-password", confirmation: "different")
        XCTAssertFalse(invalid); XCTAssertEqual(f.provider.calls.count, 1)
        let valid = await f.model.changePassword(code: "123456", password: "new-password", confirmation: "new-password")
        XCTAssertTrue(valid); XCTAssertEqual(f.model.identity, f.provider.user)
        XCTAssertEqual(f.provider.calls.last, "change:person@example.com")
    }
    func testPreferencesAreScopedToAccountAcrossSwitches() async throws {
        let f = try fixture(); defer { f.clean() }; let first = await login(f); XCTAssertTrue(first)
        var settings = PersonalAISettings(); settings.enabled = false
        XCTAssertTrue(f.model.saveAISettings(settings, newKey: ""))
        let original = f.provider.user
        f.provider.user = AccountIdentity(uid: "second-user", email: "second@example.com", provider: .agc)
        let second = await login(f); XCTAssertTrue(second); XCTAssertTrue(f.model.aiSettings.enabled)
        f.provider.user = original
        let returning = await login(f); XCTAssertTrue(returning); XCTAssertFalse(f.model.aiSettings.enabled)
    }
    func testUnavailableProviderDoesNotManufactureRemoteIdentity() async throws {
        let f = try fixture(); defer { f.clean() }
        let model = AccountModel(directory: f.directory, authProvider: UnconfiguredAGCAuthProvider())
        let success = await model.signIn(email: "person@example.com", code: "123456")
        XCTAssertFalse(success); XCTAssertFalse(model.isAuthenticated); XCTAssertFalse(model.remoteAuthConfigured)
        XCTAssertFalse(model.errorMessage.isEmpty)
    }
    func testAGCConfigurationRejectsMissingMalformedAndWrongBundleWithoutStartup() throws {
        XCTAssertNil(AGCAuthProvider.configuration(from: Data(), bundleIdentifier: "com.milo.echoes.ios"))
        let wrong = try PropertyListSerialization.data(fromPropertyList: ["client": ["package_name": "com.other.app"]], format: .xml, options: 0)
        XCTAssertNil(AGCAuthProvider.configuration(from: wrong, bundleIdentifier: "com.milo.echoes.ios"))
        let incomplete = try PropertyListSerialization.data(fromPropertyList: ["client": ["package_name": "com.milo.echoes.ios"]], format: .xml, options: 0)
        XCTAssertNil(AGCAuthProvider.configuration(from: incomplete, bundleIdentifier: "com.milo.echoes.ios"))
    }

    func testRemoteDeletionCompletionSurvivesLocalFailureAndRelaunch() async throws {
        let f = try fixture(); defer { f.clean() }; let signedIn = await login(f); XCTAssertTrue(signedIn)
        let initial = await f.model.deleteAccount { false }
        XCTAssertFalse(initial)
        f.provider.failDelete = true // The real service no longer has this user.
        let restored = AccountModel(directory: f.directory, authProvider: f.provider)
        var cleaned = false
        let retried = await restored.deleteAccount { cleaned = true; return true }
        XCTAssertTrue(retried); XCTAssertTrue(cleaned); XCTAssertFalse(restored.isAuthenticated)
        XCTAssertEqual(f.provider.calls.filter { $0 == "delete" }.count, 1)
    }
    func testLoadedBundleProvenance() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).executableURL)
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        print("MILO_LOADED_TEST_BUNDLE_SHA256=" + digest)
    }

}
