import Foundation
import Security
import CryptoKit

/// Reversible product-wide pause. Saved preferences and Keychain values are
/// retained, but cannot override this gate or start a model request.
enum AIFeaturePolicy {
    static let isAvailable = false
    static let pausedMessage = "AI 功能暂时下架，仍可在本机记录、编辑和导出回忆。"
}

enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case deepseek, qwen, kimi, minimax, custom
    var id: String { rawValue }
    var title: String {
        switch self { case .deepseek: "DeepSeek"; case .qwen: "通义千问"; case .kimi: "Kimi"; case .minimax: "MiniMax"; case .custom: "自定义（OpenAI 兼容）" }
    }
    var baseURL: String {
        switch self { case .deepseek: "https://api.deepseek.com/v1"; case .qwen: "https://dashscope.aliyuncs.com/compatible-mode/v1"; case .kimi: "https://api.moonshot.cn/v1"; case .minimax: "https://api.minimaxi.com/v1"; case .custom: "" }
    }
    var model: String {
        switch self { case .deepseek: "deepseek-chat"; case .qwen: "qwen-plus"; case .kimi: "kimi-k2.6"; case .minimax: "MiniMax-M2.5"; case .custom: "" }
    }
}

struct PersonalAISettings: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable { case milo, personal }
    var enabled = true
    var source: Source = .milo
    var provider: AIProvider = .deepseek
    var baseURL = AIProvider.deepseek.baseURL
    var model = AIProvider.deepseek.model
    var consent = false

    /// Canonical full destination binds both consent and credentials. URL credentials,
    /// fragments and query strings are rejected, rather than silently removed.
    var endpoint: URL? { Self.completionURL(baseURL) }
    var destination: String { "\(source.rawValue)|\(provider.rawValue)|\(endpoint?.absoluteString ?? "invalid")" }

    static func completionURL(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              !host.contains(where: { $0.isWhitespace }),
              parts.port == nil || (1...65535).contains(parts.port!) else { return nil }
        parts.scheme = "https"
        parts.host = host.lowercased()
        if parts.port == 443 { parts.port = nil }
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        if !parts.path.hasSuffix("/chat/completions") { parts.path += "/chat/completions" }
        return parts.url
    }
}

struct AIMessage: Codable, Sendable, Equatable {
    enum Role: String, Codable, Sendable { case system, user, assistant }
    let role: Role
    let content: String
}

enum AccountFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

struct AccountKeychain {
    private let service: String
    init(directory: URL) {
        service = "com.milo.echoes.ios.ai." + Self.digest(directory.standardizedFileURL.path)
    }
    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func query(uid: String, destination: String? = nil) -> [String: Any] {
        var value: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrGeneric as String: Data(uid.utf8),
                                    kSecAttrSynchronizable as String: false]
        if let destination { value[kSecAttrAccount as String] = Self.digest(uid + "|" + destination) }
        return value
    }
    func read(uid: String, destination: String) throws -> String? {
        var value = query(uid: uid, destination: destination)
        value[kSecReturnData as String] = true
        value[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(value as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw AccountFailure.message("无法读取安全存储，请解锁设备后重试。")
        }
        return key
    }
    func save(_ key: String, uid: String, destination: String) throws {
        let value = query(uid: uid, destination: destination)
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
                                         kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(value as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(value.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AccountFailure.message("安全存储暂不可用，Key 未写入普通文件。") }
    }
    func delete(uid: String, destination: String? = nil) throws {
        let status = SecItemDelete(query(uid: uid, destination: destination) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccountFailure.message("无法删除安全存储中的 Key，请解锁设备后重试。")
        }
    }
}

private final class NoCredentialRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Never forward a bearer credential to a redirected destination.
        completionHandler(nil)
    }
}

enum PersonalAIConnection {
    static func complete(settings: PersonalAISettings, key: String, messages: [AIMessage]) async throws -> String {
        guard AIFeaturePolicy.isAvailable else { throw AccountFailure.message(AIFeaturePolicy.pausedMessage) }
        guard let endpoint = settings.endpoint, !settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AccountFailure.message("请填写 HTTPS 接口地址、模型名称和 API Key。")
        }
        guard settings.enabled, settings.source == .personal, settings.consent else {
            throw AccountFailure.message("请先确认将当前情绪和对话发送给所选模型服务商。")
        }
        struct Body: Encodable {
            let model: String
            let messages: [AIMessage]
            let stream = false
            let thinking: [String: String]?
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoCredentialRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Body(model: settings.model.trimmingCharacters(in: .whitespacesAndNewlines),
            messages: messages, thinking: settings.provider == .kimi && settings.model == "kimi-k2.6" ? ["type": "disabled"] : nil))
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw AccountFailure.message("连接失败，请检查网络、URL 和模型服务状态。") }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AccountFailure.message("模型服务未返回有效响应。") }
        switch http.statusCode {
        case 200...299: break
        case 401, 403: throw AccountFailure.message("API Key 无效或没有模型权限，请检查 Key。")
        case 429: throw AccountFailure.message("模型额度不足或请求频繁，请检查服务商余额后重试。")
        case 404: throw AccountFailure.message("模型或接口地址不存在，请检查 URL 和模型名称。")
        case 300...399: throw AccountFailure.message("接口发生跳转；为保护 Key，请直接填写服务商的最终 HTTPS 地址。")
        default: throw AccountFailure.message("模型服务暂时不可用（\(http.statusCode)），请稍后重试。")
        }
        guard data.count <= 2_000_000 else { throw AccountFailure.message("模型响应过长，请换一个模型重试。") }
        struct Response: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
            let choices: [Choice]
        }
        guard let parsed = try? JSONDecoder().decode(Response.self, from: data),
              let content = parsed.choices.first?.message.content else {
            throw AccountFailure.message("模型没有返回正文，或此接口不兼容 Chat Completions。")
        }
        let text = content.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AccountFailure.message("模型没有返回正文，请重试。") }
        return text
    }
}
