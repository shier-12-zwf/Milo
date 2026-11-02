import Foundation
import MiloCore

// Compiled without MILO_AI_COORDINATOR_TESTS, exactly like product code.
// The UIKit-only account storage is stubbed; both request guards are real.
@MainActor final class AccountModel {
    let directory: URL
    var aiSettings = PersonalAISettings()
    var aiUnavailableReason: String? { nil }
    private(set) var calls = 0
    init(directory: URL) { self.directory = directory }
    func completeAI(messages: [AIMessage]) async throws -> String {
        calls += 1
        return "A paused product must never reach this completion."
    }
}

private final class RequestCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private final class NoNetworkProtocol: URLProtocol, @unchecked Sendable {
    static let requests = RequestCount()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.increment()
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

enum PauseCheckError: Error { case failed(String) }

@main struct PauseChecks {
    @MainActor static func require(_ value: @autoclosure () throws -> Bool, _ reason: String) throws {
        guard try value() else { throw PauseCheckError.failed(reason) }
    }

    @MainActor static func main() async throws {
        try require(!AIFeaturePolicy.isAvailable, "product AI gate must remain off")
        URLProtocol.registerClass(NoNetworkProtocol.self)
        defer { URLProtocol.unregisterClass(NoNetworkProtocol.self) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MILO-Pause-Checks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var passed = 0

        for source in [PersonalAISettings.Source.milo, .personal] {
            for provider in AIProvider.allCases {
                var settings = PersonalAISettings()
                settings.enabled = true; settings.source = source; settings.provider = provider
                settings.consent = true; settings.baseURL = "https://pause-check.invalid/v1"; settings.model = "synthetic"
                do {
                    _ = try await PersonalAIConnection.complete(settings: settings, key: "synthetic-not-a-real-key",
                                                                messages: [AIMessage(role: .user, content: "synthetic pause check")])
                    throw PauseCheckError.failed("paused provider completed")
                } catch {
                    try require(error.localizedDescription == AIFeaturePolicy.pausedMessage, "pause must precede all provider validation/network work")
                }
                passed += 1
            }
        }
        try require(NoNetworkProtocol.requests.value == 0, "connection attempts must send zero HTTP requests")

        for restoredPage in ["chat", "ai-settings", "diary"] {
            let directory = root.appendingPathComponent(UUID().uuidString)
            let repository = JSONJournalRepository(fileURL: directory.appendingPathComponent("journal.json"))
            let drafts = JSONDraftRepository(fileURL: directory.appendingPathComponent("draft.json"))
            let saved = RecallDraft(kind: "past", timeMark: "昨天", note: "保留原始记录", transcript: [
                TranscriptMessage(role: .ai, text: "原先保留的开场"),
                TranscriptMessage(role: .user, text: "我在河边散步。")
            ], aiEnabled: true, inputText: "还没发送的文字", diary: restoredPage == "diary" ? "手动编辑的正文" : nil,
                                   previousDiary: "上一版正文", diaryEnabled: true, page: restoredPage)
            try drafts.save(saved)
            let originalBytes = try Data(contentsOf: drafts.fileURL)
            var injectedCalls = 0
            let model = JournalModel(repository: repository, directory: directory, aiCompletion: { _ in
                injectedCalls += 1; return "Cannot bypass product pause"
            })
            try require(model.draft == saved && Data(contentsOf: drafts.fileURL) == originalBytes, "restoring an AI-enabled old draft must not rewrite its data")
            try require(model.aiUnavailableReason == AIFeaturePolicy.pausedMessage && !model.canRetryReply, "old settings and injected closure cannot bypass product pause")
            model.openSettings(); model.setAIEnabled(true)
            try require(model.draft == saved, "hidden settings/toggle entry points preserve the draft")
            model.resumeDraft()
            if restoredPage == "diary" {
                try require(model.draft.diary == "手动编辑的正文", "old diary edit must remain intact")
                model.back()
            }
            model.draft.inputText = "后来看到白鸟。"; model.send()
            try require(model.draft.transcript.last?.text == "后来看到白鸟。" && !model.isThinking, "send still records raw words locally")
            model.retryReply(); model.prepareDiary()
            for _ in 0..<10 { await Task.yield() }
            try require(model.draft.diary == OfflineGuide.diary(transcript: model.draft.transcript), "diary uses the local original-words formatter")
            model.editDiary("亲手编辑并保存的正文。")
            try require(model.save(), "local save remains available")
            try require(model.entries.count == 1 && model.entries[0].diary == "亲手编辑并保存的正文。", "local saved edit must be preserved")
            try require(model.exportJSON() != nil && model.exportMarkdown()?.contains("亲手编辑并保存的正文。") == true, "both local export formats remain available")
            try require(injectedCalls == 0 && model.account.calls == 0 && NoNetworkProtocol.requests.value == 0, "all old-draft paths must stay completely offline")
            passed += 1
        }
        print("PASS: \(passed) production-mode AI pause checks; zero model/HTTP calls, old drafts retained, local save/edit/export verified.")
    }
}
