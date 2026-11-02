import Foundation
import SpacekeeperCore

let project = URL(fileURLWithPath: CommandLine.arguments[1])
let executable = project.appendingPathComponent("codex-work/dist/Spacekeeper.app/Contents/MacOS/Spacekeeper")
let store = Store(root: project.appendingPathComponent("codex-work/2026-11-02-validation/scheduler-state"))
let agent = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(Scheduler.label).plist")
func failure(_ message: String) -> Error {
    NSError(domain: "ScheduleTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
guard !Scheduler.isLoaded, !FileManager.default.fileExists(atPath: agent.path) else {
    throw failure("기존 예약 작업이 있어 통합 테스트를 중단합니다.")
}
var settings = Settings()
settings.cacheIDs = [] // This integration test can never select real cache files.
settings.scheduleEnabled = true
settings.hour = (Calendar.current.component(.hour, from: Date()) + 1) % 24
let previousCount = try store.history().count
do {
    try Scheduler.apply(settings, store: store, executable: executable)
    guard Scheduler.isLoaded else { throw failure("launchd 등록 실패") }
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["kickstart", "gui/\(getuid())/\(Scheduler.label)"]
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw failure("예약 프로세스 실행 실패") }
    let deadline = Date().addingTimeInterval(15)
    while (try store.history()).count == previousCount && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    let records = try store.history()
    guard records.count == previousCount + 1, records[0].movedCount == 0 else {
        throw NSError(domain: "ScheduleTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "예약 no-op 기록 없음"])
    }
    settings.scheduleEnabled = false
    try Scheduler.apply(settings, store: store, executable: executable)
    guard !Scheduler.isLoaded, !FileManager.default.fileExists(atPath: agent.path) else { throw failure("예약 해제 실패") }
    print("PASS: launchd bootstrap, kickstart, headless no-op history, bootout, plist removal")
} catch {
    settings.scheduleEnabled = false
    try? Scheduler.apply(settings, store: store, executable: executable)
    fputs("FAIL: \(error.localizedDescription)\n", stderr)
    exit(1)
}
