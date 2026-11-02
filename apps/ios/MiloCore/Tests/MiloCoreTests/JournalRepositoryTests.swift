import Foundation
import Testing
@testable import MiloCore

private let earlierID = "00000000-0000-4000-8000-000000000001"
private let laterID = "00000000-0000-4000-8000-000000000002"

@Test func primaryMoodContractMatchesExistingMilo() {
    #expect(Mood.primaryMoods.map(\.rawValue) == ["joyful", "bright", "okay", "calm", "heavy", "low", "very-low"])
    #expect(Mood.primaryMoods.map(\.valence) == [3, 2, 1, 0, -1, -2, -3])
    #expect(Mood.calm.title == "平静")
    #expect(Mood.bright.title == "明亮")
}

@Test func newInstallationDoesNotCreateADataFileWhenReading() throws {
    let fixture = try DiskFixture()
    let repository = JSONJournalRepository(fileURL: fixture.url)
    #expect(try repository.load().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: fixture.url.path))
}

@Test func writtenNoteSurvivesANewRepositoryInstance() throws {
    let fixture = try DiskFixture()
    let entry = JournalEntry(mood: .bright, note: "  今天散步很开心 \n")
    let first = JSONJournalRepository(fileURL: fixture.url)
    #expect(try first.save(entry) == [entry])
    let reopened = JSONJournalRepository(fileURL: fixture.url)
    let loaded = try #require(reopened.load().first)
    #expect(loaded.note == "今天散步很开心")
    #expect(loaded.mood == .bright)
    #expect(loaded.id == entry.id)
    #expect(loaded.createdAt == entry.createdAt)
    #expect(loaded.kind == "now")
    #expect(!loaded.diaryEnabled)

    let payload = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.url)) as? [String: Any])
    #expect(payload["schemaVersion"] as? Int == 2)
    let records = try #require(payload["entries"] as? [[String: Any]])
    let mood = try #require(records[0]["mood"] as? [String: Any])
    #expect(mood["emotionId"] as? String == "bright")
    #expect(mood["valence"] as? Int == 2)
    #expect(records[0]["createdAt"] as? Double == entry.createdAt)
}

@Test(arguments: ["", " \t\n ", "　\n"])
func blankNotesPreserveMoodAndUseQuietPreview(input: String) throws {
    let fixture = try DiskFixture()
    let entry = JournalEntry(mood: .heavy, note: input)
    try JSONJournalRepository(fileURL: fixture.url).save(entry)
    let loaded = try #require(JSONJournalRepository(fileURL: fixture.url).load().first)
    #expect(loaded.note.isEmpty)
    #expect(loaded.mood == .heavy)
    #expect(loaded.preview == "（一次安静的记录）")
}

@Test func longUnicodeNoteKeepsEveryInteriorCharacter() throws {
    let fixture = try DiskFixture()
    let text = String(repeating: "今天散步。👩🏽‍🚀 记得风的声音。\n\n", count: 600) + "最后一句。"
    let entry = JournalEntry(mood: .okay, note: "\n " + text + "\n")
    try JSONJournalRepository(fileURL: fixture.url).save(entry)
    #expect(try JSONJournalRepository(fileURL: fixture.url).load().first?.note == text)
}

@Test func historyIsNewestFirstWithAscendingIDForEqualTimes() throws {
    let io = MemoryFileIO()
    let repository = JSONJournalRepository(fileURL: testURL, fileIO: io)
    let old = JournalEntry(createdAt: 1_000, mood: .calm, note: "old")
    let second = JournalEntry(id: laterID, createdAt: 2_000, mood: .bright, note: "second")
    let first = JournalEntry(id: earlierID, createdAt: 2_000, mood: .low, note: "first")
    try repository.save(second)
    try repository.save(old)
    try repository.save(first)
    #expect(try repository.load().map(\.id) == [earlierID, laterID, old.id])
}

@Test func savingSameIDReplacesRatherThanDuplicates() throws {
    let fixture = try DiskFixture()
    let repository = JSONJournalRepository(fileURL: fixture.url)
    try repository.save(JournalEntry(id: earlierID, createdAt: 1_000, mood: .calm, note: "原文"))
    let updated = JournalEntry(id: earlierID, createdAt: 1_000, mood: .bright, note: "修改后")
    #expect(try repository.save(updated) == [updated])
    #expect(try JSONJournalRepository(fileURL: fixture.url).load() == [updated])
}

@Test func eachSaveReadsTheCurrentFileInsteadOfAStaleCache() throws {
    let fixture = try DiskFixture()
    let first = JSONJournalRepository(fileURL: fixture.url)
    let second = JSONJournalRepository(fileURL: fixture.url)
    #expect(try first.load().isEmpty)
    let a = JournalEntry(createdAt: 1_000, mood: .calm, note: "a")
    let b = JournalEntry(createdAt: 2_000, mood: .bright, note: "b")
    try second.save(a)
    #expect(try first.save(b) == [b, a])
}

@Test func failedWriteKeepsOriginalBytesAndRecordsThenCanBeRetried() throws {
    let fixture = try DiskFixture()
    let io = FailingDiskIO()
    let repository = JSONJournalRepository(fileURL: fixture.url, fileIO: io)
    let original = JournalEntry(mood: .calm, note: "已保存")
    try repository.save(original)
    let bytes = try Data(contentsOf: fixture.url)
    let draft = JournalEntry(mood: .bright, note: "不能丢掉我的输入")
    io.failWrite = true
    #expect(throws: TestFailure.write) { try repository.save(draft) }
    #expect(try Data(contentsOf: fixture.url) == bytes)
    #expect(try repository.load() == [original])
    #expect(draft.note == "不能丢掉我的输入")
    io.failWrite = false
    #expect(try repository.save(draft).count == 2)
}

@Test func failedReadNeverOverwritesExistingDataAndRetryRecovers() throws {
    let fixture = try DiskFixture()
    let io = FailingDiskIO()
    let repository = JSONJournalRepository(fileURL: fixture.url, fileIO: io)
    let original = JournalEntry(mood: .calm, note: "已保存")
    try repository.save(original)
    let bytes = try Data(contentsOf: fixture.url)
    let writes = io.writeCount
    io.failRead = true
    #expect(throws: TestFailure.read) { try repository.load() }
    #expect(throws: TestFailure.read) { try repository.save(JournalEntry(mood: .low, note: "未保存")) }
    #expect(io.writeCount == writes)
    #expect(try Data(contentsOf: fixture.url) == bytes)
    io.failRead = false
    #expect(try repository.load() == [original])
}

@Test(arguments: ["", "not JSON", "[]", "null", "{}", "{\"schemaVersion\":1,\"entries\":null}"])
func malformedDataIsReportedAndNeverOverwritten(json: String) throws {
    let fixture = try DiskFixture()
    let bytes = Data(json.utf8)
    try bytes.write(to: fixture.url)
    let repository = JSONJournalRepository(fileURL: fixture.url)
    #expect(throws: JournalError.self) { try repository.load() }
    #expect(throws: JournalError.self) { try repository.save(JournalEntry(mood: .calm, note: "new")) }
    #expect(try Data(contentsOf: fixture.url) == bytes)
}

@Test func unsupportedSchemaIsReportedAndNeverOverwritten() throws {
    let fixture = try DiskFixture()
    let bytes = Data("{\"schemaVersion\":3,\"entries\":[]}".utf8)
    try bytes.write(to: fixture.url)
    let repository = JSONJournalRepository(fileURL: fixture.url)
    #expect(throws: JournalError.unsupportedSchema(3)) { try repository.load() }
    #expect(throws: JournalError.unsupportedSchema(3)) { try repository.save(JournalEntry(mood: .calm, note: "new")) }
    #expect(try Data(contentsOf: fixture.url) == bytes)
}

@Test func invalidRecordFieldsAreRejectedWithoutDataLoss() throws {
    let original = JournalEntry(id: earlierID, createdAt: 1_000, mood: .bright, note: "safe")
    let dictionary = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    let mutations: [(String, Any)] = [
        ("id", ""), ("id", "../invalid"), ("createdAt", -1),
        ("createdAt", 253_402_300_800_000), ("createdAt", "yesterday"),
        ("kind", "past"), ("diaryEnabled", true), ("note", NSNull()),
        ("mood", ["valence": 2, "labels": [], "emotionId": "mystery"]),
        ("mood", ["valence": 1, "labels": [], "emotionId": "bright"]),
        ("mood", ["valence": 2, "labels": ["a", "b", "c", "d"], "emotionId": "bright"]),
    ]
    for (field, invalidValue) in mutations {
        var entry = dictionary
        entry[field] = invalidValue
        let bytes = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "entries": [entry]])
        let io = MemoryFileIO(bytes: bytes)
        let repository = JSONJournalRepository(fileURL: testURL, fileIO: io)
        #expect(throws: JournalError.self) { try repository.load() }
        #expect(throws: JournalError.self) { try repository.save(original) }
        #expect(io.bytes == bytes)
        #expect(io.writeCount == 0)
    }
}

@Test func duplicateIDsAreRejectedIncludingUUIDCaseVariants() throws {
    let entry = JournalEntry(id: "ABCDEF00-0000-4000-8000-000000000001", mood: .calm, note: "one")
    var record = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
    let first = record
    record["id"] = entry.id.lowercased()
    let bytes = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "entries": [first, record]])
    let io = MemoryFileIO(bytes: bytes)
    let repository = JSONJournalRepository(fileURL: testURL, fileIO: io)
    #expect(throws: JournalError.duplicateIdentifier(entry.id)) { try repository.load() }
    #expect(throws: JournalError.duplicateIdentifier(entry.id)) { try repository.save(entry) }
    #expect(io.bytes == bytes)
    #expect(io.writeCount == 0)
}

@Test func invalidNewEntriesCannotTouchStorage() throws {
    let io = MemoryFileIO()
    let repository = JSONJournalRepository(fileURL: testURL, fileIO: io)
    let entries = [
        JournalEntry(id: "bad/id", mood: .calm, note: "invalid id"),
        JournalEntry(createdAt: -.infinity, mood: .calm, note: "invalid date"),
        JournalEntry(createdAt: .infinity, mood: .calm, note: "invalid date"),
        JournalEntry(createdAt: .nan, mood: .calm, note: "invalid date"),
        JournalEntry(createdAt: -1, mood: .calm, note: "invalid date"),
        JournalEntry(createdAt: 253_402_300_800_000, mood: .calm, note: "invalid date"),
    ]
    for entry in entries {
        #expect(throws: JournalError.self) { try repository.save(entry) }
    }
    #expect(io.readCount == 0)
    #expect(io.writeCount == 0)
    #expect(io.bytes == nil)
}

@Test func acceptedTimestampBoundsRoundTrip() throws {
    let io = MemoryFileIO()
    let repository = JSONJournalRepository(fileURL: testURL, fileIO: io)
    let earliest = JournalEntry(createdAt: 0, mood: .calm, note: "epoch")
    let latest = JournalEntry(createdAt: 253_402_300_799_999, mood: .calm, note: "upper bound")
    try repository.save(earliest)
    #expect(try repository.save(latest) == [latest, earliest])
}

@Test func realReadErrorIsNotTreatedAsAnAbsentFile() throws {
    let fixture = try DiskFixture()
    try FileManager.default.createDirectory(at: fixture.url, withIntermediateDirectories: false)
    let repository = JSONJournalRepository(fileURL: fixture.url)
    #expect(throws: (any Error).self) { try repository.load() }
    #expect(throws: (any Error).self) { try repository.save(JournalEntry(mood: .calm, note: "new")) }
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: fixture.url.path, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
}

private let testURL = URL(fileURLWithPath: "/unused-by-memory-fixture/journal.json")

private enum TestFailure: Error, Equatable {
    case read, write
}

private final class DiskFixture {
    let directory: URL
    var url: URL { directory.appendingPathComponent("journal.json") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MiloCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

private final class MemoryFileIO: JournalFileIO {
    var bytes: Data?
    var readCount = 0
    var writeCount = 0
    init(bytes: Data? = nil) { self.bytes = bytes }
    func read(from url: URL) throws -> Data? {
        readCount += 1
        return bytes
    }
    func writeAtomically(_ data: Data, to url: URL) throws {
        writeCount += 1
        bytes = data
    }
}

private final class FailingDiskIO: JournalFileIO {
    var failRead = false
    var failWrite = false
    var writeCount = 0
    private let disk = LocalJournalFileIO()
    func read(from url: URL) throws -> Data? {
        if failRead { throw TestFailure.read }
        return try disk.read(from: url)
    }
    func writeAtomically(_ data: Data, to url: URL) throws {
        if failWrite { throw TestFailure.write }
        try disk.writeAtomically(data, to: url)
        writeCount += 1
    }
}
