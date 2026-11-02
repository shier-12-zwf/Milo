import Foundation

public enum JournalError: Error, Equatable, LocalizedError, Sendable {
    case malformedData
    case unsupportedSchema(Int)
    case invalidEntry(String)
    case duplicateIdentifier(String)

    public var errorDescription: String? {
        switch self {
        case .malformedData:
            "暂时无法读取回忆，原有文件已保留。请重试。"
        case .unsupportedSchema:
            "这份回忆使用了暂不支持的数据版本，原有文件已保留。"
        case .invalidEntry, .duplicateIdentifier:
            "回忆数据需要检查，原有文件已保留。"
        }
    }
}

/// One owner at a time. The app holds the repository on its main actor;
/// simultaneous or cross-process writers are outside this milestone.
public protocol JournalRepository {
    func load() throws -> [JournalEntry]
    @discardableResult func save(_ entry: JournalEntry) throws -> [JournalEntry]
    @discardableResult func delete(id: String) throws -> [JournalEntry]
    @discardableResult func deleteAll() throws -> [JournalEntry]
}

public protocol JournalFileIO {
    /// Only an absent file returns nil. Permissions and other read errors throw.
    func read(from url: URL) throws -> Data?
    func writeAtomically(_ data: Data, to url: URL) throws
}

public struct LocalJournalFileIO: JournalFileIO {
    public init() {}

    public func read(from url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }

    public func writeAtomically(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

public final class JSONJournalRepository: JournalRepository {
    public let fileURL: URL
    private let fileIO: any JournalFileIO

    public init(fileURL: URL, fileIO: any JournalFileIO = LocalJournalFileIO()) {
        self.fileURL = fileURL
        self.fileIO = fileIO
    }

    public func load() throws -> [JournalEntry] {
        guard let bytes = try fileIO.read(from: fileURL) else { return [] }
        let envelope: Envelope
        do {
            let header = try JSONDecoder().decode(SchemaHeader.self, from: bytes)
            guard header.schemaVersion == 1 || header.schemaVersion == 2 else {
                throw JournalError.unsupportedSchema(header.schemaVersion)
            }
            envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
        } catch let error as JournalError {
            throw error
        } catch {
            throw JournalError.malformedData
        }
        var identifiers: Set<String> = []
        for entry in envelope.entries {
            try entry.validate()
            guard identifiers.insert(entry.id).inserted else {
                throw JournalError.duplicateIdentifier(entry.id)
            }
        }
        return ordered(envelope.entries)
    }

    @discardableResult public func save(_ entry: JournalEntry) throws -> [JournalEntry] {
        try entry.validate()
        // Never convert an unreadable file into a writable empty journal.
        let existing = try load()
        let entries = ordered(existing.filter { $0.id != entry.id } + [entry])
        try write(entries)
        return entries
    }

    @discardableResult public func delete(id: String) throws -> [JournalEntry] {
        let existing = try load()
        let normalizedID = UUID(uuidString: id)?.uuidString ?? id
        let entries = existing.filter { $0.id != normalizedID }
        if entries.count != existing.count { try write(entries) }
        return entries
    }

    @discardableResult public func deleteAll() throws -> [JournalEntry] {
        // Validate first; a corrupt/future journal cannot be treated as empty.
        let existing = try load()
        if !existing.isEmpty { try write([]) }
        return []
    }

    private func write(_ entries: [JournalEntry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(Envelope(schemaVersion: 2, entries: entries))
        // No cache is mutated before this atomic operation succeeds.
        try fileIO.writeAtomically(bytes, to: fileURL)
    }

    private func ordered(_ entries: [JournalEntry]) -> [JournalEntry] {
        entries.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
        }
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let entries: [JournalEntry]
    }
}

struct SchemaHeader: Decodable { let schemaVersion: Int }
