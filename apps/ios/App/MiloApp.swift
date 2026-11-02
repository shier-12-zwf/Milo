import SwiftUI
import MiloCore

@main
struct MiloApp: App {
    @State private var model = AppStorage.makeModel()
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ParityFixture.caseID != nil {
                ParityRootView(model: model)
                    .environment(\.dynamicTypeSize, ParityFixture.isLargeText ? .accessibility5 : .large)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                    .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
            } else { JournalView(model: model) }
            #else
            JournalView(model: model)
            #endif
        }
    }
}

enum AppStorage {
    #if DEBUG
    // Native unit-test hosts otherwise launch the app without --uitest-id.
    // Keep their coordinator away from the user's Application Support/MILO store too.
    private static let unitTestStoreID: UUID? = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil ? UUID() : nil
    #endif
    static var directory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if DEBUG
        if let id = ParityFixture.id ?? unitTestStoreID {
            return support.appendingPathComponent("MILO-UITests", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
        }
        #endif
        return support.appendingPathComponent("MILO", isDirectory: true)
    }
    @MainActor static func makeModel() -> JournalModel {
        let location = directory
        let url = location.appendingPathComponent("journal.json")
        var repository: any JournalRepository = JSONJournalRepository(fileURL: url)
        #if DEBUG
        if ParityFixture.id != nil {
            if ProcessInfo.processInfo.arguments.contains("--uitest-corrupt") {
                try? FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
                try? Data("broken journal fixture".utf8).write(to: url)
            }
            if ProcessInfo.processInfo.arguments.contains("--uitest-write-failure") {
                repository = WriteFailingRepository(base: repository)
            }
        }
        #endif
        let model = JournalModel(repository: repository, directory: location)
        #if DEBUG
        if ParityFixture.caseID != nil { ParityFixture.configure(model: model, repository: repository) }
        #endif
        return model
    }
}

#if DEBUG
private struct ParityRootView: View {
    let model: JournalModel
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        JournalView(model: model).accessibilityElement(children: .contain)
            .accessibilityIdentifier("parity-root")
            .accessibilityValue(textSize == .accessibility5 ? "accessibility5" : textSize == .large ? "large" : "unexpected")
    }
}
// Every launch override is gated on a UUID-specific fixture directory. It cannot select or reset production storage.
enum ParityFixture {
    static var id: UUID? { argument("--uitest-id").flatMap(UUID.init(uuidString:)) }
    static var caseID: String? { id == nil ? nil : argument("--parity-case") }
    static var route: String? { caseID?.components(separatedBy: "--").first }
    static var state: String? { caseID?.components(separatedBy: "--").dropFirst().first }
    static var isLargeText: Bool { caseID?.hasSuffix("--large-text") == true }
    static func argument(_ key: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
    @MainActor static func configure(model: JournalModel, repository: any JournalRepository) {
        guard let route, let state, id != nil else { return }
        let now = 1_790_386_860_000.0
        let note = "今天慢慢走了一段路，风很温柔。"
        let long = Array(repeating: note + "路边的树叶轻轻摇晃，我停下来，记住了这段安静的时间。", count: 14).joined(separator: "\n\n")
        let transcript = [TranscriptMessage(role: .ai, text: "那段时光里，你最先想起的是什么？", ts: now - 120_000), TranscriptMessage(role: .user, text: note, ts: now - 60_000), TranscriptMessage(role: .ai, text: "那一刻，是什么让你记住了它？", ts: now - 30_000)]
        model.account.configureFixture(remote: route == "account" && ["remote", "password-form"].contains(state), state: state)
        var draft = RecallDraft()
        draft.page = route
        draft.mood = state == "mood-joyful" ? .joyful : state == "mood-low" ? .low : .calm
        if route == "home" && state.hasPrefix("words-") { draft.page = "home-words" }
        if state == "words-three" { draft.labels = ["平静", "安稳", "松弛"] }
        if route == "now-note" { draft.kind = "now"; draft.note = state == "empty" ? "" : state == "keyboard-long" ? long : note }
        if route == "past-time" { draft.kind = "past"; if state != "empty" { draft.timeMark = state == "preset" ? "昨天" : "高三的雨季" } }
        if ["chat", "diary"].contains(route) {
            draft.kind = "past"; draft.timeMark = "去年夏天"
            draft.transcript = state == "opening" ? [transcript[0]] : transcript
            if state == "long-reply" {
                draft.kind = "now"; draft.timeMark = nil
                draft.transcript[2].text = "开了一天会之后还被加活，连着几天都是这样，确实没有多少喘口气的时间。\n先把你想说的话说完，不急着给建议。👩🏽‍🚀\n这是完整保留的最后一句。"
            }
            draft.aiEnabled = state != "offline"
            draft.diary = state == "long" ? long : note
            draft.diaryEnabled = state != "disabled"
            if state == "keyboard" { draft.inputText = note }
            model.guidanceNotice = "AI 暂时不可用，已切换本地引导"
            model.isThinking = state == "busy"
        }
        if ["timeline", "detail", "card"].contains(route), state != "empty" && state != "missing" {
            let past = route == "detail" && ["past", "transcript-expanded"].contains(state)
            let entry = JournalEntry(id: "B8867CF1-3C35-489D-B128-9788DDCDDB63", createdAt: now, mood: .calm, note: past ? "" : note, labels: ["平静", "松弛"], kind: past ? "past" : "now", timeMark: past ? "去年夏天" : nil, transcript: past ? transcript : [], diary: past ? long : nil, diaryEnabled: past, stickerTemplate: state == "orbit-theatre" ? .orbitTheatre : .planetLetter)
            do { _ = try repository.save(entry); model.reload(); draft.entryID = entry.id }
            catch { model.errorMessage = "截图夹具写入失败" }
        }
        model.draft = draft
        if route == "login" { model.account.clearFixtureIdentity() }
    }
}

private struct WriteFailingRepository: JournalRepository {
    let base: any JournalRepository
    func load() throws -> [JournalEntry] { try base.load() }
    func save(_ entry: JournalEntry) throws -> [JournalEntry] { throw CocoaError(.fileWriteNoPermission) }
    func delete(id: String) throws -> [JournalEntry] { throw CocoaError(.fileWriteNoPermission) }
    func deleteAll() throws -> [JournalEntry] { throw CocoaError(.fileWriteNoPermission) }
}
#endif
