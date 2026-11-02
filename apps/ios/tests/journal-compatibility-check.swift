import Foundation
#if LEGACY_DECODER
import LegacyMiloCore
#else
import MiloCore
#endif

enum CompatibilityError: Error { case failed(String) }
@main struct CompatibilityChecks {
    static func require(_ value: Bool, _ reason: String) throws { if !value { throw CompatibilityError.failed(reason) } }
    static let words = "合成的旧日记👩🏽‍🚀\n保留原话与换行。"
    static var conversation: [TranscriptMessage] { [.init(role: .user, text: words, ts: 1)] }
    static func main() throws {
        let mode = CommandLine.arguments[1], root = URL(fileURLWithPath: CommandLine.arguments[2])
        let oldJournal = root.appendingPathComponent("legacy-journal.json")
        let oldDraft = root.appendingPathComponent("legacy-draft.json")
        switch mode {
        case "write-legacy":
            let repository = JSONJournalRepository(fileURL: oldJournal)
            try repository.save(JournalEntry(id: "legacy-note", createdAt: 1, mood: .bright, note: words))
            try repository.save(JournalEntry(id: "legacy-past", createdAt: 2, mood: .low, kind: "past", timeMark: "昨天", transcript: conversation, diary: words, diaryEnabled: true))
            try JSONDraftRepository(fileURL: oldDraft).save(RecallDraft(mood: .bright, labels: ["温暖"], kind: "past", timeMark: "昨天", transcript: conversation, aiEnabled: false, inputText: "  未发送👩🏽‍🚀\n  ", diary: words, page: "diary"))
            // A legacy export has a schema-1 envelope with additional export metadata.
            try DiaryExport.json(entries: repository.load(), exportedAt: Date(timeIntervalSince1970: 0)).write(to: root.appendingPathComponent("legacy-export.json"))
        case "read-legacy-write-current":
            let originalJournal = try Data(contentsOf: oldJournal), originalDraft = try Data(contentsOf: oldDraft)
            let entries = try JSONJournalRepository(fileURL: oldJournal).load()
            let exported = try JSONJournalRepository(fileURL: root.appendingPathComponent("legacy-export.json")).load()
            try require(entries == exported && entries.count == 2, "current decoder reads the legacy journal and export consistently")
            try require(entries.first?.diary == words && entries.last?.note == words, "legacy content is unchanged")
            let draft = try JSONDraftRepository(fileURL: oldDraft).load()
            try require(draft?.inputText == "  未发送👩🏽‍🚀\n  " && draft?.diary == words && draft?.mood == .bright, "legacy draft restores all raw expression and mood")
            #if !LEGACY_DECODER
            try require(draft?.previousDiary == nil, "legacy draft without a backup decodes without migration")
            #endif
            try require(try Data(contentsOf: oldJournal) == originalJournal && Data(contentsOf: oldDraft) == originalDraft, "read-only upgrade never rewrites old bytes")
            let repository = JSONJournalRepository(fileURL: root.appendingPathComponent("current-journal.json"))
            for entry in entries { try repository.save(entry) }
            try repository.save(JournalEntry(id: "current-raw", createdAt: 3, mood: .bright, kind: "now", transcript: conversation))
            try repository.save(JournalEntry(id: "current-diary", createdAt: 4, mood: .low, kind: "now", transcript: conversation, diary: words, diaryEnabled: true))
            let current = try repository.load()
            try require(current.count == 4 && current.first?.diary == words, "new modes coexist with all old records")
            #if !LEGACY_DECODER
            try require(current.first?.diaryEnabled == true, "current decoder restores the additive present-diary state")
            #endif
            try DiaryExport.json(entries: current, exportedAt: Date(timeIntervalSince1970: 0)).write(to: root.appendingPathComponent("current-export.json"))
            try JSONDraftRepository(fileURL: root.appendingPathComponent("current-draft.json")).save(RecallDraft(mood: .low, kind: "now", transcript: conversation, aiEnabled: false, inputText: "未发送的此刻文字", diary: words, diaryEnabled: true, page: "diary"))
            #if !LEGACY_DECODER
            let currentDrafts = JSONDraftRepository(fileURL: root.appendingPathComponent("current-draft.json"))
            guard var revisedDraft = try currentDrafts.load() else { throw CompatibilityError.failed("missing current draft") }
            revisedDraft.previousDiary = "上一版的手改补充👩🏽‍🚀\n保留全文。"
            try currentDrafts.save(revisedDraft)
            #endif
        case "read-current":
            for name in ["current-journal.json", "current-export.json"] {
                let url = root.appendingPathComponent(name), before = try Data(contentsOf: url)
                let entries = try JSONJournalRepository(fileURL: url).load()
                try require(entries.count == 4, "new present diaries must not reject the whole mixed file")
                try require(entries.first?.kind == "now" && entries.first?.diary == words && entries.first?.transcript == conversation, "prior decoder retains present kind, diary text and transcript")
                try require(entries.last?.note == words && entries[2].diary == words, "prior records remain readable alongside new modes")
                try require(try Data(contentsOf: url) == before, "decoding compatibility does not rewrite any record")
            }
            let draft = try JSONDraftRepository(fileURL: root.appendingPathComponent("current-draft.json")).load()
            try require(draft?.kind == "now" && draft?.diary == words && draft?.inputText == "未发送的此刻文字", "prior draft decoder can retain new present expression fields")
            #if !LEGACY_DECODER
            try require(draft?.previousDiary == "上一版的手改补充👩🏽‍🚀\n保留全文。", "current decoder retains the additive diary backup")
            #endif
        default: throw CompatibilityError.failed("unsupported mode")
        }
        print("PASS: \(mode); synthetic fixtures only")
    }
}
