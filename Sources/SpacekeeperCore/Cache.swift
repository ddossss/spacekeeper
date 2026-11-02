import Foundation
import AppKit

public struct CacheRule: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let relativePath: String
    public let bundleID: String
    public func root(home: URL) -> URL { home.appendingPathComponent("Library/Caches").appendingPathComponent(relativePath) }
    public static let supported: [CacheRule] = [
        CacheRule(id: "chrome", name: "Google Chrome", relativePath: "Google/Chrome", bundleID: "com.google.Chrome"),
        CacheRule(id: "edge", name: "Microsoft Edge", relativePath: "Microsoft Edge", bundleID: "com.microsoft.edgemac"),
        CacheRule(id: "firefox", name: "Firefox", relativePath: "Firefox", bundleID: "org.mozilla.firefox"),
        CacheRule(id: "brave", name: "Brave Browser", relativePath: "BraveSoftware/Brave-Browser", bundleID: "com.brave.Browser"),
        CacheRule(id: "spotify", name: "Spotify", relativePath: "com.spotify.client", bundleID: "com.spotify.client"),
        CacheRule(id: "vscode", name: "Visual Studio Code", relativePath: "com.microsoft.VSCode", bundleID: "com.microsoft.VSCode")
    ]
    public var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            guard let id = $0.bundleIdentifier else { return false }
            return id == bundleID || id.hasPrefix(bundleID + ".")
        }
    }
}

public struct CacheGroup: Identifiable, Sendable {
    public var id: String { rule.id }
    public let rule: CacheRule
    public let files: [FileEntry]
    public let status: LocalizedMessage
    public var bytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
}

public enum CacheScanner {
    public static func scan(ids: Set<String>, minimumDays: Int, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            token: Cancellation, now: Date = Date(), excludedPaths: [String] = [],
                            running: (CacheRule) -> Bool = { $0.isRunning },
                            progress: @escaping (LocalizedMessage) -> Void = { _ in }) throws -> ([CacheGroup], [LocalizedMessage]) {
        guard minimumDays >= 7 else { throw KeeperError.unsafe("캐시는 최소 7일 보관해야 합니다.") }
        var groups: [CacheGroup] = []; var issues: [LocalizedMessage] = []
        let cutoff = now.addingTimeInterval(-Double(minimumDays) * 86400).timeIntervalSince1970
        for rule in CacheRule.supported where ids.contains(rule.id) {
            try token.check()
            let root = rule.root(home: home)
            guard FileManager.default.fileExists(atPath: root.path) else {
                groups.append(CacheGroup(rule: rule, files: [], status: "캐시 없음")); continue
            }
            if running(rule) {
                groups.append(CacheGroup(rule: rule, files: [], status: "실행 중 · 앱 종료 후 검사")); continue
            }
            progress("\(rule.name) 캐시 확인 중…")
            do {
                let report = try Scanner.walk(roots: [root], token: token, cacheMode: true, excludedPaths: excludedPaths, progress: progress)
                let eligible = report.files.filter { max($0.stamp.modified, $0.stamp.accessed) < cutoff }
                issues += report.issues
                if report.truncated { issues.append("\(rule.name): 20만 항목 제한에 도달했습니다. 일부 결과입니다.") }
                groups.append(CacheGroup(rule: rule, files: eligible, status: eligible.isEmpty ? "정리할 오래된 캐시 없음" : "\(eligible.count)개 파일"))
            } catch KeeperError.cancelled { throw KeeperError.cancelled }
            catch { issues.append(.error(error)); groups.append(CacheGroup(rule: rule, files: [], status: "접근할 수 없음")) }
        }
        return (groups, issues)
    }
}
