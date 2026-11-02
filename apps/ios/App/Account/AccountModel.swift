import Foundation
import Observation
import UIKit

struct AccountIdentity: Codable, Equatable, Sendable {
    enum Provider: String, Codable, Sendable { case local, agc }
    let uid: String
    let email: String
    let provider: Provider
}

enum VerificationPurpose: String, Sendable { case signIn, resetPassword }

/// A supported AGC SDK adapter can implement this protocol once the bundle's
/// agconnect-services.plist exists. No remote identity is manufactured by the app.
@MainActor protocol MiloAuthProvider {
    var isConfigured: Bool { get }
    func restoreSession() async throws -> AccountIdentity?
    func sendCode(email: String, purpose: VerificationPurpose) async throws
    func signIn(email: String, code: String) async throws -> AccountIdentity
    func signIn(email: String, password: String) async throws -> AccountIdentity
    func resetPassword(email: String, code: String, password: String) async throws
    func changePassword(email: String, code: String, password: String) async throws
    func signOut() async throws
    func deleteAccount() async throws
}

struct UnconfiguredAGCAuthProvider: MiloAuthProvider {
    var isConfigured: Bool { false }
    private var unavailable: AccountFailure {
        .message("邮箱登录尚未接通，请完成此 iOS 版本的账号服务配置。现有本机回忆不会丢失。")
    }
    func restoreSession() async throws -> AccountIdentity? { nil }
    func sendCode(email: String, purpose: VerificationPurpose) async throws { throw unavailable }
    func signIn(email: String, code: String) async throws -> AccountIdentity { throw unavailable }
    func signIn(email: String, password: String) async throws -> AccountIdentity { throw unavailable }
    func resetPassword(email: String, code: String, password: String) async throws { throw unavailable }
    func changePassword(email: String, code: String, password: String) async throws { throw unavailable }
    func signOut() async throws { throw unavailable }
    func deleteAccount() async throws { throw unavailable }
}

@MainActor @Observable final class AccountModel {
    private(set) var identity: AccountIdentity?
    private(set) var aiSettings = PersonalAISettings()
    private(set) var avatarData: Data?
    private(set) var isBusy = false
    private(set) var passwordResetRequiresSignIn = false
    var statusMessage = ""
    var errorMessage = ""
    var isAuthenticated: Bool { identity != nil }
    var isLocalAccount: Bool { identity?.provider == .local }
    var email: String { identity?.email ?? "MILO 用户" }
    var remoteAuthConfigured: Bool { authProvider.isConfigured }
    let directory: URL
    @ObservationIgnored private let authProvider: any MiloAuthProvider
    @ObservationIgnored private let keychain: AccountKeychain
    @ObservationIgnored private var remoteDeletedUID: String?
    @ObservationIgnored private var cooldowns: [String: Date] = [:]
    #if DEBUG
    private(set) var fixtureState: String?

    /// Screenshot-only synthetic identity is confined to a UUID test directory.
    /// This never calls or replaces a production authentication provider.
    func configureFixture(remote: Bool = false, state: String? = nil) {
        let parts = directory.standardizedFileURL.pathComponents
        guard let marker = parts.lastIndex(of: "MILO-UITests"), parts.indices.contains(marker + 1),
              UUID(uuidString: parts[marker + 1]) != nil else { return }
        fixtureState = state
        identity = AccountIdentity(uid: remote ? "fixture-remote" : "milo-local-owner",
                                   email: remote ? "milo@example.com" : "milo", provider: remote ? .agc : .local)
        loadAccountPreferences()
        if ["personal", "consent", "connection-error"].contains(state ?? "") { aiSettings.source = .personal }
        if state == "consent" { aiSettings.consent = true }
        if state == "connection-error" { errorMessage = "连接失败，请检查网络、URL 和模型服务状态。" }
        if ["error", "password-error", "code-error"].contains(state ?? "") { errorMessage = "邮箱登录尚未接通，请完成此 iOS 版本的账号服务配置。现有本机回忆不会丢失。" }
    }
    func clearFixtureIdentity() {
        let parts = directory.standardizedFileURL.pathComponents
        guard let marker = parts.lastIndex(of: "MILO-UITests"), parts.indices.contains(marker + 1),
              UUID(uuidString: parts[marker + 1]) != nil else { return }
        identity = nil
    }
    #endif

    init(directory: URL, authProvider: (any MiloAuthProvider)? = nil) {
        self.directory = directory
        self.authProvider = authProvider ?? AGCAuthProvider.make()
        self.keychain = AccountKeychain(directory: directory)
        // An offline session is a device-local identity snapshot, never a token or
        // proof that an AGC session was freshly validated.
        do {
            let data = try Data(contentsOf: directory.appendingPathComponent("account.json"))
            identity = try JSONDecoder().decode(AccountIdentity.self, from: data)
            if let pending = try? Data(contentsOf: directory.appendingPathComponent("account-deletion.json")),
               let uid = try? JSONDecoder().decode(String.self, from: pending), uid == identity?.uid {
                remoteDeletedUID = uid
                statusMessage = "账号已注销，本机数据清理尚未完成，请重试注销以完成清理。"
            }
            loadAccountPreferences()
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            identity = nil
        } catch {
            identity = nil
            errorMessage = "账号信息暂时无法读取；本机回忆已保留。"
        }
    }

    static func validEmail(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil
    }
    static func validPassword(_ text: String) -> Bool {
        (6...32).contains(text.count) && text == text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func validCode(_ text: String) -> Bool { text.utf8.count == 6 && text.utf8.allSatisfy { (48...57).contains($0) } }
    static func isOwnerEmail(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "milo" }

    func clearMessages() { statusMessage = ""; errorMessage = ""; passwordResetRequiresSignIn = false }
    func resendSeconds(email: String, purpose: VerificationPurpose) -> Int {
        max(0, Int(ceil((cooldowns[cooldownKey(email, purpose)] ?? .distantPast).timeIntervalSinceNow)))
    }
    private func cooldownKey(_ email: String, _ purpose: VerificationPurpose) -> String { "\(purpose.rawValue)|\(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())" }

    func signInLocally() -> Bool {
        clearMessages()
        do {
            try acceptIdentity(AccountIdentity(uid: "milo-local-owner", email: "milo", provider: .local))
            return true
        } catch { errorMessage = "本机账号保存失败，请检查设备存储空间。"; return false }
    }

    func requestCode(email: String, purpose: VerificationPurpose) async -> Bool {
        guard !isBusy, Self.validEmail(email) else { return false }
        guard resendSeconds(email: email, purpose: purpose) == 0 else { return true }
        isBusy = true; clearMessages(); defer { isBusy = false }
        do {
            try await authProvider.sendCode(email: email.trimmingCharacters(in: .whitespacesAndNewlines), purpose: purpose)
            cooldowns[cooldownKey(email, purpose)] = Date().addingTimeInterval(60)
            statusMessage = "验证码已发送到绑定邮箱。"
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func signIn(email: String, password: String) async -> Bool {
        if Self.isOwnerEmail(email) { return signInLocally() }
        guard !isBusy, Self.validEmail(email), Self.validPassword(password) else { return false }
        isBusy = true; clearMessages(); defer { isBusy = false }
        do {
            try acceptIdentity(await authProvider.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password))
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func signIn(email: String, code: String) async -> Bool {
        guard !isBusy, Self.validEmail(email), Self.validCode(code) else { return false }
        isBusy = true; clearMessages(); defer { isBusy = false }
        do { try acceptIdentity(await authProvider.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), code: code)); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }

    func resetPassword(email: String, code: String, password: String) async -> Bool {
        guard !isBusy, Self.validEmail(email), Self.validCode(code), Self.validPassword(password) else { return false }
        isBusy = true; clearMessages(); defer { isBusy = false }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        var passwordChanged = false
        do {
            try await authProvider.resetPassword(email: address, code: code, password: password)
            passwordChanged = true
            try acceptIdentity(await authProvider.signIn(email: address, password: password))
            return true
        } catch {
            passwordResetRequiresSignIn = passwordChanged
            errorMessage = passwordChanged ? "密码已更新，请使用新密码登录。" : error.localizedDescription
            return false
        }
    }

    func changePassword(code: String, password: String, confirmation: String) async -> Bool {
        guard !isBusy, let identity, identity.provider != .local else { return false }
        clearMessages()
        guard password == confirmation else { errorMessage = "两次输入的密码不一致。"; return false }
        guard Self.validCode(code), Self.validPassword(password) else { errorMessage = "请填写 6 位验证码和 6–32 位新密码。"; return false }
        isBusy = true; defer { isBusy = false }
        do {
            try await authProvider.changePassword(email: identity.email, code: code, password: password)
            statusMessage = "密码已更新，下次请使用新密码登录。"; return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func signOut() async -> Bool {
        guard !isBusy else { return false }
        clearMessages(); isBusy = true; defer { isBusy = false }
        var remoteCleanupFailed = false
        if identity?.provider == .agc {
            do { try await authProvider.signOut() }
            catch { remoteCleanupFailed = true }
        }
        do {
            try removeIfExists(directory.appendingPathComponent("account.json"))
            identity = nil; aiSettings = PersonalAISettings(); avatarData = nil
            if remoteCleanupFailed { statusMessage = "已退出本机登录。远程会话未能完成清理，再次登录时会重新验证。" }
            return true
        } catch { errorMessage = "退出未完成：\(error.localizedDescription)"; return false }
    }

    func deleteAccount(deleteLocalData: () -> Bool) async -> Bool {
        guard !isBusy, let current = identity else { return false }
        clearMessages(); isBusy = true; defer { isBusy = false }
        do {
            if current.provider == .agc {
                if remoteDeletedUID != current.uid {
                    try await authProvider.deleteAccount()
                    remoteDeletedUID = current.uid
                }
                // Persist remote completion before local cleanup. A retry after
                // relaunch must not require a now-deleted remote session.
                try write(JSONEncoder().encode(current.uid), to: directory.appendingPathComponent("account-deletion.json"))
            }
            guard deleteLocalData() else {
                errorMessage = current.provider == .agc ? "账号已注销，但本机回忆清理未完成，请重试。" : "本机回忆清理未完成，账号仍保留，请重试。"
                return false
            }
            try keychain.delete(uid: current.uid)
            try removeIfExists(preferencesURL(uid: current.uid))
            try removeIfExists(avatarURL(uid: current.uid))
            try removeIfExists(directory.appendingPathComponent("account.json"))
            identity = nil; aiSettings = PersonalAISettings(); avatarData = nil
            remoteDeletedUID = nil
            try? removeIfExists(directory.appendingPathComponent("account-deletion.json"))
            return true
        } catch { errorMessage = "注销未完成：\(error.localizedDescription)"; return false }
    }

    func setAvatar(_ data: Data) -> Bool {
        guard let identity else { return false }
        clearMessages()
        guard data.count <= 20 * 1024 * 1024, let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.88) else {
            errorMessage = "头像未更新，请选择可读取且小于 20 MB 的图片。"; return false
        }
        do { try write(jpeg, to: avatarURL(uid: identity.uid)); avatarData = jpeg; return true }
        catch { errorMessage = "头像保存失败，原头像已保留。"; return false }
    }
    func resetAvatar() {
        guard let identity else { return }
        do { try removeIfExists(avatarURL(uid: identity.uid)); avatarData = nil }
        catch { errorMessage = "头像恢复失败，请重试。" }
    }

    func hasAPIKey(for settings: PersonalAISettings) -> Bool {
        guard let uid = identity?.uid else { return false }
        return (try? keychain.read(uid: uid, destination: settings.destination))?.isEmpty == false
    }

    func saveAISettings(_ settings: PersonalAISettings, newKey: String) -> Bool {
        guard let uid = identity?.uid else { return false }
        clearMessages()
        var clean = settings
        clean.baseURL = clean.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.model = clean.model.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.enabled {
                guard clean.consent else { throw AccountFailure.message("请先确认将当前情绪和对话发送给所选模型服务商。") }
                if clean.source == .personal {
                    guard clean.endpoint != nil, !clean.model.isEmpty, !key.isEmpty || hasAPIKey(for: clean) else {
                        throw AccountFailure.message("请填写 HTTPS 接口地址、模型名称和 API Key。")
                    }
                }
            }
            if clean.source == .personal, !key.isEmpty { try keychain.save(key, uid: uid, destination: clean.destination) }
            try write(JSONEncoder().encode(clean), to: preferencesURL(uid: uid))
            aiSettings = clean
            statusMessage = !AIFeaturePolicy.isAvailable ? AIFeaturePolicy.pausedMessage : clean.source == .milo && clean.enabled ? "设置已保存；此安装包尚未接通后台，目前仍是本地引导。" : "设置已保存，下次 AI 请求将使用此配置。"
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func removeAPIKey(for settings: PersonalAISettings) {
        guard let uid = identity?.uid else { return }
        clearMessages()
        do {
            try keychain.delete(uid: uid, destination: settings.destination)
            if settings.destination == aiSettings.destination {
                var clean = aiSettings; clean.consent = false
                try write(JSONEncoder().encode(clean), to: preferencesURL(uid: uid)); aiSettings = clean
            }
            statusMessage = "已删除本机 Key，重新使用时需再次确认数据发送。"
        } catch { errorMessage = error.localizedDescription }
    }

    func testConnection(settings: PersonalAISettings, newKey: String) async {
        guard AIFeaturePolicy.isAvailable else {
            clearMessages(); errorMessage = AIFeaturePolicy.pausedMessage; return
        }
        guard !isBusy, let uid = identity?.uid else { return }
        clearMessages(); isBusy = true; statusMessage = "正在连接模型，最长等待 30 秒…"
        defer { isBusy = false }
        do {
            let input = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = input.isEmpty ? try keychain.read(uid: uid, destination: settings.destination) ?? "" : input
            _ = try await PersonalAIConnection.complete(settings: settings, key: key,
                    messages: [AIMessage(role: .user, content: "这是连接测试，请只回复“连接成功”。")])
            statusMessage = "连接成功，可以保存并开始使用。"
        } catch { statusMessage = ""; errorMessage = error.localizedDescription }
    }

    /// Configuration-only preflight: never reads credentials or claims a successful connection.
    var aiUnavailableReason: String? {
        if !AIFeaturePolicy.isAvailable { return AIFeaturePolicy.pausedMessage }
        if !aiSettings.enabled { return "AI 已关闭。" }
        if aiSettings.source == .milo { return "此安装包的 MILO 默认模型尚未接通。" }
        if identity == nil { return "请先登录后配置自己的模型。" }
        if !aiSettings.consent { return "请在 AI 设置中确认将当前对话发送给所选模型。" }
        if aiSettings.endpoint == nil || aiSettings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请在 AI 设置中填写有效的 HTTPS 地址和模型名称。"
        }
        return nil
    }

    func completeAI(messages: [AIMessage]) async throws -> String {
        guard AIFeaturePolicy.isAvailable else { throw AccountFailure.message(AIFeaturePolicy.pausedMessage) }
        guard let uid = identity?.uid, aiSettings.enabled else { throw AccountFailure.message("正在使用本地引导。") }
        guard aiSettings.source == .personal else { throw AccountFailure.message("此安装包尚未接通后台，正在使用本地引导。") }
        let key = try keychain.read(uid: uid, destination: aiSettings.destination) ?? ""
        return try await PersonalAIConnection.complete(settings: aiSettings, key: key, messages: messages)
    }

    private func acceptIdentity(_ value: AccountIdentity) throws {
        try write(JSONEncoder().encode(value), to: directory.appendingPathComponent("account.json"))
        identity = value; loadAccountPreferences()
    }
    private func preferencesURL(uid: String) -> URL { directory.appendingPathComponent("ai-\(safeID(uid)).json") }
    private func avatarURL(uid: String) -> URL { directory.appendingPathComponent("avatar-\(safeID(uid)).jpg") }
    private func safeID(_ uid: String) -> String { Data(uid.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-") }
    private func loadAccountPreferences() {
        guard let identity else { return }
        aiSettings = (try? JSONDecoder().decode(PersonalAISettings.self, from: Data(contentsOf: preferencesURL(uid: identity.uid)))) ?? PersonalAISettings()
        avatarData = try? Data(contentsOf: avatarURL(uid: identity.uid))
    }
    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
    private func removeIfExists(_ url: URL) throws {
        do { try FileManager.default.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { }
    }
}
