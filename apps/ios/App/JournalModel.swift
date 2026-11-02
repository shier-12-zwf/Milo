import Foundation
import Observation
import MiloCore

@MainActor
@Observable
final class JournalModel {
    var draft = RecallDraft() {
        didSet {
            if draftReady, draftNeedsRecovery, draft != oldValue { editedDuringRecovery = true }
            persistDraft()
        }
    }
    private(set) var entries: [JournalEntry] = []
    var errorMessage: String?
    private(set) var isLoaded = false
    private(set) var isSaving = false
    var isThinking = false
    var guidanceNotice = ""
    private(set) var guidanceDetail: String?
    var settingsReturnPage = "account"
    let account: AccountModel
    let temporaryExportDirectory: URL
    private(set) var recoveryBackupURL: URL?
    private let directory: URL
    private let repository: any JournalRepository
    private let draftRepository: JSONDraftRepository
    private var draftReady = false
    private var draftWritable = true
    private var draftNeedsRecovery = false
    private var editedDuringRecovery = false
    private var recoveredDraft: RecallDraft?
    private var conversationTask: Task<Void, Never>?
    private var generation = UUID()
    private enum GenerationKind { case opening, response, diary }
    private var generationKind: GenerationKind?
    private let injectedAI: Bool
    private var replyFailed = false
    private var replyStopped = false
    private let aiCompletion: @MainActor ([AIMessage]) async throws -> String

    init(repository: any JournalRepository, directory: URL,
         aiCompletion: (@MainActor ([AIMessage]) async throws -> String)? = nil) {
        self.repository = repository
        self.directory = directory
        temporaryExportDirectory = Self.temporaryExportDirectory(for: directory)
        draftRepository = JSONDraftRepository(fileURL: directory.appendingPathComponent("draft.json"))
        let account = AccountModel(directory: directory)
        self.account = account
        injectedAI = aiCompletion != nil
        self.aiCompletion = aiCompletion ?? { messages in try await account.completeAI(messages: messages) }
        draft = RecallDraft(aiEnabled: account.aiSettings.enabled)
        reload()
        do { if let restored = try draftRepository.load() { draft = restored } }
        catch {
            draftWritable = false
            draftNeedsRecovery = true
            errorMessage = "未完成的回忆暂时无法读取，原文件已保留。请先导出已有记录，再重试。"
        }
        draftReady = true
    }
    var hasDraftRecoveryConflict: Bool { recoveredDraft != nil }
    static func temporaryExportDirectory(for directory: URL) -> URL {
        // Screenshot fixtures share the simulator container with the app. Their
        // exports and deletion checks must stay inside their own UUID store.
        let parts = directory.standardizedFileURL.pathComponents
        if let marker = parts.lastIndex(of: "MILO-UITests"), parts.indices.contains(marker + 1),
           UUID(uuidString: parts[marker + 1]) != nil {
            return directory.appendingPathComponent("TemporaryExports", isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
    }
    var selectedEntry: JournalEntry? { entries.first { $0.id == draft.entryID } }
    var canFinishConversation: Bool {
        draft.transcript.contains { $0.role == .user } && draft.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking
    }
    func reload() {
        do { entries = try repository.load(); isLoaded = true; errorMessage = nil }
        catch { isLoaded = false; errorMessage = "暂时无法读取回忆。原来的记录仍被保留，请稍后重试。" }
    }
    func go(_ page: String) {
        if draft.page == "chat" || draft.page == "diary" { cancelGeneration() }
        draft.page = page
    }
    func back() {
        cancelGeneration()
        if draft.page == "ai-settings" {
            draft.page = settingsReturnPage
            resumeConversationAfterSettings()
            return
        }
        draft.goBack()
    }
    func openSettings() {
        guard aiFeatureAvailable else { return }
        settingsReturnPage = draft.page; go("ai-settings")
    }
    func chooseKind(_ kind: String) {
        cancelGeneration(); replyFailed = false; replyStopped = false
        guidanceNotice = ""; guidanceDetail = nil
        draft.chooseKind(kind)
    }
    var hasUnfinishedDraft: Bool { draft.kind != nil && (!draft.transcript.isEmpty || !draft.note.isEmpty || !draft.inputText.isEmpty || draft.diary != nil || draft.previousDiary != nil) }
    private var aiFeatureAvailable: Bool {
        #if MILO_AI_COORDINATOR_TESTS
        // Only the standalone offline coordinator harness compiles this path.
        // Neither Debug nor Release app builds define this flag.
        if injectedAI { return true }
        #endif
        return AIFeaturePolicy.isAvailable
    }
    var aiUnavailableReason: String? {
        guard aiFeatureAvailable else { return AIFeaturePolicy.pausedMessage }
        return draft.aiEnabled ? (injectedAI ? nil : account.aiUnavailableReason) : "AI 已关闭。"
    }
    var chatNotice: String {
        if !aiFeatureAvailable { return "仅本地记录" }
        if isThinking { return guidanceNotice }
        if aiUnavailableReason != nil { return draft.aiEnabled ? "仅本地记录 · AI 未连接" : "仅本地记录 · AI 已关闭" }
        return guidanceNotice
    }
    var chatDetail: String? { aiUnavailableReason ?? guidanceDetail }
    var canRetryReply: Bool { !isThinking && aiUnavailableReason == nil && draft.transcript.last?.role == .user && !OfflineGuide.wantsToPause(draft.transcript.last?.text ?? "") }
    func startPresentConversation() {
        cancelGeneration(); replyFailed = false; replyStopped = false
        draft.chooseKind("now")
        draft.page = "chat"
        draft.diaryEnabled = false
        if draft.transcript.isEmpty {
            draft.transcript.append(TranscriptMessage(role: .ai, text: "想说什么就从那里开始，不用整理好，也可以随时停下。"))
        }
        guidanceNotice = ""; guidanceDetail = nil
    }
    func endConversation() {
        go("home")
        guidanceNotice = ""; guidanceDetail = nil
        // Retain the raw local draft; ending is neither saving an entry nor generating a diary.
    }
    func resumeDraft() {
        guard hasUnfinishedDraft else { return }
        go(draft.diary != nil ? "diary" : !draft.transcript.isEmpty ? "chat" : draft.kind == "now" ? "now-note" : "past-time")
    }
    func stopReply() { cancelGeneration(); replyStopped = true; guidanceNotice = "已停止"; guidanceDetail = nil }
    func retryReply() { guard canRetryReply else { return }; replyFailed = false; replyStopped = false; respondToCurrentConversation() }
    func saveConversation() {
        guard canFinishConversation else { return }
        draft.diaryEnabled = false
        _ = save()
    }
    func openEntry(_ id: String) { draft.entryID = id; go("detail") }
    func startHome() {
        cancelGeneration(); replyFailed = false; replyStopped = false
        guidanceNotice = ""; guidanceDetail = nil
        draft = RecallDraft(aiEnabled: account.aiSettings.enabled)
    }
    func returnHome() { go("home") }
    func beginMoodWords(mood selectedMood: Mood? = nil) {
        let mood = selectedMood ?? draft.mood
        cancelGeneration()
        guidanceNotice = ""; guidanceDetail = nil
        var next = RecallDraft(mood: mood, aiEnabled: account.aiSettings.enabled); next.page = "home-words"; draft = next
    }
    /// Call only after account settings were successfully persisted. Provider,
    /// model, consent and key changes invalidate a request even if AI stays on.
    func aiSettingsDidSave() {
        cancelGeneration(); replyFailed = false; replyStopped = false
        draft.aiEnabled = account.aiSettings.enabled
        guidanceNotice = draft.aiEnabled ? "AI 设置已更新" : "仅本地记录 · AI 已关闭"
        guidanceDetail = nil
    }
    private func resumeConversationAfterSettings() {
        guard draft.page == "chat", !isThinking, !replyFailed, !replyStopped else { return }
        if draft.kind == "now", draft.transcript.isEmpty { startPresentConversation() }
        else if draft.transcript.isEmpty, let time = draft.timeMark {
            startConversation(time: time)
        } else if draft.transcript.last?.role == .user {
            respondToCurrentConversation()
        }
    }
    func setPendingTime(_ value: String) {
        if draft.timeMark != value.trimmingCharacters(in: .whitespacesAndNewlines) { cancelGeneration() }
        var next = draft
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if next.timeMark != nil { next.transcript = []; next.diary = nil; next.previousDiary = nil; next.inputText = "" }
            next.timeMark = nil
            next.pendingEntryID = nil
        } else { _ = next.selectTimeMark(value) }
        next.page = "past-time"; draft = next
    }
    func setAIEnabled(_ enabled: Bool) {
        guard aiFeatureAvailable else { return }
        draft.aiEnabled = enabled
        replyFailed = false
        guidanceDetail = nil
        if !enabled {
            let pending = generationKind
            cancelGeneration()
            if pending == .opening, draft.page == "chat", draft.transcript.isEmpty {
                draft.transcript.append(TranscriptMessage(role: .ai, text: OfflineGuide.opening(mood: draft.mood, timeMark: draft.timeMark ?? "那段时光")))
            } else if pending == .response, draft.page == "chat", draft.transcript.last?.role == .user {
                replyFailed = false
            } else if pending == .diary, draft.page == "diary", draft.diaryEnabled, draft.diary == nil {
                draft.diary = OfflineGuide.diary(transcript: draft.transcript)
            }
            guidanceNotice = "仅本地记录 · AI 已关闭"
        } else { guidanceNotice = "下次发送将尝试连接 AI" }
    }
    func retryStorage() {
        reload()
        do {
            let stored = try draftRepository.load()
            if draftNeedsRecovery {
                if editedDuringRecovery, let stored, stored != draft {
                    recoveredDraft = stored
                    errorMessage = "找到了之前的草稿。请选择继续当前内容，或恢复旧草稿；另一份会保留为备份。"
                    return
                }
                if editedDuringRecovery {
                    try draftRepository.save(draft)
                } else {
                    cancelGeneration()
                    replaceDraftWithoutWriting(stored ?? RecallDraft(aiEnabled: account.aiSettings.enabled))
                }
                finishDraftRecovery()
            } else {
                // After a write failure the in-memory draft is newer than disk.
                // A readable file alone does not mean that those edits were saved.
                try draftRepository.save(draft)
            }
            draftWritable = true
        } catch { errorMessage = "草稿仍无法恢复或保存，原文件和当前输入均已保留，请稍后重试。" }
    }
    @discardableResult
    func resolveDraftRecovery(keepCurrent: Bool) -> Bool {
        guard let recoveredDraft else { return false }
        do {
            guard try draftRepository.load() == recoveredDraft else {
                self.recoveredDraft = nil
                errorMessage = "旧草稿已发生变化，请重试读取后再选择。"
                return false
            }
            let backupDirectory = directory.appendingPathComponent("RecoveredDrafts", isDirectory: true)
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let backup = backupDirectory.appendingPathComponent("draft-\(UUID().uuidString).json")
            if keepCurrent {
                // Preserve the original envelope bytes, including formatting.
                let original = try Data(contentsOf: draftRepository.fileURL)
                try original.write(to: backup, options: .atomic)
                recoveryBackupURL = backup
                try draftRepository.save(draft)
            } else {
                try JSONDraftRepository(fileURL: backup).save(draft)
                recoveryBackupURL = backup
                try draftRepository.save(recoveredDraft)
                cancelGeneration()
                replaceDraftWithoutWriting(recoveredDraft)
            }
            finishDraftRecovery()
            errorMessage = isLoaded ? nil : "暂时无法读取回忆。原来的记录仍被保留，请稍后重试。"
            return true
        } catch {
            errorMessage = "草稿备份或恢复没有完成。两份内容仍被保留，请重试。"
            return false
        }
    }
    private func replaceDraftWithoutWriting(_ value: RecallDraft) {
        draftReady = false; draft = value; draftReady = true
    }
    private func finishDraftRecovery() {
        draftNeedsRecovery = false
        editedDuringRecovery = false
        recoveredDraft = nil
        draftWritable = true
    }
    func startConversation(time: String) {
        cancelGeneration(); replyFailed = false; replyStopped = false
        guidanceNotice = ""; guidanceDetail = nil
        guard draft.selectTimeMark(time) else { return }
        guard draft.transcript.isEmpty else { return }
        let fallback = OfflineGuide.opening(mood: draft.mood, timeMark: draft.timeMark ?? "那段时光")
        guard aiUnavailableReason == nil else {
            draft.transcript.append(TranscriptMessage(role: .ai, text: fallback))
            guidanceNotice = "仅本地记录 · AI 未连接"
            return
        }
        let messages = [AIMessage(role: .system, content: chatInstruction + "用一句温柔的中文问候开启回忆，问一个具体的小问题。"),
                        AIMessage(role: .user, content: "我想记录这份感受。")]
        requestConversationReply(messages: messages, fallback: fallback, kind: .opening)
    }
    func send() {
        let text = draft.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.page == "chat", !text.isEmpty, !isThinking else { return }
        replyStopped = false
        let pauses = OfflineGuide.wantsToPause(text)
        // A diary reflects the conversation it was made from. Navigation keeps
        // edits intact; new content requires a fresh diary, with the previous
        // body available for recovery. Pausing does not add new diary material.
        var next = draft
        if !pauses {
            if let diary = next.diary { next.previousDiary = diary }
            next.diary = nil
        }
        next.transcript.append(TranscriptMessage(role: .user, text: text))
        next.inputText = ""
        draft = next
        if pauses {
            guidanceNotice = "已暂停"; guidanceDetail = nil
            return
        }
        if aiUnavailableReason != nil || replyFailed {
            if replyFailed { guidanceNotice = "回复失败，原话已保留" }
            return
        }
        respondToCurrentConversation()
    }
    private func respondToCurrentConversation() {
        guard draft.page == "chat", draft.transcript.last?.role == .user, !isThinking else { return }
        guard !OfflineGuide.wantsToPause(draft.transcript.last?.text ?? ""), aiUnavailableReason == nil else { return }
        let conversation = Array(draft.transcript.suffix(24))
        let messages = [AIMessage(role: .system, content: chatInstruction)]
            + conversation.map { AIMessage(role: $0.role == .user ? .user : .assistant, content: $0.text) }
        requestConversationReply(messages: messages, fallback: OfflineGuide.respond(transcript: draft.transcript), kind: .response)
    }
    private var chatInstruction: String {
        """
        你是MILO，一个温和、坦诚的倾听伙伴。先回应用户刚说的具体处境，让用户按照自己的节奏把事情说出来，不把对话当作问卷。
        用户只想吐槽或明确说先别建议时，陪他把话说完，不急着分析、说教、建议、提炼意义、成长或积极结论。可以只回应而不提问；确有必要且用户愿意继续时才追问，一次至多一个，避免重复问已说过的事。
        区分用户明确说过的事实、感受与推测，不替用户断定别人的动机，不一味附和，也不虚构经历或诊断。用户主动求助或要求建议时，按请求提供适量、具体的帮助；明确要求两个建议就给两个。
        简洁自然，通常两三句话；复杂处境可稍长，不为字数删掉关键回应。用户说暂停或结束时就接受，不再追问，不擅自总结或生成日记，不催促保存。用户可以只吐槽、聊完就走。
        用户选择的情绪：\(draft.mood.title)；描述词：\(draft.labels.joined(separator: "、"))。
        \(draft.kind == "now" ? "场景：用户在说今天或此刻的事情，不要强迫转向过去回忆。" : "场景：用户想回忆，时间：" + (draft.timeMark ?? "过去") + "。顺着用户说的内容，不强求回忆细节。")
        """
    }
    private func requestConversationReply(messages: [AIMessage], fallback: String, kind: GenerationKind) {
        cancelGeneration()
        let current = generation
        let time = draft.timeMark
        let conversation = draft.transcript
        isThinking = true
        generationKind = kind
        guidanceNotice = "正在回复…"; guidanceDetail = nil
        conversationTask = Task { [weak self] in
            guard let self, !Task.isCancelled, current == generation else { return }
            defer { finishGeneration(current) }
            let reply: String?
            let notice: String
            let detail: String?
            do {
                let value = try await aiCompletion(messages)
                reply = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
                notice = reply == nil ? "回复失败，原话已保留" : ""
                detail = reply == nil ? "模型未返回文字，可重试或检查 AI 设置。" : nil
            } catch {
                reply = nil
                notice = "回复失败，原话已保留"
                detail = error.localizedDescription
            }
            guard !Task.isCancelled, current == generation, draft.page == "chat", draft.aiEnabled,
                  draft.timeMark == time, draft.transcript == conversation else { return }
            guidanceNotice = notice
            guidanceDetail = detail
            replyFailed = reply == nil
            if let reply { draft.transcript.append(TranscriptMessage(role: .ai, text: reply)) }
            else if kind == .opening, draft.transcript.isEmpty {
                draft.transcript.append(TranscriptMessage(role: .ai, text: fallback))
            }
        }
    }
    func prepareDiary() {
        guard canFinishConversation else { return }
        draft.diaryEnabled = true
        go("diary")
        ensureDiary()
    }
    func setDiaryEnabled(_ enabled: Bool) {
        draft.diaryEnabled = enabled
        if enabled { ensureDiary() }
        else {
            cancelGeneration()
            guidanceNotice = "仅收藏原话"; guidanceDetail = nil
        }
    }
    func editDiary(_ text: String) {
        // Also protect edits made outside the disabled editor (for example, a
        // restored draft) from a provider that returns after cancellation.
        if generationKind == .diary { cancelGeneration() }
        draft.diary = text
    }
    func restorePreviousDiary() {
        guard let previous = draft.previousDiary else { return }
        cancelGeneration()
        var next = draft
        next.previousDiary = next.diary
        next.diary = previous
        draft = next
        guidanceNotice = "已恢复上一版"; guidanceDetail = nil
    }
    func ensureDiary() {
        guard draft.page == "diary", draft.diaryEnabled, draft.diary == nil, !isThinking else { return }
        let conversation = draft.transcript
        let fallback = OfflineGuide.diary(transcript: conversation)
        guard aiUnavailableReason == nil, conversation.count <= 32 else {
            draft.diary = fallback
            guidanceNotice = "已按原话整理"
            guidanceDetail = conversation.count > 32 ? "对话较长，已在本机按你的原话整理。" : aiUnavailableReason
            return
        }
        cancelGeneration()
        let current = generation
        let time = draft.timeMark
        let initialDiary = draft.diary
        isThinking = true; generationKind = .diary
        guidanceNotice = "正在整理…"; guidanceDetail = nil
        let messages = [AIMessage(role: .system, content: "你是MILO的记录助手。仅使用用户明确说过的事实和感受，保留原意与情绪强度，整理为第一人称中文日记。说了一点就写一点，不为凑字数扩写。不虚构人物、事件、感觉、动机或细节，不把推测写成事实，不添加用户没说过的释然、成长或结论。不诊断、不说教、不写标题，只输出日记正文。记录时间：\(time ?? "今天 / 此刻")。")]
            + conversation.filter { $0.role == .user }.map { AIMessage(role: .user, content: $0.text) }
        conversationTask = Task { [weak self] in
            guard let self, !Task.isCancelled, current == generation else { return }
            defer { finishGeneration(current) }
            let text: String
            let notice: String
            let detail: String?
            do {
                text = try await aiCompletion(messages)
                let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                notice = empty ? "已按原话整理" : "日记已整理"
                detail = empty ? "模型未返回日记正文，已在本机按你的原话整理。" : nil
            } catch {
                text = fallback
                notice = "已按原话整理"
                detail = error.localizedDescription
            }
            guard !Task.isCancelled, current == generation, draft.page == "diary", draft.diaryEnabled,
                  draft.aiEnabled, draft.timeMark == time, draft.transcript == conversation,
                  draft.diary == initialDiary else { return }
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.diary = clean.isEmpty ? fallback : clean
            guidanceNotice = notice
            guidanceDetail = detail
        }
    }
    @discardableResult
    func save() -> Bool {
        guard draftWritable else {
            errorMessage = hasDraftRecoveryConflict
                ? "找到了之前的草稿。请选择继续当前内容，或恢复旧草稿；另一份会保留为备份。"
                : "之前的草稿尚未恢复，请先重试读取。原文件和当前输入均已保留。"
            return false
        }
        guard isLoaded, !isSaving, !isThinking else { return false }
        isSaving = true; defer { isSaving = false }
        var recordWritten = false
        do {
            var pending = draft
            if pending.pendingEntryID == nil { pending.pendingEntryID = UUID().uuidString }
            try draftRepository.save(pending)
            draftReady = false; draft = pending; draftReady = true
            let entry = try pending.makeEntry(id: pending.pendingEntryID!)
            entries = try repository.save(entry)
            recordWritten = true
            var next = RecallDraft(aiEnabled: account.aiSettings.enabled); next.page = "card"; next.entryID = entry.id
            try draftRepository.save(next)
            draftReady = false; draft = next; draftReady = true
            errorMessage = nil
            return true
        } catch {
            errorMessage = recordWritten
                ? "回忆已保存，但草稿状态暂时未能更新。请重试，不会重复收藏。"
                : "这次没有保存成功。你写下的文字还在，可以再试一次。"
            return false
        }
    }

    func setTemplate(_ template: CardTemplate) {
        guard var entry = selectedEntry else { return }
        entry.stickerTemplate = template
        do { entries = try repository.save(entry) }
        catch { errorMessage = "卡片样式没有保存成功，请重试。" }
    }
    func deleteSelected() {
        guard let id = draft.entryID else { return }
        do { entries = try repository.delete(id: id); draft.entryID = nil; go("timeline") }
        catch { errorMessage = "没有删除成功，原回忆仍然保留。" }
    }
    func clearLocalData() -> Bool {
        // Account flow calls this only after the explicit local-delete confirmation or verified remote deletion.
        do {
            // Never erase a readable store before discovering an unsupported or
            // damaged companion file. Cleanup errors are surfaced, not ignored.
            _ = try repository.load()
            _ = try draftRepository.load()
            cancelGeneration()
            try clearTemporaryExports()
            let backups = directory.appendingPathComponent("RecoveredDrafts", isDirectory: true)
            try removeIfPresent(backups)
            entries = try repository.deleteAll()
            try draftRepository.clear()
            replaceDraftWithoutWriting(RecallDraft(aiEnabled: account.aiSettings.enabled))
            finishDraftRecovery()
            recoveryBackupURL = nil
            isLoaded = true; errorMessage = nil
            return true
        } catch { errorMessage = "有部分本地内容未能清除，请重试。"; return false }
    }
    private func clearTemporaryExports() throws {
        let manager = FileManager.default
        let children: [URL]
        do { children = try manager.contentsOfDirectory(at: temporaryExportDirectory, includingPropertiesForKeys: nil) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return }
        for child in children {
            let name = child.lastPathComponent
            let isRecordExport = name.hasPrefix("MILO-Export-") && UUID(uuidString: String(name.dropFirst("MILO-Export-".count))) != nil
            if name == "MiloCardShares" || isRecordExport { try manager.removeItem(at: child) }
        }
    }
    private func removeIfPresent(_ url: URL) throws {
        do { try FileManager.default.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { return }
    }
    func logout() { cancelGeneration(); draft.page = "home" }
    func exportJSON() -> Data? {
        do { return try DiaryExport.json(entries: entries) }
        catch { errorMessage = "导出失败，请稍后重试。"; return nil }
    }
    func exportMarkdown() -> String? { DiaryExport.markdown(entries: entries) }
    private func cancelGeneration() {
        if isThinking { guidanceNotice = "" }
        generation = UUID(); conversationTask?.cancel(); conversationTask = nil; generationKind = nil; isThinking = false
    }
    private func finishGeneration(_ current: UUID) {
        guard current == generation else { return }
        conversationTask = nil; generationKind = nil; isThinking = false
    }
    private func persistDraft() {
        guard draftReady, draftWritable else { return }
        do { try draftRepository.save(draft) }
        catch { errorMessage = "草稿暂时未能保存。请保持应用打开，重试后再离开。" }
    }
}
