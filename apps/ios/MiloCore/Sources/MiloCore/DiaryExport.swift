import Foundation

/// Export accepts only the diary model. Credentials and account preferences
/// cannot enter this API or the resulting document.
public enum DiaryExport {
    public static func json(entries: [JournalEntry], exportedAt: Date = Date()) throws -> Data {
        struct Export: Encodable {
            let schemaVersion = 1
            let app = "MILO"
            let exportedAt: String
            let entries: [JournalEntry]
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Export(exportedAt: formatter.string(from: exportedAt), entries: entries))
    }

    public static func markdown(entries: [JournalEntry], timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        var lines = ["# MILO · 我的情绪日记", "", "共 \(entries.count) 篇", ""]
        for entry in entries {
            let labels = entry.labels.isEmpty ? entry.mood.title : entry.labels.joined(separator: "、")
            lines += ["## \(formatter.string(from: Date(timeIntervalSince1970: entry.createdAt / 1_000)))", "",
                      "情绪：\(labels)（\(entry.mood.valence)）", "时间：\(entry.timeMark ?? "此刻")", "", entry.diary ?? entry.note, ""]
            if !entry.transcript.isEmpty {
                lines += ["### 对话记录", ""]
                for message in entry.transcript { lines += ["\(message.role == .user ? "我" : "MILO")：\(message.text)", ""] }
            }
            lines += ["---", ""]
        }
        return lines.joined(separator: "\n")
    }
}

public struct CardCopy: Equatable, Sendable {
    public let heading: String
    public let labels: String
    public let body: String
    public init(entry: JournalEntry) {
        heading = entry.kind == "past" ? entry.timeMark ?? "过去的某一天" : "此刻"
        labels = entry.labels.joined(separator: " · ")
        let longest = entry.transcript.filter { $0.role == .user }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.reduce("") { $0.count >= $1.count ? $0 : $1 }
        let sources = [entry.diary ?? "", entry.note, longest]
        if let source = sources.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
            let ends: Set<Character> = ["。", "！", "？", "…", "!", "?", "；", ";"]
            let sentence = text.firstIndex(where: { ends.contains($0) }).map { String(text[...$0]) } ?? text
            body = sentence.count > 48 ? String(sentence.prefix(48)) + "…" : sentence
        } else if !entry.labels.isEmpty {
            body = "带着\(entry.labels.prefix(3).joined(separator: "、"))的心情，这一刻被安静地收藏。"
        } else {
            body = "这一刻，被安静地收藏了。"
        }
    }
}

public func memoryTicketID(for entry: JournalEntry, timeZone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyMMdd"
    let stamp = formatter.string(from: Date(timeIntervalSince1970: entry.createdAt / 1_000))
    var hash: UInt32 = 2_166_136_261
    for unit in entry.id.utf16 { hash = (hash ^ UInt32(unit)) &* 16_777_619 }
    let encoded = String(hash, radix: 36).uppercased()
    let suffix = String((String(repeating: "0", count: max(0, 4 - encoded.count)) + encoded).suffix(4))
    return "ML-\(stamp)-\(String(format: "%02d", entry.mood.valence + 3))-\(suffix)"
}
