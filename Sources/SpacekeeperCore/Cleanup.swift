import Foundation

public enum CleanupRequest: Sendable {
    case cache([FileEntry], minimumDays: Int)
    case duplicates([DuplicateGroup], selected: Set<String>)
    case largeFiles([FileEntry])

    public var files: [FileEntry] {
        switch self {
        case .cache(let files, _), .largeFiles(let files): return files
        case .duplicates(let groups, let selected): return groups.flatMap(\.files).filter { selected.contains($0.id) }
        }
    }
    public var title: String {
        switch self { case .cache: return "캐시 정리"; case .duplicates: return "중복 파일 정리"; case .largeFiles: return "대용량 파일 정리" }
    }
}

public final class Cleaner: @unchecked Sendable {
    public typealias TrashAction = (URL) throws -> URL
    private let store: Store
    private let home: URL
    private let trash: TrashAction
    public init(store: Store, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                trash: @escaping TrashAction = { url in
                    var destination: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
                    guard let destination else { throw KeeperError.unsafe("휴지통 위치를 확인할 수 없습니다. Finder에서 확인해 주세요.") }
                    return destination as URL
                }) {
        self.store = store; self.home = home; self.trash = trash
    }

    public func clean(_ request: CleanupRequest, scheduled: Bool = false, token: Cancellation = Cancellation(),
                      running: (CacheRule) -> Bool = { $0.isRunning }) throws -> HistoryRecord {
        try store.withLock {
            let settings = try store.settings()
            if scheduled {
                guard settings.scheduleEnabled, case .cache = request else {
                    throw KeeperError.unsafe("정기 캐시 청소가 꺼져 있습니다.")
                }
            }
            var seen = Set<String>()
            let entries = request.files.filter { seen.insert($0.id).inserted }
            guard !entries.isEmpty else { throw KeeperError.unsafe("정리할 파일을 선택해 주세요.") }
            var keepers: [String: FileEntry] = [:]
            if case .duplicates(let groups, let selected) = request {
                guard selected.isSubset(of: Set(groups.flatMap(\.files).map(\.id))) else {
                    throw KeeperError.unsafe("검사 결과에 없는 파일이 선택되었습니다.")
                }
                for group in groups where group.files.contains(where: { selected.contains($0.id) }) {
                    guard let keeper = group.files.first(where: { !selected.contains($0.id) }),
                          group.files.count >= 2 else {
                        throw KeeperError.unsafe("각 중복 그룹에서 최소 한 파일은 남겨야 합니다.")
                    }
                    try FileSafety.validateRoot(keeper.root, home: home)
                    guard let digest = keeper.digest, try FileSafety.hash(keeper, token: token) == digest else {
                        throw KeeperError.changed(keeper.url.path)
                    }
                    for file in group.files where selected.contains(file.id) {
                        guard file.digest == digest else { throw KeeperError.unsafe("파일 내용이 서로 다릅니다.") }
                        keepers[file.id] = keeper
                    }
                }
            }
            var record = HistoryRecord(kind: scheduled ? "정기 캐시 청소" : request.title)
            // Persist an intent before touching files; no cleanup if the journal cannot be written.
            try store.save(record: record)
            var movedBytes: Int64 = 0
            for entry in entries {
                do { try token.check() } catch { record.setNote("남은 작업을 취소했습니다."); break }
                if scheduled && movedBytes + entry.bytes > settings.maxScheduledBytes {
                    record.setNote("1회 정리 한도에 도달해 나머지 파일은 보관했습니다."); continue
                }
                var item = HistoryItem(source: entry.url, bytes: entry.bytes)
                do {
                    if settings.excludedPaths.contains(where: { entry.url.path == $0 || FileSafety.contains(URL(fileURLWithPath: $0), entry.url) }) {
                        throw KeeperError.unsafe("검사 제외 목록에 있는 파일입니다.")
                    }
                    try FileSafety.validate(entry)
                    switch request {
                    case .cache(_, let days):
                        guard days >= 7, let rule = CacheRule.supported.first(where: {
                            entry.root == $0.root(home: home) && FileSafety.contains($0.root(home: home), entry.url)
                        }), !running(rule), !scheduled || settings.cacheIDs.contains(rule.id) else {
                            throw KeeperError.unsafe("지원하지 않는 캐시이거나 앱이 실행 중입니다: \(entry.url.lastPathComponent)")
                        }
                        let stamp = try FileStamp(url: entry.url)
                        let minimum = scheduled ? max(days, settings.minimumDays) : days
                        guard max(stamp.modified, stamp.accessed) < Date().addingTimeInterval(-Double(minimum) * 86400).timeIntervalSince1970 else {
                            throw KeeperError.unsafe("최근 사용한 캐시는 보관합니다: \(entry.url.lastPathComponent)")
                        }
                    case .duplicates:
                        try FileSafety.validateRoot(entry.root, home: home)
                        guard let keeper = keepers[entry.id], let digest = entry.digest,
                              try FileSafety.hash(entry, token: token) == digest,
                              try FileSafety.hash(keeper, token: token) == digest else {
                            throw KeeperError.changed(entry.url.path)
                        }
                    case .largeFiles:
                        try FileSafety.validateRoot(entry.root, home: home)
                    }
                    try FileSafety.validate(entry)
                    item.pending = true
                    record.items.append(item)
                    try store.append(item: item, recordID: record.id)
                    let destination = try trash(entry.url)
                    item.trashURL = destination
                    item.trashStamp = try? FileStamp(url: destination)
                    item.pending = false
                    movedBytes += entry.bytes
                    record.items[record.items.count - 1] = item
                } catch {
                    item.pending = false
                    item.error = error.localizedDescription
                    item.localizedError = .error(error)
                    if record.items.last?.id == item.id { record.items[record.items.count - 1] = item }
                    else { record.items.append(item) }
                }
                // Stop immediately if recovery metadata cannot be persisted.
                try store.append(item: item, recordID: record.id)
            }
            try store.finish(record: record)
            return record
        }
    }

    public func restore(recordID: UUID) throws -> HistoryRecord {
        try store.withLock {
            guard var record = try store.history().first(where: { $0.id == recordID }) else {
                throw KeeperError.unsafe("정리 기록을 찾을 수 없습니다.")
            }
            // Compact any interrupted journal before appending new restore events.
            try store.finish(record: record)
            for index in record.items.indices {
                let item = record.items[index]
                guard let trashURL = item.trashURL, !item.restored else { continue }
                do {
                    guard let expected = item.trashStamp else { throw KeeperError.unsafe("Finder 휴지통에서 직접 복원해 주세요.") }
                    try FileSafety.noSymlinks(trashURL)
                    guard expected.sameFile(as: try FileStamp(url: trashURL)) else { throw KeeperError.changed(trashURL.path) }
                    try FileSafety.noSymlinks(item.source.deletingLastPathComponent())
                    guard !FileManager.default.fileExists(atPath: item.source.path) else {
                        throw KeeperError.unsafe("원래 위치에 같은 이름의 파일이 있어 덮어쓰지 않았습니다.")
                    }
                    try FileManager.default.moveItem(at: trashURL, to: item.source)
                    record.items[index].restored = true
                    record.items[index].error = nil
                    record.items[index].localizedError = nil
                } catch { record.items[index].error = error.localizedDescription; record.items[index].localizedError = .error(error) }
                try store.append(item: record.items[index], recordID: record.id)
            }
            try store.finish(record: record)
            return record
        }
    }
}
