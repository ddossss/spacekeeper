import Foundation
import CryptoKit
import Darwin

public enum KeeperError: LocalizedError {
    case unsafe(LocalizedMessage), changed(String), cancelled, busy
    public var errorDescription: String? { message.rendered }
    public var message: LocalizedMessage {
        switch self {
        case .unsafe(let message): return message
        case .changed(let path): return "검사 후 파일이 변경되었습니다. 다시 검사해 주세요: \(path)"
        case .cancelled: return "검사를 취소했습니다."
        case .busy: return "다른 정리 작업이 진행 중입니다. 잠시 후 다시 시도해 주세요."
        }
    }
}

public final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw KeeperError.cancelled }
    }
}

public struct FileStamp: Codable, Equatable, Sendable {
    public let device: Int32
    public let inode: UInt64
    public let bytes: Int64
    public let modified: Double
    public let changed: Double
    public let accessed: Double
    public let links: UInt16

    public init(url: URL) throws {
        var value = stat()
        guard lstat(url.path, &value) == 0,
              (value.st_mode & S_IFMT) == S_IFREG,
              value.st_flags & UInt32(UF_COMPRESSED | UF_IMMUTABLE | SF_IMMUTABLE) == 0 else {
            throw KeeperError.unsafe("일반 로컬 파일만 처리합니다: \(url.path)")
        }
        device = value.st_dev; inode = value.st_ino; bytes = value.st_size
        modified = Double(value.st_mtimespec.tv_sec) + Double(value.st_mtimespec.tv_nsec) / 1e9
        changed = Double(value.st_ctimespec.tv_sec) + Double(value.st_ctimespec.tv_nsec) / 1e9
        accessed = Double(value.st_atimespec.tv_sec) + Double(value.st_atimespec.tv_nsec) / 1e9
        links = value.st_nlink
    }

    public func sameFile(as other: FileStamp) -> Bool {
        device == other.device && inode == other.inode && bytes == other.bytes &&
        modified == other.modified && changed == other.changed && links == other.links
    }
}

public struct FileEntry: Identifiable, Codable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let root: URL
    public let stamp: FileStamp
    public var digest: String?
    public var bytes: Int64 { stamp.bytes }
    public init(url: URL, root: URL, digest: String? = nil) throws {
        self.url = url.standardizedFileURL; self.root = root.standardizedFileURL
        self.stamp = try FileStamp(url: url); self.digest = digest
    }
}

public enum FileSafety {
    public static let excludedNames: Set<String> = [
        ".git", ".svn", "node_modules", ".build", ".Trash", ".Trashes", ".Spotlight-V100",
        ".fseventsd", "__pycache__", ".venv", "venv", "Pods", "DerivedData", "codex-work"
    ]
    public static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "photoslibrary", "photolibrary", "musiclibrary",
        "sparsebundle", "backupbundle", "xcodeproj", "xcworkspace", "pages", "numbers", "key"
    ]

    public static func contains(_ root: URL, _ child: URL) -> Bool {
        let r = root.standardizedFileURL.path
        return child.standardizedFileURL.path.hasPrefix(r == "/" ? "/" : r + "/")
    }

    /// Reject every symbolic-link component, including symlinked parents.
    public static func noSymlinks(_ url: URL) throws {
        var current = URL(fileURLWithPath: "/")
        for part in url.standardizedFileURL.pathComponents.dropFirst() {
            current.appendPathComponent(part)
            var value = stat()
            guard lstat(current.path, &value) == 0 else { throw KeeperError.changed(current.path) }
            guard (value.st_mode & S_IFMT) != S_IFLNK else {
                throw KeeperError.unsafe("심볼릭 링크 경로는 제외합니다: \(current.path)")
            }
        }
    }

    public static func validateRoot(_ root: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let root = root.standardizedFileURL
        try noSymlinks(root)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else {
            throw KeeperError.unsafe("검사할 폴더를 선택해 주세요.")
        }
        let protected = ["/System", "/Library", "/Applications", "/private", "/usr", "/bin", "/sbin", "/dev"]
            .map { URL(fileURLWithPath: $0) } + [home.appendingPathComponent("Library"), home.appendingPathComponent(".Trash")]
        guard root.path != "/", root.path != "/Users", !protected.contains(where: { root == $0 || contains($0, root) }),
              !root.pathComponents.contains(where: { excludedNames.subtracting(["codex-work"]).contains($0) || packageExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) else {
            throw KeeperError.unsafe("시스템·라이브러리·앱 내부는 검사 대상에서 제외합니다. 문서 폴더를 선택해 주세요.")
        }
    }

    public static func validate(_ entry: FileEntry) throws {
        guard contains(entry.root, entry.url) else { throw KeeperError.unsafe("검사한 폴더 밖의 파일입니다.") }
        try noSymlinks(entry.url)
        let now = try FileStamp(url: entry.url)
        guard entry.stamp.sameFile(as: now), now.links == 1 else { throw KeeperError.changed(entry.url.path) }
        let values = try entry.url.resourceValues(forKeys: [.isUbiquitousItemKey])
        guard values.isUbiquitousItem != true, entry.url.pathExtension != "icloud" else {
            throw KeeperError.unsafe("클라우드 파일은 제외합니다.")
        }
    }

    public static func hash(_ entry: FileEntry, token: Cancellation) throws -> String {
        try validate(entry)
        let fd = open(entry.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw KeeperError.unsafe("파일을 읽을 수 없습니다: \(entry.url.path)") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_ino == entry.stamp.inode,
              info.st_dev == entry.stamp.device, (info.st_mode & S_IFMT) == S_IFREG else {
            throw KeeperError.changed(entry.url.path)
        }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        while true {
            try token.check()
            let count = read(fd, &buffer, buffer.count)
            if count < 0 { throw KeeperError.unsafe("파일 읽기에 실패했습니다: \(entry.url.path)") }
            if count == 0 { break }
            hasher.update(data: Data(buffer[0..<count]))
        }
        try validate(entry)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct ScanReport: Sendable {
    public var files: [FileEntry] = []
    public var issues: [LocalizedMessage] = []
    public var skipped = 0
    public var truncated = false
    public init() {}
}

public struct DuplicateGroup: Identifiable, Sendable {
    public let id: String
    public let files: [FileEntry]
    public var reclaimable: Int64 { Int64(max(0, files.count - 1)) * (files.first?.bytes ?? 0) }
}

public enum Scanner {
    public static func walk(roots: [URL], minimumBytes: Int64 = 1, token: Cancellation,
                            cacheMode: Bool = false, limit: Int = 200_000, excludedPaths: [String] = [],
                            progress: @escaping (LocalizedMessage) -> Void = { _ in }) throws -> ScanReport {
        var result = ScanReport()
        var seen = Set<String>()
        var visited = 0
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        for root in roots.map({ $0.standardizedFileURL }) {
            try token.check()
            if excludedPaths.contains(where: { root.path == $0 || FileSafety.contains(URL(fileURLWithPath: $0), root) }) { continue }
            if cacheMode { try FileSafety.noSymlinks(root) } else { try FileSafety.validateRoot(root) }
            let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey, .isUbiquitousItemKey]
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                errorHandler: { url, error in
                if result.issues.count < 30 { result.issues.append("\(url.path): \(LocalizedMessage.error(error))") }
                return true
            }) else { result.issues.append("폴더에 접근할 수 없습니다: \(root.path)"); continue }
            for case let url as URL in enumerator {
                try token.check()
                visited += 1
                if visited > limit { result.truncated = true; return result }
                do {
                    let values = try url.resourceValues(forKeys: Set(keys))
                    let excluded = FileSafety.excludedNames.contains(url.lastPathComponent) ||
                        excludedPaths.contains(where: { url.path == $0 || FileSafety.contains(URL(fileURLWithPath: $0), url) }) ||
                        FileSafety.packageExtensions.contains(url.pathExtension.lowercased()) ||
                        values.isSymbolicLink == true || values.isUbiquitousItem == true ||
                        values.isPackage == true || url.pathExtension == "icloud" ||
                        (!cacheMode && (url == home.appendingPathComponent("Library") ||
                         ["System", "Applications", "Library"].contains(url.lastPathComponent) && values.isDirectory == true))
                    if excluded { enumerator.skipDescendants(); result.skipped += 1; continue }
                    guard values.isRegularFile == true else { continue }
                    let entry = try FileEntry(url: url, root: root)
                    guard entry.bytes >= minimumBytes, entry.stamp.links == 1 else { result.skipped += 1; continue }
                    guard seen.insert(entry.id).inserted else { continue }
                    try FileSafety.validate(entry)
                    result.files.append(entry)
                    if result.files.count % 150 == 0 { progress("\(result.files.count)개 파일 확인 중…") }
                } catch {
                    result.skipped += 1
                    if result.issues.count < 30 { result.issues.append("\(url.lastPathComponent): \(LocalizedMessage.error(error))") }
                }
            }
        }
        return result
    }

    public static func duplicates(in report: inout ScanReport, token: Cancellation,
                                  progress: @escaping (LocalizedMessage) -> Void = { _ in }) throws -> [DuplicateGroup] {
        let buckets = Dictionary(grouping: report.files, by: \.bytes).values.filter { $0.count > 1 }
        var groups: [DuplicateGroup] = []
        var checked = 0
        let total = buckets.reduce(0) { $0 + $1.count }
        for bucket in buckets {
            var hashed: [String: [FileEntry]] = [:]
            for var file in bucket {
                try token.check()
                checked += 1
                progress("파일 내용 비교 \(checked) / \(total) · \(file.url.lastPathComponent)")
                do {
                    let digest = try FileSafety.hash(file, token: token)
                    file.digest = digest
                    hashed[digest, default: []].append(file)
                } catch KeeperError.cancelled { throw KeeperError.cancelled }
                catch { if report.issues.count < 30 { report.issues.append(.error(error)) } }
            }
            groups += hashed.filter { $0.value.count > 1 }.map {
                DuplicateGroup(id: $0.key, files: $0.value.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending })
            }
        }
        return groups.sorted { $0.reclaimable > $1.reclaimable }
    }
}
