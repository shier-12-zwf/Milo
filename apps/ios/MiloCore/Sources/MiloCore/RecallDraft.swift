import Foundation

/// A complete, credential-free in-progress journey. Raw user input is not
/// trimmed until a saved entry is made, so interruption never loses typing.
public struct RecallDraft: Codable, Equatable, Sendable {
    public var mood: Mood
    public var labels: [String]
    public var kind: String?
    public var timeMark: String?
    public var note: String
    public var transcript: [TranscriptMessage]
    public var aiEnabled: Bool
    public var inputText: String
    public var diary: String?
    /// Previous body retained when more conversation invalidates the current
    /// diary. Optional so drafts from before revision backup remain readable.
    public var previousDiary: String?
    public var diaryEnabled: Bool
    public var stickerTemplate: CardTemplate
    public var page: String
    public var entryID: String?
    /// Stable identity for an in-flight save. Browsing another entry must not
    /// change it; retries may upsert this ID after a draft-clear failure.
    public var pendingEntryID: String?

    public init(mood: Mood = .calm, labels: [String] = [], kind: String? = nil,
                timeMark: String? = nil, note: String = "", transcript: [TranscriptMessage] = [],
                aiEnabled: Bool = true, inputText: String = "", diary: String? = nil,
                previousDiary: String? = nil,
                diaryEnabled: Bool = true, stickerTemplate: CardTemplate = .planetLetter,
                page: String = "home", entryID: String? = nil, pendingEntryID: String? = nil) {
        self.mood = mood
        self.labels = labels
        self.kind = kind
        self.timeMark = timeMark
        self.note = note
        self.transcript = transcript
        self.aiEnabled = aiEnabled
        self.inputText = inputText
        self.diary = diary
        self.previousDiary = previousDiary
        self.diaryEnabled = diaryEnabled
        self.stickerTemplate = stickerTemplate
        self.page = page
        self.entryID = entryID
        self.pendingEntryID = pendingEntryID
    }

    public mutating func selectMood(_ value: Mood) {
        self = RecallDraft(mood: value, page: "classify")
    }

    /// Selecting a fourth word is a no-op; tapping a selected word removes it.
    public mutating func toggleLabel(_ value: String) {
        guard mood.descriptorWords.contains(value) else { return }
        if let index = labels.firstIndex(of: value) { labels.remove(at: index) }
        else if labels.count < 3 { labels.append(value) }
    }

    public mutating func chooseKind(_ value: String) {
        guard value == "now" || value == "past" else { return }
        if kind != nil && kind != value {
            note = ""
            timeMark = nil
            transcript = []
            inputText = ""
            diary = nil
            previousDiary = nil
            pendingEntryID = nil
        }
        kind = value
        page = value == "now" ? "now-note" : "past-time"
    }

    @discardableResult public mutating func selectTimeMark(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind == "past", !value.isEmpty else { return false }
        if timeMark != nil && timeMark != value {
            transcript = []
            diary = nil
            previousDiary = nil
            inputText = ""
            pendingEntryID = nil
        }
        timeMark = value
        page = "chat"
        return true
    }

    public mutating func goBack() {
        switch page {
        case "classify", "timeline": page = "home"
        case "home-words", "words": page = "home"; labels = []
        case "now-note", "past-time": page = "classify"
        case "chat": page = kind == "now" ? "classify" : "past-time"
        case "diary": page = "chat"
        case "card", "detail": page = "timeline"; entryID = nil
        default: break
        }
    }

    public func makeEntry(id: String = UUID().uuidString,
                          createdAt: Double = Date().timeIntervalSince1970 * 1_000) throws -> JournalEntry {
        guard let kind, kind == "now" || kind == "past" else {
            throw JournalError.invalidEntry("missing entry kind")
        }
        if kind == "past" && !transcript.contains(where: { $0.role == .user && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw JournalError.invalidEntry("missing user expression")
        }
        let hasConversation = !transcript.isEmpty
        let entry = JournalEntry(id: id, createdAt: createdAt, mood: mood, note: kind == "now" ? note : "",
                                 labels: labels, kind: kind, timeMark: kind == "past" ? timeMark : nil,
                                 transcript: transcript,
                                 diary: hasConversation && diaryEnabled ? diary : nil,
                                 diaryEnabled: hasConversation && diaryEnabled,
                                 stickerTemplate: stickerTemplate)
        try entry.validate()
        return entry
    }

    func validate() throws {
        try validateLabels(labels)
        guard kind == nil || kind == "now" || kind == "past" else { throw JournalError.invalidEntry("invalid draft kind") }
        let pages: Set<String> = ["home", "home-words", "words", "classify", "now-note", "past-time", "chat", "diary", "card", "timeline", "detail", "login", "account", "ai-settings"]
        guard pages.contains(page) else { throw JournalError.invalidEntry("unknown draft page") }
        if let entryID { try validateIdentifier(entryID) }
        if let pendingEntryID { try validateIdentifier(pendingEntryID) }
        for message in transcript { try validateTimestamp(message.ts) }
    }
}

public protocol DraftRepository {
    func load() throws -> RecallDraft?
    func save(_ draft: RecallDraft) throws
    func clear() throws
}

public final class JSONDraftRepository: DraftRepository {
    public let fileURL: URL
    private let fileIO: any JournalFileIO
    public init(fileURL: URL, fileIO: any JournalFileIO = LocalJournalFileIO()) {
        self.fileURL = fileURL
        self.fileIO = fileIO
    }
    public func load() throws -> RecallDraft? {
        guard let bytes = try fileIO.read(from: fileURL) else { return nil }
        do {
            let header = try JSONDecoder().decode(SchemaHeader.self, from: bytes)
            guard header.schemaVersion == 1 else { throw JournalError.unsupportedSchema(header.schemaVersion) }
            let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
            try envelope.draft?.validate()
            return envelope.draft
        } catch let error as JournalError { throw error }
        catch { throw JournalError.malformedData }
    }
    public func save(_ draft: RecallDraft) throws {
        try draft.validate()
        _ = try load()
        try write(draft)
    }
    public func clear() throws {
        _ = try load()
        // An atomic tombstone uses the same preservation guarantees as a save.
        try write(nil)
    }
    private func write(_ draft: RecallDraft?) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try fileIO.writeAtomically(encoder.encode(Envelope(schemaVersion: 1, draft: draft)), to: fileURL)
    }
    private struct Envelope: Codable {
        let schemaVersion: Int
        let draft: RecallDraft?
        enum CodingKeys: String, CodingKey { case schemaVersion, draft }
        init(schemaVersion: Int, draft: RecallDraft?) { self.schemaVersion = schemaVersion; self.draft = draft }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
            guard values.contains(.draft) else { throw JournalError.malformedData }
            draft = try values.decodeIfPresent(RecallDraft.self, forKey: .draft)
        }
        func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(schemaVersion, forKey: .schemaVersion)
            try values.encode(draft, forKey: .draft)
        }
    }
}
