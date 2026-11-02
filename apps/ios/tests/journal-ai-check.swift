import Foundation
import MiloCore

// Run with apps/ios/scripts/test-journal-ai.sh. The script compiles the real
// JournalModel, AIMessage and MiloCore sources. Only the UIKit-dependent account
// container is substituted here; each request uses the injected ControlledAI.
// No URLSession request, credential, authentication provider or personal store
// is touched. Deliberately uncancellable continuations test late provider data.
@MainActor final class AccountModel {
    let directory: URL
    var aiSettings: PersonalAISettings
    // Only account storage is stubbed: the real PersonalAISettings value and
    // JournalModel coordinator remain under test, without credentials or HTTP.
    static var fixtureSettings: [String: PersonalAISettings] = [:]
    init(directory: URL) {
        self.directory = directory
        aiSettings = Self.fixtureSettings[directory.path] ?? PersonalAISettings()
    }
    var aiUnavailableReason: String? { aiSettings.source == .milo ? "MILO 默认模型尚未接通。" : nil }
    func completeAI(messages: [AIMessage]) async throws -> String { throw URLError(.notConnectedToInternet) }
}

@MainActor final class ControlledAI {
    var messages: [[AIMessage]] = []
    var waiting: [Int: CheckedContinuation<String, any Error>] = [:]
    func complete(_ messages: [AIMessage]) async throws -> String {
        let index = self.messages.count
        self.messages.append(messages)
        // Intentionally ignores task cancellation to test a late provider response.
        return try await withCheckedThrowingContinuation { waiting[index] = $0 }
    }
    func reply(_ value: String, at index: Int = 0) { waiting.removeValue(forKey: index)!.resume(returning: value) }
    func fail(error: any Error = URLError(.notConnectedToInternet), at index: Int = 0) { waiting.removeValue(forKey: index)!.resume(throwing: error) }
}

enum CheckError: Error { case failed(String) }

@MainActor struct StorageFixture {
    let directory: URL
    let journal: JSONJournalRepository
    let drafts: JSONDraftRepository
    init(_ root: URL) {
        directory = root.appendingPathComponent("MILO-UITests").appendingPathComponent(UUID().uuidString)
        journal = JSONJournalRepository(fileURL: directory.appendingPathComponent("journal.json"))
        drafts = JSONDraftRepository(fileURL: directory.appendingPathComponent("draft.json"))
    }
    func model() -> JournalModel { JournalModel(repository: journal, directory: directory) }
    func blockDraft() throws -> Data {
        let bytes = try Data(contentsOf: drafts.fileURL)
        try FileManager.default.removeItem(at: drafts.fileURL)
        try FileManager.default.createDirectory(at: drafts.fileURL, withIntermediateDirectories: true)
        return bytes
    }
    func restoreDraft(_ bytes: Data) throws {
        try FileManager.default.removeItem(at: drafts.fileURL)
        try bytes.write(to: drafts.fileURL, options: .atomic)
    }
}

@main struct Checks {
    @MainActor static func require(_ value: @autoclosure () throws -> Bool, _ reason: String) throws {
        guard try value() else { throw CheckError.failed(reason) }
    }
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 { if condition() { return }; await Task.yield() }
        throw CheckError.failed("test callback did not settle")
    }
    @MainActor static func drain() async { for _ in 0..<50 { await Task.yield() } }
    @MainActor static func create(_ ai: ControlledAI, _ root: URL) -> JournalModel {
        let directory = root.appendingPathComponent(UUID().uuidString)
        let repository = JSONJournalRepository(fileURL: directory.appendingPathComponent("journal.json"))
        return JournalModel(repository: repository, directory: directory, aiCompletion: { try await ai.complete($0) })
    }
    static func transcript() -> [TranscriptMessage] {
        [TranscriptMessage(role: .ai, text: "你最先想起什么？"), TranscriptMessage(role: .user, text: "我在河边散步，看见一只白鸟。")]
    }
    static func fullDraft(_ note: String) -> RecallDraft {
        RecallDraft(mood: .bright, labels: ["明亮", "温暖"], kind: "past", timeMark: "那个夏天", note: note,
                    transcript: transcript(), aiEnabled: false, inputText: "还没有发送的文字", diary: "亲手修改的日记", previousDiary: "上一版👩🏽‍🚀\n补充文字",
                    diaryEnabled: true, stickerTemplate: .orbitTheatre, page: "diary", entryID: "browsed-entry", pendingEntryID: "pending-entry")
    }
    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MILO-AI-Checks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var passed = 0
        do {
            let fixture = StorageFixture(root), model = fixture.model()
            model.startPresentConversation()
            try require(model.draft.page == "chat" && model.draft.kind == "now" && model.draft.timeMark == nil, "present chat skips past time selection")
            try require(model.chatNotice == "仅本地记录" && model.chatDetail == AIFeaturePolicy.pausedMessage, "paused model has a concise local status with an honest detailed cause")
            model.draft.inputText = "今天心情不好，想吐槽"; model.send(); model.send()
            try require(model.draft.transcript.count == 2 && !model.isThinking && !model.canRetryReply, "unconfigured send records once with no fabricated reply or loading")
            model.draft.inputText = "开了一天会，最后又被加活。"; model.send()
            try require(model.draft.transcript.count == 3 && model.entries.isEmpty && model.draft.diary == nil, "offline user can continue expressing without turn-count responses")
            model.draft.inputText = "没说完的文字"; model.endConversation()
            let restored = fixture.model()
            try require(restored.hasUnfinishedDraft && restored.draft.page == "home" && restored.entries.isEmpty, "exit persists raw draft, not a diary or saved entry")
            restored.resumeDraft()
            try require(restored.draft.page == "chat" && restored.draft.inputText == "没说完的文字", "present draft resumes after restart without generation")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.startPresentConversation()
            try require(ai.messages.isEmpty, "present welcome is local and does not invent a user opening request")
            let examples = ["开了一天会，最后被加活，只想说说，先别建议", "最近每天这样", "同事没回消息肯定看不起我，别一味附和", "请给两个建议"]
            for (index, example) in examples.enumerated() {
                model.draft.inputText = example; model.send()
                try await wait { ai.messages.count == index + 1 }
                try require(ai.messages[index].last?.content == example && ai.messages[index].last?.role == .user, "synthetic latest request is passed verbatim")
                let instruction = ai.messages[index][0].content
                try require(instruction.contains("可以只回应而不提问") && instruction.contains("不一味附和") && instruction.contains("给两个") && instruction.contains("不要强迫转向过去") && !instruction.contains("48"), "prompt defines listening, uncertainty, requested help and present context; this is not a semantic quality test")
                let response = "你说开了一天会之后还被加活，这样的日子又接连出现，留给自己喘口气的时间很少。\n这次可以先把想吐槽的话说完，不急着解决。👩🏽‍🚀\n这是必须完整保留的最后一句。"
                model.draft.inputText = "等待时的新草稿"; model.send()
                try require(ai.messages.count == index + 1, "send is rejected during generation without losing new typing")
                ai.reply(response, at: index)
                try await wait { !model.isThinking }
                try require(model.draft.transcript.last?.text == response && model.draft.inputText == "等待时的新草稿", "reply longer than 48 characters, emoji, newline and tail survive exactly")
                model.draft.inputText = ""
            }
            model.draft.inputText = "先到这里，也不用生成日记"; model.send(); model.endConversation()
            await drain()
            try require(ai.messages.count == 4 && model.entries.isEmpty && model.draft.diary == nil && model.hasUnfinishedDraft, "explicit ending triggers neither another reply nor diary generation or collection")
            passed += 1
        }
        for error in [URLError(.timedOut) as any Error, AccountFailure.message("API Key 无效或没有模型权限，请检查 Key。")] {
            let ai = ControlledAI(), model = create(ai, root)
            model.startPresentConversation(); model.draft.inputText = "今天被加活了。"; model.send()
            try await wait { ai.messages.count == 1 }; ai.fail(error: error)
            try await wait { !model.isThinking }
            try require(model.draft.transcript.count == 2 && model.chatNotice == "回复失败，原话已保留" && model.chatDetail == error.localizedDescription,
                        "timeout/authentication failure keeps a short status, optional cause and user text without inventing a reply")
            model.draft.inputText = "只想再说一点。"; model.send()
            await drain()
            try require(ai.messages.count == 1 && model.draft.transcript.count == 3, "failure does not loop requests or repeated scripted responses")
            model.retryReply(); model.retryReply()
            try await wait { ai.messages.count == 2 }
            try require(model.draft.transcript.count == 3, "retry neither resends a duplicate user message nor creates concurrent requests")
            ai.reply("这次连接恢复了。", at: 1)
            try await wait { !model.isThinking }
            try require(model.draft.transcript.count == 4 && model.chatDetail == nil && model.chatNotice.isEmpty,
                        "explicit retry appends exactly one real reply and clears stale failure details")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.startPresentConversation(); model.draft.inputText = "今天有点累。"; model.send()
            try await wait { ai.messages.count == 1 }; model.stopReply()
            model.openSettings(); model.back(); await drain()
            try require(ai.messages.count == 1, "unchanged settings must not restart a deliberately stopped reply")
            model.draft.inputText = "我想接着说。"; model.send()
            try await wait { ai.messages.count == 2 }
            ai.reply("已经停止的旧回复", at: 0); await drain()
            try require(model.isThinking && model.draft.transcript.count == 3, "late stopped reply must not end a newer request")
            ai.reply("新的回复", at: 1); try await wait { !model.isThinking }
            try require(model.draft.transcript.last?.text == "新的回复", "sending after stop can start a new request without a connection-failure claim")
            passed += 1
        }
        for operation in ["stop", "back", "settings", "end", "off"] {
            let ai = ControlledAI(), model = create(ai, root)
            model.startPresentConversation(); model.draft.inputText = "今天心情不好。"; model.send()
            try await wait { ai.messages.count == 1 }
            model.draft.inputText = "未发送的新句子"
            switch operation {
            case "stop": model.stopReply()
            case "back": model.back()
            case "settings": model.openSettings()
            case "end": model.endConversation()
            default: model.setAIEnabled(false)
            }
            let retained = model.draft
            ai.reply("不能插入的迟到回复")
            await drain()
            try require(!model.isThinking && model.draft == retained && model.draft.transcript.count == 2 && model.draft.inputText == "未发送的新句子", "present \(operation) cancels safely, retaining user input and suppressing late data")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.startPresentConversation(); model.draft.inputText = "今天被加活了。"; model.send()
            try await wait { ai.messages.count == 1 }; ai.reply("可以先把这件事说完。")
            try await wait { !model.isThinking }; model.saveConversation()
            try require(ai.messages.count == 1 && model.entries.count == 1 && model.entries[0].kind == "now" && model.entries[0].transcript.count == 3 && !model.entries[0].diaryEnabled && model.entries[0].diary == nil, "present conversation-only collection never calls diary generation")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.startPresentConversation(); model.draft.inputText = "今天被加活了。"; model.send()
            try await wait { ai.messages.count == 1 }; ai.reply("可以先把这件事说完。")
            try await wait { !model.isThinking }; model.prepareDiary()
            try await wait { ai.messages.count == 2 }
            try require(ai.messages[1].filter { $0.role == .user }.map(\.content) == ["今天被加活了。"] && ai.messages[1][0].content.contains("今天 / 此刻"), "explicit present diary uses user facts and present time only")
            ai.reply("今天被加活了。", at: 1); try await wait { !model.isThinking }
            try require(model.save() && model.entries[0].diary == "今天被加活了。" && model.entries[0].kind == "now", "optional present diary saves and validates without relabeling it as past")
            passed += 1
        }
        for kind in ["now", "past"] {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: kind, timeMark: kind == "past" ? "昨天" : nil,
                                      transcript: transcript(), diary: "之前整理的日记。", page: "diary")
            model.editDiary("我亲手修改过的日记。"); model.back()
            try require(model.draft.diary == "我亲手修改过的日记。", "navigation alone must retain the edited diary")
            model.draft.inputText = "后来还看见天边的彩虹。"; model.send()
            try await wait { ai.messages.count == 1 }
            let storedDraft = try JSONDraftRepository(fileURL: model.account.directory.appendingPathComponent("draft.json")).load()
            try require(model.draft.diary == nil && storedDraft?.diary == nil && storedDraft?.previousDiary == "我亲手修改过的日记。",
                        "new user expression invalidates the old cache while retaining the edited body in a persisted backup in \(kind) mode")
            ai.reply("你还记得那道彩虹。"); try await wait { !model.isThinking }
            model.prepareDiary(); try await wait { ai.messages.count == 2 }
            try require(ai.messages[1].filter { $0.role == .user }.map(\.content) == ["我在河边散步，看见一只白鸟。", "后来还看见天边的彩虹。"],
                        "regenerated diary receives both old and newly added user content")
            ai.reply("我在河边散步，看见白鸟，后来又看见彩虹。", at: 1)
            try await wait { !model.isThinking }
            model.restorePreviousDiary()
            try require(model.draft.diary == "我亲手修改过的日记。" && model.draft.previousDiary == "我在河边散步，看见白鸟，后来又看见彩虹。",
                        "restoring the edited prior body keeps the newly generated body available")
            model.restorePreviousDiary()
            try require(model.save() && model.entries[0].diary == "我在河边散步，看见白鸟，后来又看见彩虹。",
                        "saving after more conversation never reuses the outdated diary")
            passed += 1
        }
        for kind in ["now", "past"] {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: kind, timeMark: kind == "past" ? "昨天" : nil,
                                      transcript: transcript(), diary: "手改正文，包含未在聊天说过的补充。",
                                      previousDiary: "更早的正文。", page: "chat")
            model.draft.inputText = "先到这里，也不用生成日记"; model.send(); model.endConversation()
            await drain()
            let stored = try JSONDraftRepository(fileURL: model.account.directory.appendingPathComponent("draft.json")).load()
            try require(ai.messages.isEmpty && stored?.diary == "手改正文，包含未在聊天说过的补充。" && stored?.previousDiary == "更早的正文。",
                        "pausing and leaving preserve both edited diary versions without treating pause as new material")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: "now", transcript: transcript(), previousDiary: "之前手改的正文。", page: "chat")
            model.prepareDiary(); try await wait { ai.messages.count == 1 }
            model.restorePreviousDiary()
            try require(model.draft.diary == "之前手改的正文。" && model.draft.previousDiary == nil && !model.isThinking,
                        "restoring a backup without a current body cancels generation and consumes the backup")
            ai.reply("不能覆盖恢复正文的迟到日记"); await drain()
            let savedDraft = try JSONDraftRepository(fileURL: model.account.directory.appendingPathComponent("draft.json")).load()
            try require(savedDraft?.diary == "之前手改的正文。" && savedDraft?.previousDiary == nil,
                        "restored backup survives persistence and a late cancelled diary reply")
            passed += 1
        }
        for enabled in [false, true] {
            let fixture = StorageFixture(root)
            var settings = PersonalAISettings(); settings.enabled = enabled
            AccountModel.fixtureSettings[fixture.directory.path] = settings
            let model = fixture.model()
            try require(model.draft.aiEnabled == enabled, "first draft must use the stored account AI default")
            try require(fixture.drafts.load() == nil, "reading the account default must not manufacture a persisted draft")
            model.draft.aiEnabled = !enabled
            model.draft.mood = .bright
            model.beginMoodWords()
            try require(model.draft.aiEnabled == enabled && model.draft.mood == .bright, "new mood journey must use the account default while retaining mood")
            model.draft.aiEnabled = !enabled
            model.startHome()
            try require(model.draft.aiEnabled == enabled, "starting another memory must use the current account default")
            passed += 1
        }
        for enabled in [false, true] {
            let fixture = StorageFixture(root)
            var settings = PersonalAISettings(); settings.enabled = !enabled
            AccountModel.fixtureSettings[fixture.directory.path] = settings
            var saved = fullDraft("用户已经明确选择的草稿")
            saved.aiEnabled = enabled
            try fixture.drafts.save(saved)
            let model = fixture.model()
            try require(model.draft == saved, "restored draft must preserve its choice even when the account default differs")
            model.openSettings()
            try require(model.draft.aiEnabled == enabled, "opening settings without saving cannot replace the session choice")
            try require(model.draft == saved, "paused settings entry must retain the complete restored diary without navigating")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: "past", page: "past-time")
            model.startConversation(time: "昨天")
            try await wait { ai.messages.count == 1 }
            model.openSettings()
            model.account.aiSettings.enabled = false
            model.aiSettingsDidSave()
            try require(!model.draft.aiEnabled && !model.isThinking, "successful settings save must synchronize the current draft")
            model.back()
            let local = model.draft.transcript
            try require(model.draft.page == "chat" && local.count == 1 && ai.messages.count == 1, "returning to an interrupted opening with AI disabled must use local guidance")
            ai.reply("设置保存前的迟到开场")
            await drain()
            try require(model.draft.transcript == local, "a prior opening cannot return after settings changed")
            let repository = JSONJournalRepository(fileURL: model.account.directory.appendingPathComponent("journal.json"))
            let restored = JournalModel(repository: repository, directory: model.account.directory)
            try require(!restored.draft.aiEnabled, "the synchronized session AI choice survives restart")
            model.draft.inputText = "我还记得河边的树。"; model.send()
            try require(model.draft.transcript.count == 2 && !model.isThinking && ai.messages.count == 1, "local chat remains usable after saving settings")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: "past", page: "past-time")
            model.startConversation(time: "昨天")
            // Save before the scheduled Task has begun contacting its provider.
            model.account.aiSettings.enabled = false
            model.aiSettingsDidSave()
            await drain()
            try require(ai.messages.isEmpty && !model.isThinking && !model.draft.aiEnabled,
                        "settings cancellation before task execution must prevent the provider call itself")
            passed += 1
        }
        for changedField in ["provider", "model", "consent"] {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: "past", timeMark: "昨天", transcript: transcript(), inputText: "我还记得风的声音。", page: "chat")
            model.send()
            try await wait { ai.messages.count == 1 }
            let waitingTranscript = model.draft.transcript
            switch changedField {
            case "provider": model.account.aiSettings.provider = .qwen
            case "model": model.account.aiSettings.model = "new-test-model"
            default: model.account.aiSettings.consent = true
            }
            // Exercise the save callback itself, independent of navigation's
            // cancellation. Enabled stays true in all three configuration changes.
            model.aiSettingsDidSave()
            try require(model.draft.aiEnabled && !model.isThinking && model.draft.transcript == waitingTranscript,
                        "saving \(changedField) with AI still on must cancel the old request without erasing user text")
            model.openSettings(); model.back()
            try await wait { ai.messages.count == 2 }
            try require(model.isThinking && model.draft.transcript == waitingTranscript,
                        "returning to chat must resume the pending answer without duplicating the user's message")
            ai.reply("旧配置迟到回复", at: 0)
            await drain()
            try require(model.isThinking && model.draft.transcript == waitingTranscript,
                        "old \(changedField) request cannot mutate or finish the replacement request")
            ai.reply("新配置下的回复", at: 1)
            try await wait { !model.isThinking }
            try require(model.draft.transcript.count == waitingTranscript.count + 1 && model.draft.transcript.last?.text == "新配置下的回复",
                        "the resumed request must still complete under current settings")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: "past", timeMark: "昨天", transcript: transcript(), page: "chat")
            model.prepareDiary()
            try await wait { ai.messages.count == 1 }
            model.account.aiSettings.enabled = false
            model.aiSettingsDidSave()
            ai.reply("旧模型不该覆盖的新日记")
            await drain()
            try require(!model.isThinking && model.draft.diary == nil, "saving settings invalidates pending diary output too")
            model.ensureDiary()
            try require(model.draft.diary == OfflineGuide.diary(transcript: transcript()), "diary can continue locally after AI is disabled")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: "past", aiEnabled: false, page: "past-time")
            model.startConversation(time: "昨天")
            try require(model.draft.transcript.count == 1 && !model.isThinking && ai.messages.isEmpty, "disabled opening must be immediate local guidance")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: "past", page: "past-time")
            model.startConversation(time: "昨天")
            try await wait { ai.messages.count == 1 }
            try require(model.isThinking && model.draft.transcript.isEmpty, "opening must wait for configured completion")
            ai.reply("昨天最让你记得的是什么？")
            try await wait { !model.isThinking }
            try require(model.draft.transcript.last?.text == "昨天最让你记得的是什么？", "opening response is used")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: "past", page: "past-time")
            model.startConversation(time: "昨天")
            try await wait { ai.messages.count == 1 }
            model.setAIEnabled(false)
            let local = model.draft.transcript
            ai.reply("这段旧回复不能出现")
            await drain()
            try require(!model.isThinking && model.draft.transcript == local && local.count == 1, "disabled AI must suppress late opening response")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: "past", page: "past-time")
            model.startConversation(time: "昨天")
            try await wait { ai.messages.count == 1 }
            model.startConversation(time: "大学时光")
            try await wait { ai.messages.count == 2 }
            ai.reply("旧时间的回答")
            await drain()
            try require(model.isThinking && model.draft.transcript.isEmpty, "stale completion must not clear a newer generation")
            ai.reply("大学里你先想起谁？", at: 1)
            try await wait { !model.isThinking }
            try require(model.draft.transcript.count == 1 && model.draft.transcript[0].text == "大学里你先想起谁？", "contexts stay isolated")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: "past", timeMark: "昨天", transcript: transcript(), inputText: "风很温柔。", page: "chat")
            model.send()
            try await wait { ai.messages.count == 1 }
            ai.fail()
            try await wait { !model.isThinking }
            try require(model.draft.transcript[2].text == "风很温柔。" && model.draft.transcript.count == 3 && model.chatNotice == "回复失败，原话已保留", "failed response preserves user text without fabricated understanding")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: "past", timeMark: "昨天", transcript: transcript(), page: "chat")
            model.prepareDiary()
            try await wait { ai.messages.count == 1 }
            try require(model.draft.page == "diary" && model.isThinking && !model.save(), "pending diary cannot save")
            try require(ai.messages[0].filter { $0.role == .user }.map(\.content) == ["我在河边散步，看见一只白鸟。"], "diary sends user facts only")
            ai.reply("我在河边散步，看见一只白鸟。")
            try await wait { !model.isThinking }
            try require(model.draft.diary == "我在河边散步，看见一只白鸟。", "AI diary output is retained")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: "past", timeMark: "昨天", transcript: transcript(), page: "chat")
            model.prepareDiary()
            try await wait { ai.messages.count == 1 }
            model.setDiaryEnabled(false)
            try require(!model.isThinking && model.save(), "turning diary off cancels generation and allows transcript-only save")
            ai.reply("晚到日记不能写进已保存记录")
            await drain()
            try require(model.entries.count == 1 && !model.entries[0].diaryEnabled && model.entries[0].diary == nil && model.draft.page == "card", "late diary cannot mutate saved result")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: "past", timeMark: "昨天", transcript: transcript(), page: "chat")
            model.prepareDiary()
            try await wait { ai.messages.count == 1 }
            model.editDiary("这是我亲手改写的日记。")
            ai.reply("迟到的模型输出")
            await drain()
            try require(model.draft.diary == "这是我亲手改写的日记。" && !model.isThinking, "late completion never overwrites handwriting")
            model.ensureDiary()
            try require(ai.messages.count == 1, "existing diary never triggers regeneration")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: "past", timeMark: "昨天", transcript: transcript(), page: "chat")
            model.prepareDiary()
            try await wait { ai.messages.count == 1 }
            model.back()
            ai.reply("离页后不该写入的日记")
            await drain()
            try require(model.draft.page == "chat" && model.draft.diary == nil && !model.isThinking, "leaving diary cancels and prevents late mutation")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            let long = (0..<33).map { TranscriptMessage(role: $0 % 2 == 0 ? .user : .ai, text: "第\($0)句话") }
            model.draft = RecallDraft(kind: "past", timeMark: "昨天", transcript: long, page: "chat")
            model.prepareDiary()
            try require(!model.isThinking && ai.messages.isEmpty && model.draft.diary == OfflineGuide.diary(transcript: long), "more than 32 messages always uses local diary")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: "past", timeMark: "昨天", transcript: transcript(), page: "chat")
            model.prepareDiary()
            try await wait { ai.messages.count == 1 }
            ai.fail()
            try await wait { !model.isThinking }
            try require(model.draft.diary == OfflineGuide.diary(transcript: transcript()) && model.guidanceNotice == "已按原话整理" && model.guidanceDetail != nil,
                        "diary network failure is a clearly identified fact-only fallback with optional error details")
            passed += 1
        }
        do {
            let ai = ControlledAI(), model = create(ai, root)
            model.draft = RecallDraft(kind: "now", transcript: transcript(), page: "chat")
            model.prepareDiary(); try await wait { ai.messages.count == 1 }
            ai.reply(" \n "); try await wait { !model.isThinking }
            try require(model.draft.diary == OfflineGuide.diary(transcript: transcript()) && model.guidanceNotice == "已按原话整理" && model.guidanceDetail?.contains("未返回日记正文") == true,
                        "empty provider output must not claim a successful model-written diary")
            passed += 1
        }
        do {
            let fixture = StorageFixture(root)
            let originalDraft = RecallDraft(kind: "past", timeMark: "去年", transcript: transcript(), aiEnabled: false,
                                            previousDiary: "上一时间的日记备份。", page: "past-time", pendingEntryID: "previously-written")
            let original = try originalDraft.makeEntry(id: "previously-written")
            try fixture.journal.save(original)
            try fixture.drafts.save(originalDraft)
            let model = fixture.model()
            model.setPendingTime("  ")
            try require(model.draft.pendingEntryID == nil && model.draft.timeMark == nil && model.draft.previousDiary == nil,
                        "clearing time must discard the previous pending save identity and unrelated diary backup")
            model.setPendingTime("今年")
            model.draft.transcript = [TranscriptMessage(role: .user, text: "这是另一段回忆。")]
            try require(model.save(), "new time context must save")
            let records = try fixture.journal.load()
            try require(records.count == 2 && records.contains(original), "new context must never replace the previous saved memory")
            passed += 1
        }
        do {
            let fixture = StorageFixture(root), original = fullDraft("旧草稿的全部文字")
            try fixture.drafts.save(original)
            let bytes = try fixture.blockDraft()
            let model = fixture.model()
            try require(model.errorMessage != nil, "unreadable startup draft must report an error")
            try fixture.restoreDraft(bytes)
            model.retryStorage()
            try require(model.draft == original && model.errorMessage == nil && !model.hasDraftRecoveryConflict, "retry must hydrate a never-restored draft before enabling writes")
            try require(Data(contentsOf: fixture.drafts.fileURL) == bytes, "read-only hydration preserves original draft bytes")
            model.go("account")
            let reloaded = try fixture.drafts.load()
            try require(reloaded?.note == original.note && reloaded?.transcript == original.transcript, "navigation after recovery preserves restored content")
            passed += 1
        }
        do {
            let fixture = StorageFixture(root)
            try fixture.drafts.save(RecallDraft(kind: "now", note: "之前已落盘的文字", page: "now-note"))
            let model = fixture.model(), bytes = try fixture.blockDraft()
            model.draft.note = "写入失败期间新输入的长文"
            try require(model.errorMessage != nil, "failed persistence must surface an error")
            try fixture.restoreDraft(bytes)
            model.retryStorage()
            try require(model.errorMessage == nil && !model.hasDraftRecoveryConflict, "runtime write failure is retried without a false startup conflict")
            try require(fixture.model().draft == model.draft, "retry must persist newer in-memory edits before clearing the error")
            passed += 1
        }
        for keepCurrent in [true, false] {
            let fixture = StorageFixture(root), original = fullDraft("之前完整的草稿")
            try fixture.drafts.save(original)
            let bytes = try fixture.blockDraft(), model = fixture.model()
            let current = RecallDraft(mood: .lonely, labels: ["孤单"], kind: "now", note: "读取失败后新写的内容\n包括换行和空格  ", aiEnabled: false, page: "now-note")
            model.draft = current
            try fixture.restoreDraft(bytes)
            model.errorMessage = nil
            try require(!model.save() && model.errorMessage != nil && model.draft == current, "saving before startup recovery must refuse the write and redisplay recovery guidance")
            try require(Data(contentsOf: fixture.drafts.fileURL) == bytes, "a now-readable file cannot bypass explicit startup recovery")
            model.retryStorage()
            try require(model.hasDraftRecoveryConflict && model.draft == current && !model.save(), "startup recovery must protect both differing drafts until a choice is made")
            try require(Data(contentsOf: fixture.drafts.fileURL) == bytes, "conflict discovery cannot overwrite the old draft")
            try require(model.resolveDraftRecovery(keepCurrent: keepCurrent), "both explicit recovery choices must succeed")
            guard let backup = model.recoveryBackupURL else { throw CheckError.failed("recovery choice must produce an accessible backup") }
            let backedUpDraft = try JSONDraftRepository(fileURL: backup).load()
            try require(backedUpDraft == (keepCurrent ? original : current), "backup must contain the entire unchosen draft, including all fields")
            if keepCurrent { try require(Data(contentsOf: backup) == bytes, "old-draft backup must preserve exact original envelope bytes") }
            let expected = keepCurrent ? current : original
            try require(model.draft == expected && fixture.model().draft == expected && !model.hasDraftRecoveryConflict, "chosen draft must survive restart")
            passed += 1
        }
        for keepCurrent in [true, false] {
            let fixture = StorageFixture(root), original = fullDraft("恢复写入失败时仍保留的旧稿")
            try fixture.drafts.save(original)
            let bytes = try fixture.blockDraft(), model = fixture.model()
            model.draft = RecallDraft(kind: "now", note: "恢复写入失败时仍保留的新稿", page: "now-note")
            let current = model.draft
            try fixture.restoreDraft(bytes)
            model.retryStorage()
            try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: fixture.drafts.fileURL.path)
            let result = model.resolveDraftRecovery(keepCurrent: keepCurrent)
            try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: fixture.drafts.fileURL.path)
            try require(!result && model.hasDraftRecoveryConflict && model.errorMessage != nil, "failed primary recovery write must keep the unresolved conflict")
            try require(model.draft == current && Data(contentsOf: fixture.drafts.fileURL) == bytes, "primary write failure must preserve both in-memory and disk drafts")
            guard let backup = model.recoveryBackupURL else { throw CheckError.failed("successful backup remains available after primary write failure") }
            let backedUpDraft = try JSONDraftRepository(fileURL: backup).load()
            try require(backedUpDraft == (keepCurrent ? original : current), "backup remains complete even when writing the chosen draft fails")
            try require(model.resolveDraftRecovery(keepCurrent: keepCurrent), "recovery can be retried after a failed primary write")
            passed += 1
        }
        do {
            let fixture = StorageFixture(root), original = fullDraft("必须保留的旧草稿")
            try fixture.drafts.save(original)
            let bytes = try fixture.blockDraft(), model = fixture.model()
            model.draft.note = "必须保留的新输入"
            let current = model.draft
            try fixture.restoreDraft(bytes)
            model.retryStorage()
            try write("阻止创建备份目录", to: fixture.directory.appendingPathComponent("RecoveredDrafts"))
            try require(!model.resolveDraftRecovery(keepCurrent: true) && model.hasDraftRecoveryConflict && model.errorMessage != nil, "backup failure must not claim a successful recovery")
            try require(model.draft == current && Data(contentsOf: fixture.drafts.fileURL) == bytes, "failed backup must preserve both drafts")
            passed += 1
        }
        do {
            let fixture = StorageFixture(root), original = fullDraft("发现时的旧草稿")
            try fixture.drafts.save(original)
            let bytes = try fixture.blockDraft(), model = fixture.model()
            model.draft.note = "本轮输入"
            let current = model.draft
            try fixture.restoreDraft(bytes)
            model.retryStorage()
            var changed = original; changed.note = "选择前磁盘草稿已更新"
            try fixture.drafts.save(changed)
            try require(!model.resolveDraftRecovery(keepCurrent: true), "stale recovery choice must be rejected")
            let stored = try fixture.drafts.load()
            try require(stored == changed && model.draft == current, "a changed disk draft cannot be overwritten by a stale recovery choice")
            model.retryStorage()
            try require(model.hasDraftRecoveryConflict, "re-reading changed storage allows a fresh choice")
            passed += 1
        }
        do {
            let fixture = StorageFixture(root)
            try fixture.journal.save(JournalEntry(mood: .calm, note: "清理测试记录"))
            try fixture.drafts.save(fullDraft("清理测试草稿"))
            let model = fixture.model()
            let cache = model.temporaryExportDirectory
            try require(cache == fixture.directory.appendingPathComponent("TemporaryExports", isDirectory: true), "fixtures must isolate their temporary exports")
            let card = cache.appendingPathComponent("MiloCardShares/private.png")
            let export = cache.appendingPathComponent("MILO-Export-\(UUID().uuidString)/MILO-回忆.json")
            let backup = fixture.directory.appendingPathComponent("RecoveredDrafts/draft-test.json")
            let unrelated = cache.appendingPathComponent("another-app/private.txt")
            let nonExport = cache.appendingPathComponent("MILO-Export-personal-not-a-uuid/keep.txt")
            let externalExport = root.appendingPathComponent("Files/MILO-回忆.json")
            let otherFixture = StorageFixture(root)
            let otherCard = JournalModel.temporaryExportDirectory(for: otherFixture.directory).appendingPathComponent("MiloCardShares/private.png")
            for url in [card, export, backup, unrelated, nonExport, externalExport, otherCard] { try write("敏感内容", to: url) }
            try require(model.clearLocalData(), "clearing local data must succeed after deleting app-owned caches")
            let records = try fixture.journal.load(), savedDraft = try fixture.drafts.load()
            try require(records.isEmpty && savedDraft == nil && model.entries.isEmpty && model.draft == RecallDraft(), "successful clear must erase both canonical stores and in-memory draft")
            for url in [card, export, backup] { try require(!FileManager.default.fileExists(atPath: url.path), "cleared data must include private card, export and recovery backup caches") }
            for url in [unrelated, nonExport, externalExport, otherCard] { try require(FileManager.default.fileExists(atPath: url.path), "cleanup cannot remove unrelated files, user exports or other fixtures") }
            try require(model.recoveryBackupURL == nil && model.errorMessage == nil, "successful deletion clears obsolete recovery state")
            passed += 1
        }
        do {
            let fixture = StorageFixture(root), original = JournalEntry(mood: .calm, note: "缓存清理失败时不可先删除的记录")
            try fixture.journal.save(original)
            let model = fixture.model()
            try write("这里故意是一个文件", to: model.temporaryExportDirectory)
            try require(!model.clearLocalData() && model.errorMessage != nil, "cache cleanup failure must not report successful deletion")
            let records = try fixture.journal.load()
            try require(records == [original], "detectable cache cleanup failure must leave canonical records intact")
            passed += 1
        }
        do {
            let fixture = StorageFixture(root), original = JournalEntry(mood: .calm, note: "备份删除失败时保留的记录")
            try fixture.journal.save(original)
            let model = fixture.model(), backupDirectory = fixture.directory.appendingPathComponent("RecoveredDrafts")
            try write("需清理的备份", to: backupDirectory.appendingPathComponent("draft.json"))
            // Foundation enforces file immutable flags even when tests are run
            // by the owner; restore the flag before this isolated fixture exits.
            let immutableFile = backupDirectory.appendingPathComponent("draft.json")
            try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: immutableFile.path)
            let result = model.clearLocalData()
            try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: immutableFile.path)
            try require(!result && model.errorMessage != nil, "recovery-backup deletion failure must not report success")
            let records = try fixture.journal.load()
            try require(records == [original] && FileManager.default.fileExists(atPath: immutableFile.path), "failed backup cleanup preserves records and remaining backup")
            passed += 1
        }
        for bytes in [Data("{broken".utf8), Data("{\"schemaVersion\":999,\"draft\":null}".utf8)] {
            let fixture = StorageFixture(root), original = JournalEntry(mood: .calm, note: "另一份可读记录")
            try fixture.journal.save(original)
            try bytes.write(to: fixture.drafts.fileURL, options: .atomic)
            let model = fixture.model()
            model.draft.note = "不能覆盖未知文件的新文字"
            model.retryStorage(); model.go("account")
            try require(!model.save() && !model.clearLocalData(), "unsupported or malformed draft blocks destructive operations")
            let records = try fixture.journal.load()
            try require(Data(contentsOf: fixture.drafts.fileURL) == bytes && records == [original], "startup, retry, navigation and clear preserve unreadable bytes and companion journal")
            passed += 1
        }
        do {
            let fixture = StorageFixture(root), draft = fullDraft("回忆文件未知版本时保留草稿")
            try fixture.drafts.save(draft)
            let bytes = Data("{\"schemaVersion\":999,\"entries\":[]}".utf8)
            try bytes.write(to: fixture.journal.fileURL, options: .atomic)
            let model = fixture.model()
            model.retryStorage()
            try require(!model.isLoaded && model.errorMessage != nil && !model.save() && !model.clearLocalData(), "draft retry cannot dismiss a companion journal read failure")
            try require(Data(contentsOf: fixture.journal.fileURL) == bytes && fixture.model().draft == draft, "unknown journal bytes and valid draft survive all blocked mutations")
            passed += 1
        }
        print("PASS: \(passed) isolated offline AI and storage checks; no HTTP requests, real keys, emails or user records used.")
    }
}
