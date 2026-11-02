import Foundation

public enum OfflineGuide {
    public static let timePresets = ["昨天", "上个星期", "几个月前", "去年这个时候", "去年夏天", "几年前", "大学时光", "刚工作那会儿", "少年时代", "小时候"]
    public static let recordingNotice = "当前仅本地记录，不会理解或回复内容。你可以继续写、收藏原话，或在 AI 设置中连接自己的模型。"

    public static func opening(mood: Mood = .calm, timeMark: String) -> String {
        timeMark.count > 18 ? "那段时光里，你最先想起什么？" : "「\(timeMark)」，你最先想起什么？"
    }

    // Never impersonate semantic understanding with a response selected by turn count.
    public static func respond(transcript: [TranscriptMessage]) -> String {
        if let last = transcript.last, last.role == .user, wantsToPause(last.text) { return "好，先停在这里。" }
        return recordingNotice
    }

    public static func wantsToPause(_ text: String) -> Bool {
        matches(text, pattern: "^(我)?(现在|今天|暂时|真的)?(不想说|不想聊|不说了|不聊了|先不说|先不聊|说不下去|聊不下去|先这样|先到这里|就这样|暂停|先停一下|到这里|算了|没了|没有了)(了|吧)?(也?(不用|不要|不需要)(生成|整理)?日记)?$")
    }

    public static func diary(transcript: [TranscriptMessage]) -> String {
        let lines = transcript.filter { $0.role == .user }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return lines.isEmpty ? "今天的心情，先记在这里。" : lines.joined(separator: "\n\n")
    }

    public static func transcriptText(_ transcript: [TranscriptMessage]) -> String {
        transcript.map { "\($0.role == .user ? "我" : "回响")：\($0.text)" }.joined(separator: "\n")
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        let ignored = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,。.!！?？"))
        let compact = String(String.UnicodeScalarView(text.unicodeScalars.filter { !ignored.contains($0) }))
        return compact.range(of: pattern, options: .regularExpression) != nil
    }
}
