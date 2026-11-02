import Foundation
import Testing
@testable import MiloCore

@Test func fifteenMoodsKeepExactDescriptorVocabulary() {
    #expect(Mood.allCases.count == 15)
    #expect(Mood.calm.descriptorWords == ["平静", "安稳", "松弛", "清醒", "踏实", "淡然", "宁静", "柔和", "从容", "平衡", "舒展", "自在"])
    #expect(Mood.heavy.descriptorWords == ["沉重", "疲惫", "压着", "迟滞", "难过", "失落", "孤独", "担心", "压抑", "委屈", "害怕", "遗憾"])
    #expect(Mood.joyful.descriptorWords == ["雀跃", "兴奋", "欢欣", "想庆祝", "轻盈", "温暖", "喜悦", "期待", "安心", "满足", "有力量", "被理解"])
    for mood in Mood.allCases {
        #expect(mood.descriptorWords.count == 12)
        #expect(Set(mood.descriptorWords).count == 12)
    }
}

@Test func schemaOneReadIsNonMutatingAndNextSaveMigratesEveryField() throws {
    let bytes = Data(#"{"schemaVersion":1,"entries":[{"id":"ABCDEF00-0000-4000-8000-000000000001","createdAt":1000,"kind":"now","mood":{"valence":0,"labels":[],"emotionId":"calm"},"note":"旧回忆👩🏽‍🚀\n第二行","diaryEnabled":false}]}"#.utf8)
    let io = ParityMemoryIO(bytes: bytes)
    let repository = JSONJournalRepository(fileURL: parityURL, fileIO: io)
    let old = try #require(repository.load().first)
    #expect(io.bytes == bytes)
    #expect(io.writes == 0)
    #expect(old.note == "旧回忆👩🏽‍🚀\n第二行")
    let past = pastEntry()
    let saved = try repository.save(past)
    #expect(saved == [past, old])
    #expect(try JSONJournalRepository(fileURL: parityURL, fileIO: io).load() == saved)
    let savedBytes = try #require(io.bytes)
    let payload = try #require(JSONSerialization.jsonObject(with: savedBytes) as? [String: Any])
    #expect(payload["schemaVersion"] as? Int == 2)
}

@Test func failedMigrationAndFutureRecordsNeverRewriteBytes() throws {
    let bytes = Data(#"{"schemaVersion":1,"entries":[]}"#.utf8)
    let io = ParityMemoryIO(bytes: bytes)
    let repository = JSONJournalRepository(fileURL: parityURL, fileIO: io)
    io.failWrite = true
    #expect(throws: ParityIOError.write) { try repository.save(pastEntry()) }
    #expect(io.bytes == bytes)
    let future = Data(#"{"schemaVersion":99,"entries":{"unrecognized":"future shape"}}"#.utf8)
    io.bytes = future
    #expect(throws: JournalError.unsupportedSchema(99)) { try repository.load() }
    #expect(throws: JournalError.unsupportedSchema(99)) { try repository.delete(id: "anything") }
    #expect(io.bytes == future)
}

@Test func schemaTwoPastRoundTripTemplateUpdateAndDeleteAreAtomic() throws {
    let io = ParityMemoryIO()
    let repository = JSONJournalRepository(fileURL: parityURL, fileIO: io)
    var entry = pastEntry()
    #expect(try repository.save(entry) == [entry])
    #expect(try repository.load() == [entry])
    entry.stickerTemplate = .orbitTheatre
    #expect(try repository.save(entry).first?.stickerTemplate == .orbitTheatre)
    let bytes = io.bytes
    let writes = io.writes
    #expect(try repository.delete(id: "missing") == [entry])
    #expect(io.writes == writes)
    io.failWrite = true
    #expect(throws: ParityIOError.write) { try repository.delete(id: entry.id) }
    #expect(io.bytes == bytes)
    #expect(try repository.load() == [entry])
    io.failWrite = false
    #expect(try repository.delete(id: entry.id).isEmpty)
    #expect(try repository.load().isEmpty)
}

@Test func nonUUIDHarmonyIdentifiersArePreservedAndInvalidDomainRejected() throws {
    let repository = JSONJournalRepository(fileURL: parityURL, fileIO: ParityMemoryIO())
    let entry = JournalEntry(id: "milo-1751234567890_ab12", mood: .sad, note: "still here")
    #expect(try repository.save(entry).first?.id == entry.id)
    for id in ["", ".", "..", "../entry", "a/b", "a b", "a\nb", String(repeating: "x", count: 129)] {
        #expect(throws: JournalError.self) { try repository.save(JournalEntry(id: id, mood: .calm)) }
    }
}

@Test func deletingAllMemoriesIsAtomicAndValidatesExistingBytes() throws {
    let io = ParityMemoryIO()
    let repository = JSONJournalRepository(fileURL: parityURL, fileIO: io)
    let first = pastEntry()
    let second = JournalEntry(id: "another-memory", createdAt: 1_000, mood: .bright, note: "要一起保留")
    try repository.save(first)
    try repository.save(second)
    let bytes = io.bytes
    io.failWrite = true
    #expect(throws: ParityIOError.write) { try repository.deleteAll() }
    #expect(io.bytes == bytes)
    #expect(try repository.load() == [first, second])
    io.failWrite = false
    let writes = io.writes
    #expect(try repository.deleteAll().isEmpty)
    #expect(io.writes == writes + 1)
    #expect(try repository.load().isEmpty)

    for invalid in ["broken bytes", #"{"schemaVersion":99,"entries":[]}"#] {
        let bytes = Data(invalid.utf8)
        io.bytes = bytes
        let writes = io.writes
        #expect(throws: JournalError.self) { try repository.deleteAll() }
        #expect(io.bytes == bytes && io.writes == writes)
    }
}

@Test func nowJourneyAllowsBlankAndDescriptorLimitResets() throws {
    var draft = RecallDraft()
    draft.selectMood(.bright)
    for word in Mood.bright.descriptorWords.prefix(4) { draft.toggleLabel(word) }
    #expect(draft.labels == ["明亮", "开朗", "有希望"])
    draft.toggleLabel("开朗")
    #expect(draft.labels == ["明亮", "有希望"])
    draft.chooseKind("now")
    draft.note = " \n "
    let entry = try draft.makeEntry(id: "now-1", createdAt: 1)
    #expect(entry.kind == "now" && entry.note.isEmpty)
    #expect(!entry.diaryEnabled)
    #expect(entry.labels == ["明亮", "有希望"])
    draft.page = "words"
    draft.goBack()
    #expect(draft.page == "home" && draft.labels.isEmpty)
    draft.selectMood(.low)
    #expect(draft.transcript.isEmpty && draft.note.isEmpty && draft.labels.isEmpty)
}

@Test func presentConversationAndOptionalDiaryRoundTripWithoutLosingNote() throws {
    let io = ParityMemoryIO(), repository = JSONJournalRepository(fileURL: parityURL, fileIO: ParityMemoryIO())
    var draft = RecallDraft(kind: "now", note: "我自己写下的补充。", transcript: [.init(role: .user, text: "今天很累。", ts: 1)], aiEnabled: false, diaryEnabled: false, page: "chat")
    draft.goBack()
    #expect(draft.page == "classify" && draft.transcript.count == 1)
    let raw = try draft.makeEntry(id: "present-chat", createdAt: 2)
    #expect(raw.note == "我自己写下的补充。" && raw.transcript == draft.transcript && raw.diary == nil && !raw.diaryEnabled)
    #expect(try repository.save(raw).first == raw)
    draft.diaryEnabled = true; draft.diary = "今天很累。"
    let diary = try draft.makeEntry(id: "present-diary", createdAt: 3)
    #expect(try repository.save(diary).first == diary)
    #expect(try repository.load().first == diary)
    #expect(diary.kind == "now" && diary.timeMark == nil && diary.diaryEnabled)
    let drafts = JSONDraftRepository(fileURL: parityURL, fileIO: io)
    try drafts.save(draft)
    #expect(try drafts.load() == draft)
    let exported = try DiaryExport.json(entries: [raw, diary])
    #expect(String(decoding: exported, as: UTF8.self).contains("今天很累"))
}

@Test func presentDiaryUsesBackwardReadableEncodingAndRejectsInvalidFlag() throws {
    let entry = JournalEntry(id: "present-diary-compat", createdAt: 2, mood: .low, kind: "now", transcript: [.init(role: .user, text: "今天很累👩🏽‍🚀\n第二行", ts: 1)], diary: "今天很累👩🏽‍🚀\n第二行", diaryEnabled: true)
    let bytes = try JSONEncoder().encode(entry)
    var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    #expect(object["kind"] as? String == "now")
    #expect(object["diaryEnabled"] as? Bool == false)
    #expect(object["presentDiaryEnabled"] as? Bool == true)
    #expect(try JSONDecoder().decode(JournalEntry.self, from: bytes) == entry)
    object["kind"] = "past"; object["timeMark"] = "昨天"
    #expect(throws: JournalError.self) { try JSONDecoder().decode(JournalEntry.self, from: JSONSerialization.data(withJSONObject: object)) }
}

@Test func pausesAreConservativeAndIncludeExplicitNoDiaryEndings() {
    for text in ["暂停", "先停一下", "先到这里，也不用生成日记", "不聊了。"] { #expect(OfflineGuide.wantsToPause(text)) }
    for text in ["先别建议", "那时候我不想说，但现在可以了", "同事说算了但我还想继续"] { #expect(!OfflineGuide.wantsToPause(text)) }
}

@Test func pastJourneyPreservesDraftOnBackAndClearsChangedTimeContextOnly() throws {
    var draft = RecallDraft(mood: .calm, labels: ["平静"])
    draft.chooseKind("past")
    let blankRejected = !draft.selectTimeMark(" \n")
    #expect(blankRejected)
    let firstAccepted = draft.selectTimeMark(" 昨天 ")
    #expect(firstAccepted)
    draft.transcript = [.init(role: .ai, text: OfflineGuide.opening(timeMark: "昨天"), ts: 1), .init(role: .user, text: "走过河边。", ts: 2)]
    draft.inputText = "还没发完的 👩🏽‍🚀"
    draft.diary = "我编辑过的原文。"
    draft.aiEnabled = false
    draft.page = "diary"
    draft.goBack()
    #expect(draft.page == "chat" && draft.inputText == "还没发完的 👩🏽‍🚀")
    draft.goBack()
    #expect(draft.page == "past-time")
    let sameAccepted = draft.selectTimeMark("昨天")
    #expect(sameAccepted)
    #expect(draft.transcript.count == 2 && draft.diary != nil)
    let entry = try draft.makeEntry(id: "past-1", createdAt: 3)
    #expect(entry.diary == "我编辑过的原文。" && entry.transcript == draft.transcript)
    draft.diaryEnabled = false
    let conversation = try draft.makeEntry(id: "past-2", createdAt: 4)
    #expect(conversation.diary == nil && conversation.transcript.count == 2)
    let changedAccepted = draft.selectTimeMark("几年前")
    #expect(changedAccepted)
    #expect(draft.transcript.isEmpty && draft.diary == nil && draft.inputText.isEmpty)
    #expect(draft.mood == .calm && draft.labels == ["平静"] && !draft.aiEnabled)
    #expect(throws: JournalError.self) { try draft.makeEntry() }
}

@Test func interruptedDraftRestoresRawInputAndAtomicClear() throws {
    let io = ParityMemoryIO()
    let repository = JSONDraftRepository(fileURL: parityURL, fileIO: io)
    let draft = RecallDraft(mood: .anxious, labels: ["焦灼"], kind: "past", timeMark: "去年夏天", transcript: [.init(role: .user, text: "记忆", ts: 1)], aiEnabled: false, inputText: "  未发送\n👩🏽‍🚀 ", diary: "编辑中\n", page: "diary")
    try repository.save(draft)
    #expect(try JSONDraftRepository(fileURL: parityURL, fileIO: io).load() == draft)
    let bytes = io.bytes
    io.failWrite = true
    #expect(throws: ParityIOError.write) { try repository.clear() }
    #expect(io.bytes == bytes)
    io.failWrite = false
    try repository.clear()
    #expect(try repository.load() == nil)
}

@Test func previousDiaryBackupIsOptionalDurableAndScopedToTheConversation() throws {
    let repository = JSONDraftRepository(fileURL: parityURL, fileIO: ParityMemoryIO())
    var draft = RecallDraft(kind: "past", timeMark: "昨天", diary: "新的正文。",
                            previousDiary: "用户修改的上一版👩🏽‍🚀\n保留补充。", page: "diary")
    try repository.save(draft)
    #expect(try repository.load() == draft)

    var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
    legacy.removeValue(forKey: "previousDiary")
    let old = try JSONDecoder().decode(RecallDraft.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(old.previousDiary == nil && old.diary == draft.diary)

    _ = draft.selectTimeMark("昨天")
    #expect(draft.previousDiary == "用户修改的上一版👩🏽‍🚀\n保留补充。")
    _ = draft.selectTimeMark("去年")
    #expect(draft.diary == nil && draft.previousDiary == nil)
    draft.previousDiary = "上一段回忆的正文。"
    draft.chooseKind("now")
    #expect(draft.previousDiary == nil)
    draft.previousDiary = "上一次情绪的正文。"
    draft.selectMood(.bright)
    #expect(draft.previousDiary == nil)
}

@Test func pendingSaveIdentityPersistsIndependentlyAndResetsWithContext() throws {
    let io = ParityMemoryIO()
    let repository = JSONDraftRepository(fileURL: parityURL, fileIO: io)
    var draft = RecallDraft(kind: "past", timeMark: "昨天",
                            transcript: [.init(role: .user, text: "我的原话", ts: 1)],
                            page: "detail", entryID: "browsed-memory", pendingEntryID: "pending-save")
    try repository.save(draft)
    let restored = try repository.load()
    var reopened = try #require(restored)
    #expect(reopened.entryID == "browsed-memory")
    #expect(reopened.pendingEntryID == "pending-save")
    reopened.entryID = "another-memory"
    #expect(reopened.pendingEntryID == "pending-save")
    let entry = try reopened.makeEntry(id: try #require(reopened.pendingEntryID), createdAt: 2)
    #expect(entry.id == "pending-save" && reopened.pendingEntryID == "pending-save")

    // Drafts written before the pending ID was introduced must still decode.
    var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
    legacy.removeValue(forKey: "pendingEntryID")
    let oldDraft = try JSONDecoder().decode(RecallDraft.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(oldDraft.pendingEntryID == nil && oldDraft.entryID == "browsed-memory")

    draft.page = "past-time"
    _ = draft.selectTimeMark("昨天")
    #expect(draft.pendingEntryID == "pending-save")
    _ = draft.selectTimeMark("几年前")
    #expect(draft.pendingEntryID == nil)
    draft.pendingEntryID = "retry-now"
    draft.chooseKind("now")
    #expect(draft.pendingEntryID == nil)
    draft.pendingEntryID = "another-retry"
    draft.selectMood(.bright)
    #expect(draft.pendingEntryID == nil)
    draft.pendingEntryID = "../invalid"
    let bytes = io.bytes
    #expect(throws: JournalError.self) { try repository.save(draft) }
    #expect(io.bytes == bytes)
}

@Test(arguments: ["not JSON", #"{"schemaVersion":1}"#, #"{"schemaVersion":2,"draft":null}"#, #"{"schemaVersion":1,"draft":{}}"#])
func corruptOrFutureDraftCannotBeSavedOverOrCleared(json: String) throws {
    let bytes = Data(json.utf8)
    let io = ParityMemoryIO(bytes: bytes)
    let repository = JSONDraftRepository(fileURL: parityURL, fileIO: io)
    #expect(throws: JournalError.self) { try repository.load() }
    #expect(throws: JournalError.self) { try repository.save(RecallDraft()) }
    #expect(throws: JournalError.self) { try repository.clear() }
    #expect(io.bytes == bytes && io.writes == 0)
}

@Test func offlineGuidanceIsConciseResumableAndDiaryUsesOnlyUserWords() {
    #expect(OfflineGuide.opening(timeMark: "昨天") == "「昨天」，你最先想起什么？")
    #expect(OfflineGuide.opening(timeMark: String(repeating: "很久", count: 20)) == "那段时光里，你最先想起什么？")
    #expect(OfflineGuide.respond(transcript: [.init(role: .user, text: "先这样", ts: 1)]) == "好，先停在这里。")
    #expect(!OfflineGuide.wantsToPause("那时候我不想说，但现在可以了"))
    #expect(OfflineGuide.respond(transcript: [.init(role: .user, text: "我不知道怎么说", ts: 1)]) == OfflineGuide.recordingNotice)
    var messages = [TranscriptMessage(role: .ai, text: "今天你一定很开心。", ts: 0)]
    messages.append(.init(role: .user, text: "  今天很难。\n不想假装开心。  ", ts: 1))
    #expect(OfflineGuide.respond(transcript: messages) == OfflineGuide.recordingNotice)
    messages.append(.init(role: .user, text: "我去了公园。", ts: 2))
    #expect(OfflineGuide.respond(transcript: messages) == OfflineGuide.recordingNotice)
    #expect(OfflineGuide.diary(transcript: messages) == "今天很难。\n不想假装开心。\n\n我去了公园。")
    for i in 3...50 { messages.append(.init(role: .user, text: "继续说", ts: Double(i))) }
    #expect(OfflineGuide.respond(transcript: messages) == OfflineGuide.recordingNotice)
}

@Test func exportsContainFullMemoriesAndOnlyAllowlistedEnvelope() throws {
    let entry = pastEntry()
    let bytes = try DiaryExport.json(entries: [entry], exportedAt: Date(timeIntervalSince1970: 0))
    let payload = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    #expect(Set(payload.keys) == ["schemaVersion", "app", "exportedAt", "entries"])
    #expect(payload["app"] as? String == "MILO")
    #expect(payload["exportedAt"] as? String == "1970-01-01T00:00:00.000Z")
    let exported = try #require(payload["entries"] as? [[String: Any]])
    #expect(try JSONDecoder().decode(JournalEntry.self, from: JSONSerialization.data(withJSONObject: exported[0])) == entry)
    let markdown = DiaryExport.markdown(entries: [entry], timeZone: TimeZone(secondsFromGMT: 0)!)
    #expect(markdown.contains("日记原文。") && markdown.contains("我：我的原话。") && markdown.contains("MILO：你想起什么？"))
    #expect(!String(decoding: bytes, as: UTF8.self).contains("apiKey"))
}

@Test func cardSummaryUsesUserContentPriorityAndStableTicket() {
    var entry = pastEntry()
    #expect(CardCopy(entry: entry).body == "日记原文。")
    #expect(CardCopy(entry: entry).heading == "昨天")
    #expect(CardCopy(entry: entry).labels == "平静 · 安稳")
    entry.diary = nil
    entry.note = "此刻写的第一句。第二句。"
    #expect(CardCopy(entry: entry).body == "此刻写的第一句。")
    entry.note = ""
    #expect(CardCopy(entry: entry).body == "我的原话。")
    let ticket = memoryTicketID(for: entry, timeZone: TimeZone(secondsFromGMT: 0)!)
    #expect(ticket == memoryTicketID(for: entry, timeZone: TimeZone(secondsFromGMT: 0)!))
    #expect(ticket.hasPrefix("ML-700101-03-"))
    entry.transcript = [.init(role: .user, text: String(repeating: "👩🏽‍🚀", count: 60), ts: 1)]
    #expect(CardCopy(entry: entry).body == String(repeating: "👩🏽‍🚀", count: 48) + "…")
}

private func pastEntry() -> JournalEntry {
    JournalEntry(id: "harmony-123_abc", createdAt: 2_000, mood: .calm, labels: ["平静", "安稳"], kind: "past", timeMark: "昨天", transcript: [.init(role: .ai, text: "你想起什么？", ts: 1_000), .init(role: .user, text: "我的原话。", ts: 1_001)], diary: "日记原文。", diaryEnabled: true)
}
private let parityURL = URL(fileURLWithPath: "/memory-fixture/parity.json")
private enum ParityIOError: Error { case write }
private final class ParityMemoryIO: JournalFileIO {
    var bytes: Data?
    var failWrite = false
    var writes = 0
    init(bytes: Data? = nil) { self.bytes = bytes }
    func read(from url: URL) throws -> Data? { bytes }
    func writeAtomically(_ data: Data, to url: URL) throws {
        if failWrite { throw ParityIOError.write }
        writes += 1
        bytes = data
    }
}
