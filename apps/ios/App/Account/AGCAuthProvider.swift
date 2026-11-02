import Foundation
import AGConnectAuth
import AGConnectCore
import HMFoundation

/// Native adapter for Huawei's pinned 1.9.4.300 SDK. The SDK owns its tokens;
/// AccountIdentity contains only non-secret display/account metadata.
@MainActor final class AGCAuthProvider: MiloAuthProvider {
    private static var initialized: AGCAuthProvider?
    private let auth: AGCAuth
    var isConfigured: Bool { true }

    private init(auth: AGCAuth) { self.auth = auth }

    /// A missing/wrong-platform config cannot initialize the SDK or send traffic.
    /// Merely linking the real SDK never manufactures a remote identity.
    static func make() -> any MiloAuthProvider {
        guard let url = Bundle.main.url(forResource: "agconnect-services", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let bundleID = Bundle.main.bundleIdentifier,
              let configuration = configuration(from: data, bundleIdentifier: bundleID) else {
            return UnconfiguredAGCAuthProvider()
        }
        if let initialized { return initialized }
        AGCInstance.startUp(configuration)
        let provider = AGCAuthProvider(auth: AGCAuth.instance())
        initialized = provider
        return provider
    }

    /// Validation is side-effect free so malformed/wrong-app configs can be
    /// tested without initializing the SDK or contacting the account service.
    static func configuration(from data: Data, bundleIdentifier: String) -> AGCServicesConfig? {
        guard !bundleIdentifier.isEmpty,
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = object as? [String: Any],
              let client = dictionary["client"] as? [String: Any],
              let package = client["package_name"] as? String,
              package == bundleIdentifier else { return nil }
        let configuration = AGCServicesConfig(dictionary: dictionary)
        guard valid(configuration.appId), valid(configuration.productId), valid(configuration.cpId),
              valid(configuration.apiKey), valid(configuration.clientId), valid(configuration.clientSecret),
              configuration.routePolicy != .unknown else { return nil }
        return configuration
    }

    private static func valid(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func restoreSession() async throws -> AccountIdentity? {
        guard let user = auth.currentUser else { return nil }
        // Cached metadata is not fresh remote authentication. The SDK refreshes
        // its token here; offline failures leave the caller's local diary intact.
        try await mapped {
            try await Self.resolve(user.getToken(true)) { _ in () }
        }
        return try Self.identity(user)
    }

    func sendCode(email: String, purpose: VerificationPurpose) async throws {
        let settings = AGCVerifyCodeSettings(action: purpose == .resetPassword ? .resetPassword : .registerLogin,
                                            locale: Locale(identifier: "zh_CN"), sendInterval: 60)
        try await mapped {
            try await Self.resolve(auth.requestVerifyCode(withEmail: email, settings: settings)) { _ in () }
        }
    }

    func signIn(email: String, code: String) async throws -> AccountIdentity {
        let credential = AGCEmailAuthProvider.credential(withEmail: email, password: nil, verifyCode: code)
        return try await mapped {
            do {
                return try await Self.resolve(auth.signIn(credential: credential), transform: Self.signedInIdentity)
            } catch {
                // iOS has no Harmony autoCreateUser flag. Only this explicit
                // server result permits registration; invalid OTP/network errors
                // must never trigger an account-creation attempt.
                guard (error as NSError).code == Int(AGCAuthErrorCode.AGCAuthErrorCodeUserNotRegistered.rawValue) else { throw error }
                return try await Self.resolve(auth.createUser(withEmail: email, password: nil, verifyCode: code),
                                              transform: Self.signedInIdentity)
            }
        }
    }

    func signIn(email: String, password: String) async throws -> AccountIdentity {
        let credential = AGCEmailAuthProvider.credential(withEmail: email, password: password)
        return try await mapped {
            try await Self.resolve(auth.signIn(credential: credential), transform: Self.signedInIdentity)
        }
    }

    func resetPassword(email: String, code: String, password: String) async throws {
        try await mapped {
            try await Self.resolve(auth.resetPassword(withEmail: email, newPassword: password, verifyCode: code)) { _ in () }
        }
    }

    func changePassword(email: String, code: String, password: String) async throws {
        guard let user = auth.currentUser,
              user.email?.caseInsensitiveCompare(email) == .orderedSame else { throw Self.reauthenticationRequired }
        try await mapped {
            try await Self.resolve(user.updatePassword(password, verifyCode: code,
                                                      provider: AGCAuthProviderType.email.rawValue)) { _ in () }
        }
    }

    func signOut() async throws { auth.signOut() }

    func deleteAccount() async throws {
        guard auth.currentUser != nil else { throw Self.reauthenticationRequired }
        try await mapped { try await Self.resolve(auth.deleteUser()) { _ in () } }
    }

    private static var reauthenticationRequired: AccountFailure {
        .message("请重新登录邮箱账号，再继续修改密码或注销账号。本机回忆仍然保留。")
    }

    /// Project only Sendable values out of the Objective-C callback, never pass
    /// AGCUser/AGCSignInResult across Swift actor boundaries.
    private nonisolated static func identity(_ user: AGCUser) throws -> AccountIdentity {
        guard !user.uid.isEmpty, let email = user.email, !email.isEmpty else {
            throw AccountFailure.message("账号服务没有返回完整身份，请重新登录。")
        }
        return AccountIdentity(uid: user.uid, email: email, provider: .agc)
    }

    private nonisolated static func signedInIdentity(_ result: AGCSignInResult?) throws -> AccountIdentity {
        guard let user = result?.user else { throw AccountFailure.message("账号服务没有返回登录结果，请重试。") }
        return try identity(user)
    }

    private func mapped<Result>(_ operation: () async throws -> Result) async throws -> Result {
        do { return try await operation() }
        catch {
            if let failure = error as? AccountFailure { throw failure }
            let nsError = error as NSError
            switch nsError.code {
            case Int(AGCAuthErrorCode.AGCAuthErrorCodeSensitiveOperationTimeout.rawValue),
                 Int(AGCAuthErrorCode.AGCAuthErrorCodeInvalidRefreshToken.rawValue),
                 Int(AGCAuthErrorCode.AGCAuthErrorCodeNotSignIn.rawValue):
                throw Self.reauthenticationRequired
            case Int(AGCAuthErrorCode.AGCAuthErrorCodeVerifyCodeError.rawValue),
                 Int(AGCAuthErrorCode.AGCAuthErrorCodePasswordVerifyCodeError.rawValue),
                 Int(AGCAuthErrorCode.AGCAuthErrorCodeSignInUserPasswordError.rawValue):
                throw AccountFailure.message("验证码或密码不正确，请检查后重试。")
            case Int(AGCAuthErrorCode.AGCAuthErrorCodeVerifyCodeIntervalLimit.rawValue),
                 Int(AGCAuthErrorCode.AGCAuthErrorCodeVerifyCodeTimeLimit.rawValue):
                throw AccountFailure.message("验证码发送过于频繁，请稍后再试。")
            case Int(AGCAuthErrorCode.AGCAuthErrorCodePasswordStrengthLow.rawValue):
                throw AccountFailure.message("密码强度不足，请使用至少两种字母、数字或符号组合。")
            default:
                if nsError.domain == NSURLErrorDomain {
                    throw AccountFailure.message("暂时无法连接账号服务，请检查网络后重试。本机回忆仍然保留。")
                }
                // Do not display vendor messages, which may contain user data.
                throw AccountFailure.message("账号操作未完成，请稍后重试（错误 \(nsError.code)）。")
            }
        }
    }

    private static func resolve<Value: AnyObject, Result: Sendable>(
        _ task: HMFoundation.Task<Value>,
        transform: @escaping @Sendable (Value?) throws -> Result
    ) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            // A single terminal callback prevents success/failure double-resume.
            task.onComplete { finished in
                if let error = finished.error { continuation.resume(throwing: error) }
                else if finished.isCanceled { continuation.resume(throwing: CancellationError()) }
                else if finished.isSuccessful {
                    do { continuation.resume(returning: try transform(finished.result)) }
                    catch { continuation.resume(throwing: error) }
                } else {
                    continuation.resume(throwing: AccountFailure.message("账号服务未返回结果，请重试。"))
                }
            }
        }
    }
}
