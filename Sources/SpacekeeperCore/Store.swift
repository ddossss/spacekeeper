import Foundation
import Darwin

public struct Settings: Codable, Sendable {
    public var scheduleEnabled = false
    public var daily = false
    public var weekday = 1 // Monday (launchd: Sunday = 0)
    public var hour = 10
    public var minute = 0
    public var minimumDays = 14
    public var cacheIDs = Set(CacheRule.supported.map(\.id))
    public var maxScheduledBytes: Int64 = 2 * 1024 * 1024 * 1024
    public var excludedPaths: [String] = []
    public init() {}
    public func validate() throws {
        guard (0...6).contains(weekday), (0...23).contains(hour), (0...59).contains(minute),
              (7...365).contains(minimumDays), maxScheduledBytes > 0,
              maxScheduledBytes <= 20 * 1024 * 1024 * 1024,
              cacheIDs.isSubset(of: Set(CacheRule.supported.map(\.id))) else {
            throw KeeperError.unsafe("정기 청소 설정 범위를 확인해 주세요.")
        }
    }
}

public struct HistoryItem: Identifiable, Codable, Sendable {
    public var id = UUID()
    public let source: URL
    public let bytes: Int64
    public var trashURL: URL?
    public var trashStamp: FileStamp?
    public var restored = false
    public var error: String?
    public var localizedError: LocalizedMessage?
    public var displayError: String? { localizedError?.rendered ?? error.map { L10n.text($0) } }
    public var pending: Bool?
}

public struct HistoryRecord: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var date = Date()
    public let kind: String
    public var items: [HistoryItem] = []
    public var note: String = ""
    public var localizedNote: LocalizedMessage?
    public var displayNote: String { localizedNote?.rendered ?? L10n.text(note) }
    public mutating func setNote(_ message: LocalizedMessage) { note = message.rendered; localizedNote = message }
    public var movedBytes: Int64 { items.filter { $0.trashURL != nil && !$0.restored }.reduce(0) { $0 + $1.bytes } }
    public var movedCount: Int { items.filter { $0.trashURL != nil && !$0.restored }.count }
    public init(kind: String) { self.kind = kind }
}

public final class Store: @unchecked Sendable {
    public let root: URL
    private let fm = FileManager.default
    public init(root: URL) { self.root = root }
    public static var defaultRoot: URL {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "SpacekeeperStatePath") as? String {
            return URL(fileURLWithPath: configured)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Spacekeeper")
    }
    public func prepare() throws {
        try fm.createDirectory(at: root.appendingPathComponent("history"), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try FileSafety.noSymlinks(root)
    }
    public func settings() throws -> Settings {
        let url = root.appendingPathComponent("settings.json")
        if !fm.fileExists(atPath: url.path) { return Settings() }
        let result = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: url))
        try result.validate(); return result
    }
    public func save(settings: Settings) throws {
        try settings.validate(); try prepare()
        try JSONEncoder().encode(settings).write(to: root.appendingPathComponent("settings.json"), options: .atomic)
    }
    public func save(record: HistoryRecord) throws {
        try prepare()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: root.appendingPathComponent("history/\(record.id.uuidString).json"), options: .atomic)
    }
    public func history() throws -> [HistoryRecord] {
        let directory = root.appendingPathComponent("history")
        guard fm.fileExists(atPath: directory.path) else { return [] }
        return try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { url in
                var record = try JSONDecoder().decode(HistoryRecord.self, from: Data(contentsOf: url))
                let journal = directory.appendingPathComponent(record.id.uuidString + ".jsonl")
                if fm.fileExists(atPath: journal.path) {
                    let data = try Data(contentsOf: journal)
                    var byID = Dictionary(uniqueKeysWithValues: record.items.enumerated().map { ($0.element.id, $0.offset) })
                    let lines = data.split(separator: 10, omittingEmptySubsequences: true)
                    for (index, line) in lines.enumerated() {
                        // A process interrupted mid-write may leave only the last event incomplete.
                        guard let item = try? JSONDecoder().decode(HistoryItem.self, from: Data(line)) else {
                            if index == lines.count - 1 && data.last != 10 { continue }
                            throw KeeperError.unsafe("정리 기록이 손상되었습니다: \(journal.path)")
                        }
                        if let index = byID[item.id] { record.items[index] = item }
                        else { byID[item.id] = record.items.count; record.items.append(item) }
                    }
                }
                return record
            }
            .sorted { $0.date > $1.date }
    }
    /// Append a durable event instead of rewriting an ever-growing record for every cache file.
    public func append(item: HistoryItem, recordID: UUID) throws {
        let path = root.appendingPathComponent("history/\(recordID.uuidString).jsonl").path
        let fd = open(path, O_CREAT | O_APPEND | O_WRONLY | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw KeeperError.unsafe("정리 기록을 저장할 수 없습니다.") }
        defer { close(fd) }
        var data = try JSONEncoder().encode(item); data.append(10)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard count > 0 else { throw KeeperError.unsafe("정리 기록을 저장할 수 없습니다.") }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw KeeperError.unsafe("정리 기록을 디스크에 저장할 수 없습니다.") }
    }
    public func finish(record: HistoryRecord) throws {
        try save(record: record)
        let journal = root.appendingPathComponent("history/\(record.id.uuidString).jsonl")
        if fm.fileExists(atPath: journal.path) { try fm.removeItem(at: journal) }
    }
    public func withLock<T>(_ action: () throws -> T) throws -> T {
        try prepare()
        let fd = open(root.appendingPathComponent("operation.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw KeeperError.unsafe("정리 잠금 파일을 열 수 없습니다.") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw KeeperError.busy }
        defer { flock(fd, LOCK_UN) }
        return try action()
    }
}
