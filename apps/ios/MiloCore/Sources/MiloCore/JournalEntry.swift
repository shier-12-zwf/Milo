import Foundation

public enum ChatRole: String, Codable, Sendable { case user, ai }

public struct TranscriptMessage: Codable, Equatable, Sendable {
    public var role: ChatRole
    public var text: String
    /// Milliseconds since the Unix epoch.
    public var ts: Double
    public init(role: ChatRole, text: String, ts: Double = Date().timeIntervalSince1970 * 1_000) {
        self.role = role
        self.text = text
        self.ts = ts
    }
}

public enum CardTemplate: String, Codable, CaseIterable, Identifiable, Sendable {
    case planetLetter = "planet-letter"
    case orbitTheatre = "orbit-theatre"
    public var id: String { rawValue }
    public var title: String { self == .planetLetter ? "星球卡片" : "轨道剧场" }
    public var subtitle: String { self == .planetLetter ? "雾紫卡纸" : "社交海报" }
}

public struct JournalEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let createdAt: Double
    public var mood: Mood
    public var note: String
    public var labels: [String]
    public var kind: String
    public var timeMark: String?
    public var transcript: [TranscriptMessage]
    public var diary: String?
    public var diaryEnabled: Bool
    public var stickerTemplate: CardTemplate

    public init(
        id: String = UUID().uuidString,
        createdAt: Double = Date().timeIntervalSince1970 * 1_000,
        mood: Mood,
        note: String = "",
        labels: [String] = [],
        kind: String = "now",
        timeMark: String? = nil,
        transcript: [TranscriptMessage] = [],
        diary: String? = nil,
        diaryEnabled: Bool = false,
        stickerTemplate: CardTemplate = .planetLetter
    ) {
        self.id = UUID(uuidString: id)?.uuidString ?? id
        self.createdAt = createdAt
        self.mood = mood
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.labels = labels
        self.kind = kind
        self.timeMark = timeMark
        self.transcript = transcript
        self.diary = diary
        self.diaryEnabled = diaryEnabled
        self.stickerTemplate = stickerTemplate
    }

    public var preview: String {
        if let diary, !diary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return diary }
        if !note.isEmpty { return note }
        let text = transcript.filter { $0.role == .user }.map(\.text).joined(separator: " ")
        return text.isEmpty ? "（一次安静的记录）" : text
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, kind, mood, note, timeMark, transcript, diary, diaryEnabled, stickerTemplate, presentDiaryEnabled
    }
    private struct StoredMood: Codable {
        let valence: Int
        let labels: [String]
        let emotionId: Mood
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let storedMood = try values.decode(StoredMood.self, forKey: .mood)
        guard storedMood.valence == storedMood.emotionId.valence else {
            throw JournalError.invalidEntry("inconsistent mood")
        }
        let kind = try values.decode(String.self, forKey: .kind)
        let legacyDiaryEnabled = try values.decode(Bool.self, forKey: .diaryEnabled)
        let presentDiaryEnabled = try values.decodeIfPresent(Bool.self, forKey: .presentDiaryEnabled) ?? false
        guard !presentDiaryEnabled || kind == "now" else { throw JournalError.invalidEntry("invalid present diary flag") }
        self.init(
            id: try values.decode(String.self, forKey: .id),
            createdAt: try values.decode(Double.self, forKey: .createdAt),
            mood: storedMood.emotionId,
            note: values.contains(.note) ? try values.decode(String.self, forKey: .note) : "",
            labels: storedMood.labels,
            kind: kind,
            timeMark: try values.decodeIfPresent(String.self, forKey: .timeMark),
            transcript: try values.decodeIfPresent([TranscriptMessage].self, forKey: .transcript) ?? [],
            diary: try values.decodeIfPresent(String.self, forKey: .diary),
            diaryEnabled: legacyDiaryEnabled || presentDiaryEnabled,
            stickerTemplate: try values.decodeIfPresent(CardTemplate.self, forKey: .stickerTemplate) ?? .planetLetter
        )
        try validate()
    }

    public func encode(to encoder: any Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(kind, forKey: .kind)
        try values.encode(StoredMood(valence: mood.valence, labels: labels, emotionId: mood), forKey: .mood)
        try values.encode(note, forKey: .note)
        try values.encodeIfPresent(timeMark, forKey: .timeMark)
        try values.encode(transcript, forKey: .transcript)
        try values.encodeIfPresent(diary, forKey: .diary)
        // Older iOS rejects kind=now with diaryEnabled=true. Preserve the familiar
        // kind and all content, and use an additive optional flag that it ignores.
        try values.encode(kind == "past" && diaryEnabled, forKey: .diaryEnabled)
        if kind == "now", diaryEnabled { try values.encode(true, forKey: .presentDiaryEnabled) }
        try values.encode(stickerTemplate, forKey: .stickerTemplate)
    }

    func validate() throws {
        try validateIdentifier(id)
        try validateTimestamp(createdAt)
        try validateLabels(labels)
        guard kind == "now" || kind == "past" else { throw JournalError.invalidEntry("unknown kind") }
        if kind == "now" && diaryEnabled && !transcript.contains(where: { $0.role == .user }) {
            throw JournalError.invalidEntry("present diary requires user expression")
        }
        if kind == "past", timeMark?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw JournalError.invalidEntry("missing past time")
        }
        for message in transcript { try validateTimestamp(message.ts) }
    }
}

func validateIdentifier(_ value: String) throws {
    // HarmonyOS creates non-UUID identifiers. Keep IDs opaque while excluding
    // whitespace, path separators and unbounded values from persisted keys.
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
    guard !value.isEmpty, value.utf8.count <= 128,
          value != ".", value != "..", value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
        throw JournalError.invalidEntry("invalid identifier")
    }
}

func validateTimestamp(_ value: Double) throws {
    guard value.isFinite, (0...253_402_300_799_999).contains(value) else {
        throw JournalError.invalidEntry("invalid timestamp")
    }
}

func validateLabels(_ labels: [String]) throws {
    guard labels.count <= 3, Set(labels).count == labels.count,
          labels.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 64 }) else {
        throw JournalError.invalidEntry("invalid labels")
    }
}
