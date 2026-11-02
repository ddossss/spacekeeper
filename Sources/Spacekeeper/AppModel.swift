import SwiftUI
import AppKit
import SpacekeeperCore

enum Page: String, CaseIterable, Identifiable {
    case overview = "개요", caches = "캐시 정리", duplicates = "중복 파일", large = "대용량 파일"
    case apps = "설치 앱", schedule = "정기 청소", history = "정리 기록"
    var id: String { rawValue }
    var title: String { L10n.text(rawValue) }
    var icon: String {
        switch self {
        case .overview: return "internaldrive"
        case .caches: return "sparkles"
        case .duplicates: return "doc.on.doc"
        case .large: return "externaldrive.badge.plus"
        case .apps: return "square.grid.2x2"
        case .schedule: return "calendar.badge.clock"
        case .history: return "clock.arrow.circlepath"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return L("Mac에 여유를, 파일에는 제자리를.")
        case .caches: return L("다시 생성할 수 있는 오래된 앱 캐시를 정리하세요.")
        case .duplicates: return L("내용이 완전히 같은 파일을 찾고, 남길 사본을 고르세요.")
        case .large: return L("큰 파일부터 살펴보면 공간을 더 쉽게 정리할 수 있어요.")
        case .apps: return L("설치된 앱을 확인하고, 필요 없는 앱은 Finder에서 관리하세요.")
        case .schedule: return L("정해진 시간에 오래된 캐시를 휴지통으로 옮깁니다.")
        case .history: return L("어떤 파일을 정리했는지 확인하고 원래 위치로 복원하세요.")
        }
    }
}

struct InstalledApp: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let version: String
}

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var language = AppLanguage.systemDefault
    @Published var page = Page.overview
    @Published var settings = Settings()
    @Published var cacheGroups: [CacheGroup] = []
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var largeFiles: [FileEntry] = []
    @Published var selected = Set<String>()
    @Published var keepers: [String: String] = [:]
    @Published var roots: [URL] = []
    @Published var history: [HistoryRecord] = []
    @Published var apps: [InstalledApp] = []
    @Published var busy = false
    @Published var status: LocalizedMessage = "검사할 항목을 선택해 주세요."
    @Published var issues: [LocalizedMessage] = []
    @Published var message: LocalizedMessage?
    @Published var pending: CleanupRequest?
    @Published var restoreID: UUID?
    @Published var capacity: Int64 = 0
    @Published var available: Int64 = 0
    @Published var lastScan: Date?
    @Published var scannedPage: Page?
    @Published var largeThreshold = 100
    @Published var search = ""
    @Published var scheduleLoaded = false
    let store: Store
    private var token = Cancellation()

    init(store: Store) {
        self.store = store
        do {
            language = try store.language(); L10n.language = language
            settings = try store.settings(); history = try store.history()
        }
        catch { message = "설정 또는 기록을 읽지 못했습니다: \(LocalizedMessage.error(error))" }
        refreshDisk()
        scheduleLoaded = Scheduler.isLoaded
    }

    func changeLanguage(_ language: AppLanguage) {
        guard !busy else { return }
        do {
            try store.save(language: language)
            L10n.language = language
            self.language = language
        } catch { message = .error(error) }
    }

    func refreshDisk() {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            capacity = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
            available = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        }
    }

    func selectFolder(exclusion: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = exclusion ? L("검사에서 제외") : L("검사 폴더 추가")
        if panel.runModal() == .OK {
            if exclusion {
                settings.excludedPaths = Array(Set(settings.excludedPaths + panel.urls.map(\.path))).sorted()
            } else {
                for url in panel.urls where !roots.contains(url) {
                    do { try FileSafety.validateRoot(url); roots.append(url) }
                    catch { message = .error(error) }
                }
                invalidate()
            }
        }
    }

    func invalidate() {
        selected = []; duplicateGroups = []; largeFiles = []; cacheGroups = []
        scannedPage = nil; lastScan = nil; search = ""; issues = []
    }
    func navigate(_ target: Page) {
        guard !busy else { return }
        if page != target { page = target; selected = []; search = "" }
        if target == .apps { loadApps() }
        if target == .history { reloadHistory() }
        if target == .schedule { scheduleLoaded = Scheduler.isLoaded }
    }
    func cancel() { token.cancel(); status = "현재 파일 처리를 마친 뒤 중단합니다…" }

    func scan() {
        guard !busy else { return }
        let target = page
        if target != .caches && roots.isEmpty { selectFolder(); if roots.isEmpty { return } }
        invalidate(); busy = true; status = "검사를 준비하고 있습니다…"; token = Cancellation()
        let token = token, roots = roots, settings = settings, threshold = Int64(largeThreshold) * 1024 * 1024
        Task { [self] in
            do {
                let result = try await Task.detached(priority: .utility) { [weak self] () -> ScanOutput in
                    let gate = ProgressGate()
                    let progress: (LocalizedMessage) -> Void = { text in
                        if gate.shouldSend() { Task { @MainActor [weak self] in self?.status = text } }
                    }
                    if target == .caches {
                        let (groups, issues) = try CacheScanner.scan(ids: settings.cacheIDs, minimumDays: settings.minimumDays, token: token, excludedPaths: settings.excludedPaths, progress: progress)
                        return ScanOutput(caches: groups, issues: issues)
                    }
                    var report = try Scanner.walk(roots: roots, minimumBytes: target == .large ? threshold : 1,
                                                  token: token, excludedPaths: settings.excludedPaths, progress: progress)
                    let groups = target == .duplicates ? try Scanner.duplicates(in: &report, token: token, progress: progress) : []
                    if report.truncated { report.issues.insert("20만 항목 제한에 도달했습니다. 폴더를 좁혀서 다시 검사해 주세요. 아래는 일부 결과입니다.", at: 0) }
                    return ScanOutput(duplicates: groups, large: target == .large ? report.files.sorted { $0.bytes > $1.bytes } : [],
                                      issues: report.issues, scanned: report.files.count, skipped: report.skipped)
                }.value
                cacheGroups = result.caches; duplicateGroups = result.duplicates; largeFiles = result.large
                keepers = Dictionary(uniqueKeysWithValues: result.duplicates.compactMap { group in group.files.first.map { (group.id, $0.id) } })
                issues = result.issues; scannedPage = target; lastScan = Date()
                status = target == .caches ? "캐시 검사 완료" : "\(result.scanned)개 파일 확인 · 제외 \(result.skipped)개"
            } catch { status = .error(error) }
            busy = false
        }
    }

    var selectedFiles: [FileEntry] {
        let files: [FileEntry]
        switch page {
        case .caches: files = cacheGroups.flatMap(\.files)
        case .duplicates: files = duplicateGroups.flatMap(\.files)
        case .large: files = largeFiles
        default: files = []
        }
        return files.filter { selected.contains($0.id) }
    }
    var selectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.bytes } }

    func review() {
        guard !selectedFiles.isEmpty else { return }
        switch page {
        case .caches: pending = .cache(selectedFiles, minimumDays: settings.minimumDays)
        case .duplicates: pending = .duplicates(duplicateGroups, selected: selected)
        case .large: pending = .largeFiles(selectedFiles)
        default: break
        }
    }
    func clean() {
        guard let request = pending else { return }
        pending = nil; busy = true; token = Cancellation(); status = "선택한 파일을 확인하고 휴지통으로 옮기는 중…"
        let store = store, token = token
        Task {
            do {
                let record = try await Task.detached(priority: .utility) {
                    try Cleaner(store: store).clean(request, token: token)
                }.value
                invalidate(); reloadHistory(); refreshDisk(); page = .history
                let failures = record.items.filter { $0.error != nil }.count
                let skipped: LocalizedMessage = failures > 0 ? " \(failures)개 항목은 건너뛰었습니다. 기록에서 이유를 확인하세요." : ""
                message = "\(record.movedCount)개 파일, \(formatBytes(record.movedBytes))을 휴지통으로 옮겼습니다.\(skipped)\n휴지통을 비우면 디스크 공간이 확보됩니다."
                status = "정리 완료"
            } catch { message = .error(error); reloadHistory(); status = "정리를 완료하지 못했습니다." }
            busy = false
        }
    }
    func restore(_ id: UUID) {
        busy = true; status = "원래 위치로 복원하는 중…"; let store = store
        Task {
            do {
                let record = try await Task.detached { try Cleaner(store: store).restore(recordID: id) }.value
                let failed = record.items.filter { $0.trashURL != nil && !$0.restored }.count
                message = failed == 0 ? "파일을 원래 위치로 복원했습니다." : "\(failed)개 파일을 복원하지 못했습니다. 휴지통과 정리 기록의 상세 내용을 확인하세요."
                reloadHistory(); invalidate(); refreshDisk()
            } catch { message = .error(error) }
            busy = false; status = "복원 작업 완료"
        }
    }
    func saveSettings(_ proposed: SpacekeeperCore.Settings) {
        guard let executable = Bundle.main.executableURL else { return }
        busy = true; status = "예약 설정을 저장하는 중…"
        let settings = proposed, store = store
        Task {
            do {
                try await Task.detached { try Scheduler.apply(settings, store: store, executable: executable) }.value
                self.settings = settings
                message = settings.scheduleEnabled ? "정기 청소를 켰습니다. Mac에 로그인한 동안 앱을 종료해도 예약이 실행됩니다." : "설정을 저장했습니다. 정기 청소는 꺼져 있습니다."
                invalidate()
            } catch { message = .error(error); if let saved = try? store.settings() { self.settings = saved } }
            scheduleLoaded = Scheduler.isLoaded; busy = false; status = "설정 저장 완료"
        }
    }
    func reloadHistory() {
        do { history = try store.history() } catch { message = .error(error) }
    }
    func loadApps() {
        let fm = FileManager.default
        apps = [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
            .flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
            .filter { $0.pathExtension == "app" }
            .map { url in InstalledApp(url: url, name: url.deletingPathExtension().lastPathComponent,
                                     version: Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct ScanOutput: Sendable {
    var caches: [CacheGroup] = []
    var duplicates: [DuplicateGroup] = []
    var large: [FileEntry] = []
    var issues: [LocalizedMessage] = []
    var scanned = 0
    var skipped = 0
}

private final class ProgressGate: @unchecked Sendable {
    private var last = Date.distantPast
    func shouldSend() -> Bool {
        guard Date().timeIntervalSince(last) > 0.15 else { return false }
        last = Date(); return true
    }
}

func formatBytes(_ value: Int64) -> String {
    L10n.bytes(value)
}
