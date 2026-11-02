import Foundation
import Darwin

public enum Scheduler {
    public static let label = "local.spacekeeper.cache-cleanup"
    public static func plist(settings: Settings, executable: URL, state: URL) throws -> Data {
        try settings.validate()
        var calendar = ["Hour": settings.hour, "Minute": settings.minute]
        if !settings.daily { calendar["Weekday"] = settings.weekday }
        let value: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable.path, "--scheduled", "--state", state.path],
            "StartCalendarInterval": calendar,
            "ProcessType": "Background",
            "LowPriorityIO": true,
            "Nice": 10,
            "RunAtLoad": false,
            "StandardOutPath": state.appendingPathComponent("scheduler.log").path,
            "StandardErrorPath": state.appendingPathComponent("scheduler-error.log").path
        ]
        return try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    }

    @discardableResult
    private static func launchctl(_ arguments: [String], allowFailure: Bool = false) throws -> Bool {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe(); process.standardError = pipe; process.standardOutput = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 && !allowFailure {
            throw KeeperError.unsafe("예약 작업 등록에 실패했습니다. 시스템 설정의 로그인 항목을 확인해 주세요. \(String(data: data, encoding: .utf8) ?? "")")
        }
        return process.terminationStatus == 0
    }

    public static var isLoaded: Bool {
        (try? launchctl(["print", "gui/\(getuid())/\(label)"], allowFailure: true)) == true
    }

    public static func apply(_ settings: Settings, store: Store, executable: URL) throws {
        try settings.validate()
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw KeeperError.unsafe("앱 실행 파일을 찾을 수 없습니다. 앱을 다시 빌드해 주세요.")
        }
        try store.withLock {
            let fm = FileManager.default
            let agents = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
            let target = agents.appendingPathComponent(label + ".plist")
            let domain = "gui/\(getuid())"
            let previous = try store.settings()
            let previousPlist = try? Data(contentsOf: target)
            // Fail closed: disable the worker before replacing a registration.
            var disabled = settings; disabled.scheduleEnabled = false
            try store.save(settings: disabled)
            do {
                if isLoaded { try launchctl(["bootout", "\(domain)/\(label)"]) }
                if settings.scheduleEnabled {
                    try fm.createDirectory(at: agents, withIntermediateDirectories: true)
                    try FileSafety.noSymlinks(agents)
                    try plist(settings: settings, executable: executable, state: store.root).write(to: target, options: .atomic)
                    try launchctl(["bootstrap", domain, target.path])
                } else if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try store.save(settings: settings)
            } catch {
                // Restore prior configuration and registration when possible.
                _ = try? launchctl(["bootout", "\(domain)/\(label)"], allowFailure: true)
                if let previousPlist {
                    try? previousPlist.write(to: target, options: .atomic)
                    if previous.scheduleEnabled { _ = try? launchctl(["bootstrap", domain, target.path]) }
                } else { try? fm.removeItem(at: target) }
                var rollback = previous
                rollback.scheduleEnabled = previous.scheduleEnabled && isLoaded
                try? store.save(settings: rollback)
                throw error
            }
        }
    }

    public static func run(store: Store) throws {
        L10n.language = try store.language()
        let settings = try store.settings()
        guard settings.scheduleEnabled else { return }
        let token = Cancellation()
        let (groups, issues) = try CacheScanner.scan(ids: settings.cacheIDs, minimumDays: settings.minimumDays, token: token, excludedPaths: settings.excludedPaths)
        let files = groups.flatMap(\.files).sorted { $0.stamp.modified < $1.stamp.modified }
        if files.isEmpty {
            try store.withLock {
                var record = HistoryRecord(kind: "정기 캐시 청소")
                record.setNote(issues.isEmpty ? "정리할 오래된 캐시가 없거나 앱이 실행 중이었습니다." : .joined(issues))
                try store.save(record: record)
            }
        } else {
            _ = try Cleaner(store: store).clean(.cache(files, minimumDays: settings.minimumDays), scheduled: true)
        }
    }
}
