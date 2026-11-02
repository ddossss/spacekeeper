#if !STANDALONE_TESTS
import XCTest
#endif
import Foundation
import Darwin
@testable import SpacekeeperCore

final class SafetyTests: XCTestCase {
    var root: URL!
    var documents: URL!
    var trash: URL!
    var store: Store!
    let fm = FileManager.default

    override func setUpWithError() throws {
        L10n.language = .korean
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        root = project.appendingPathComponent("codex-work/test-fixtures/\(UUID().uuidString)")
        documents = root.appendingPathComponent("documents")
        trash = root.appendingPathComponent("test-trash")
        store = Store(root: root.appendingPathComponent("state"))
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let root { try fm.removeItem(at: root) } }

    @discardableResult func file(_ name: String, content: String = "same contents", base: URL? = nil, ageDays: Int? = nil) throws -> URL {
        let url = (base ?? documents).appendingPathComponent(name)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        if let ageDays {
            let seconds = Int(Date().addingTimeInterval(-Double(ageDays) * 86400).timeIntervalSince1970)
            var times = [timeval(tv_sec: seconds, tv_usec: 0), timeval(tv_sec: seconds, tv_usec: 0)]
            XCTAssertEqual(utimes(url.path, &times), 0)
        }
        return url
    }
    func groups() throws -> [DuplicateGroup] {
        var report = try Scanner.walk(roots: [documents], token: Cancellation())
        return try Scanner.duplicates(in: &report, token: Cancellation())
    }
    func cleaner(home: URL? = nil) -> Cleaner {
        Cleaner(store: store, home: home ?? fm.homeDirectoryForCurrentUser, trash: { [self] url in
            let dest = trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try fm.moveItem(at: url, to: dest)
            return dest
        })
    }

    func testContentMatchingNotNameOrSize() throws {
        try file("a", content: "abc"); try file("b", content: "abc"); try file("c", content: "xyz")
        let result = try groups()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(Set(result[0].files.map { $0.url.lastPathComponent }), ["a", "b"])
        XCTAssertEqual(result[0].reclaimable, 3)
    }
    func testOverlappingRootsDoNotCreateFalseDuplicates() throws {
        let nested = documents.appendingPathComponent("nested")
        try file("single", base: nested)
        var result = try Scanner.walk(roots: [documents, nested], token: Cancellation())
        XCTAssertEqual(result.files.count, 1)
        XCTAssertTrue(try Scanner.duplicates(in: &result, token: Cancellation()).isEmpty)
    }
    func testSymlinkAndHardlinkAndPackagesExcluded() throws {
        let original = try file("original")
        try fm.createSymbolicLink(at: documents.appendingPathComponent("symbolic"), withDestinationURL: original)
        try fm.linkItem(at: original, to: documents.appendingPathComponent("hardlink"))
        try file("Sample.app/inside"); try file("node_modules/inside"); try file(".hidden")
        try file("cloud.icloud")
        XCTAssertTrue(try Scanner.walk(roots: [documents], token: Cancellation()).files.isEmpty)
    }
    func testSymlinkRootRejected() throws {
        let link = root.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: documents)
        XCTAssertThrowsError(try Scanner.walk(roots: [link], token: Cancellation()))
    }
    func testProtectedRootsRejected() throws {
        XCTAssertThrowsError(try FileSafety.validateRoot(URL(fileURLWithPath: "/")))
        XCTAssertThrowsError(try FileSafety.validateRoot(URL(fileURLWithPath: "/Applications")))
        XCTAssertThrowsError(try FileSafety.validateRoot(fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")))
    }
    func testExcludedFolderAndScanLimit() throws {
        try file("keep/a"); try file("scan/b"); try file("scan/c")
        let result = try Scanner.walk(roots: [documents], token: Cancellation(), excludedPaths: [documents.appendingPathComponent("keep").path])
        XCTAssertEqual(result.files.count, 2)
        XCTAssertTrue(try Scanner.walk(roots: [documents], token: Cancellation(), limit: 1).truncated)
    }
    func testCancellation() throws {
        try file("a")
        let token = Cancellation(); token.cancel()
        XCTAssertThrowsError(try Scanner.walk(roots: [documents], token: token))
    }
    func testRefusesDeletingEveryCopy() throws {
        try file("a"); try file("b")
        let groups = try groups()
        XCTAssertThrowsError(try cleaner().clean(.duplicates(groups, selected: Set(groups[0].files.map(\.id)))))
        XCTAssertTrue(fm.fileExists(atPath: documents.appendingPathComponent("a").path))
        XCTAssertTrue(fm.fileExists(atPath: documents.appendingPathComponent("b").path))
    }
    func testChangedKeeperBlocksDuplicateCleanup() throws {
        try file("a"); let b = try file("b")
        let groups = try groups()
        try file("a", content: "replaced contents")
        XCTAssertThrowsError(try cleaner().clean(.duplicates(groups, selected: [b.path])))
        XCTAssertTrue(fm.fileExists(atPath: b.path))
    }
    func testChangedTargetNotMoved() throws {
        try file("a"); let b = try file("b")
        let groups = try groups()
        try file("b", content: "new data")
        let record = try cleaner().clean(.duplicates(groups, selected: [b.path]))
        XCTAssertEqual(record.movedCount, 0)
        XCTAssertNotNil(record.items.first?.error)
        XCTAssertTrue(fm.fileExists(atPath: b.path))
    }
    func testDuplicateTrashAndRestore() throws {
        let a = try file("a"); let b = try file("b")
        let record = try cleaner().clean(.duplicates(try groups(), selected: [b.path]))
        XCTAssertEqual(record.movedCount, 1)
        XCTAssertTrue(fm.fileExists(atPath: a.path)); XCTAssertFalse(fm.fileExists(atPath: b.path))
        let restored = try cleaner().restore(recordID: record.id)
        XCTAssertTrue(restored.items[0].restored)
        XCTAssertEqual(try String(contentsOf: b, encoding: .utf8), "same contents")
    }
    func testRestoreWillNotOverwriteExistingFile() throws {
        let a = try file("a")
        let entry = try FileEntry(url: a, root: documents)
        let record = try cleaner().clean(.largeFiles([entry]))
        try file("a", content: "new original")
        let restored = try cleaner().restore(recordID: record.id)
        XCTAssertFalse(restored.items[0].restored)
        XCTAssertNotNil(restored.items[0].error)
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "new original")
    }
    func testParentSymlinkSwapBlocked() throws {
        let a = try file("sub/a")
        let entry = try FileEntry(url: a, root: documents)
        let original = documents.appendingPathComponent("sub")
        let relocated = root.appendingPathComponent("relocated")
        try fm.moveItem(at: original, to: relocated)
        try fm.createSymbolicLink(at: original, withDestinationURL: relocated)
        let result = try cleaner().clean(.largeFiles([entry]))
        XCTAssertEqual(result.movedCount, 0)
        XCTAssertTrue(fm.fileExists(atPath: relocated.appendingPathComponent("a").path))
    }
    func testFreshAndRunningCacheExcluded() throws {
        let home = root.appendingPathComponent("home")
        let rule = CacheRule.supported[0]
        let cache = rule.root(home: home)
        try file("old", base: cache, ageDays: 30)
        try file("recent", base: cache, ageDays: 1)
        let (groups, _) = try CacheScanner.scan(ids: [rule.id], minimumDays: 14, home: home, token: Cancellation(), running: { _ in false })
        XCTAssertEqual(groups[0].files.map { $0.url.lastPathComponent }, ["old"])
        let (running, _) = try CacheScanner.scan(ids: [rule.id], minimumDays: 14, home: home, token: Cancellation(), running: { _ in true })
        XCTAssertTrue(running[0].files.isEmpty)
        let blocked = try cleaner(home: home).clean(.cache(groups[0].files, minimumDays: 14), running: { _ in true })
        XCTAssertEqual(blocked.movedCount, 0)
    }
    func testCacheCannotEscapeAllowlist() throws {
        let url = try file("not-cache", ageDays: 30)
        let result = try cleaner().clean(.cache([FileEntry(url: url, root: documents)], minimumDays: 14), running: { _ in false })
        XCTAssertEqual(result.movedCount, 0)
        XCTAssertTrue(fm.fileExists(atPath: url.path))
    }
    func testScheduleOffAndByteBudget() throws {
        let home = root.appendingPathComponent("home")
        let rule = CacheRule.supported[0]
        let cache = rule.root(home: home)
        try file("old-a", content: "12345", base: cache, ageDays: 30)
        try file("old-b", content: "12345", base: cache, ageDays: 30)
        let (groups, _) = try CacheScanner.scan(ids: [rule.id], minimumDays: 14, home: home, token: Cancellation(), running: { _ in false })
        let request = CleanupRequest.cache(groups[0].files, minimumDays: 14)
        XCTAssertThrowsError(try cleaner(home: home).clean(request, scheduled: true, running: { _ in false }))
        var settings = Settings(); settings.scheduleEnabled = true; settings.maxScheduledBytes = 5
        try store.save(settings: settings)
        let result = try cleaner(home: home).clean(request, scheduled: true, running: { _ in false })
        XCTAssertEqual(result.movedCount, 1); XCTAssertEqual(result.movedBytes, 5)
    }
    func testExclusionRecheckedBeforeCleanup() throws {
        let a = try file("a")
        let entry = try FileEntry(url: a, root: documents)
        var settings = Settings(); settings.excludedPaths = [documents.path]
        try store.save(settings: settings)
        let result = try cleaner().clean(.largeFiles([entry]))
        XCTAssertEqual(result.movedCount, 0)
    }
    func testCrossProcessLockRejectsConcurrentOperation() throws {
        try store.withLock { XCTAssertThrowsError(try store.withLock { true }) }
    }
    func testSchedulePlistAndSettingsValidation() throws {
        var settings = Settings(); settings.daily = false; settings.weekday = 3; settings.hour = 9; settings.minute = 20
        let data = try Scheduler.plist(settings: settings, executable: URL(fileURLWithPath: "/with spaces/Spacekeeper"), state: store.root)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual((plist["StartCalendarInterval"] as? [String: Int])?["Weekday"], 3)
        XCTAssertEqual((plist["ProgramArguments"] as? [String])?.first, "/with spaces/Spacekeeper")
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, false)
        settings.daily = true
        let daily = try PropertyListSerialization.propertyList(from: Scheduler.plist(settings: settings, executable: root, state: store.root), format: nil) as? [String: Any]
        XCTAssertNil((daily?["StartCalendarInterval"] as? [String: Int])?["Weekday"])
        settings.minimumDays = 0
        XCTAssertThrowsError(try store.save(settings: settings))
    }
    func testCorruptSettingsFailsClosed() throws {
        try store.prepare()
        try Data("broken".utf8).write(to: store.root.appendingPathComponent("settings.json"))
        XCTAssertThrowsError(try store.settings())
        let a = try file("a")
        XCTAssertThrowsError(try cleaner().clean(.largeFiles([FileEntry(url: a, root: documents)])))
        XCTAssertTrue(fm.fileExists(atPath: a.path))
    }
    func testNativeTrashAPIAndRestore() throws {
        let url = try file("spacekeeper-native-trash-test.txt")
        let entry = try FileEntry(url: url, root: documents)
        let cleaner = Cleaner(store: store)
        let record = try cleaner.clean(.largeFiles([entry]))
        XCTAssertEqual(record.movedCount, 1)
        XCTAssertFalse(fm.fileExists(atPath: url.path))
        let restored = try cleaner.restore(recordID: record.id)
        XCTAssertTrue(restored.items.first?.restored == true)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "same contents")
    }
    func testJournalRecoversInterruptedOperationAndTruncatedLastEvent() throws {
        let url = try file("a")
        let record = HistoryRecord(kind: "테스트")
        try store.save(record: record)
        var item = HistoryItem(source: url, bytes: 13)
        item.pending = true
        try store.append(item: item, recordID: record.id)
        item.pending = false; item.error = "test failure"
        try store.append(item: item, recordID: record.id)
        let journal = store.root.appendingPathComponent("history/\(record.id.uuidString).jsonl")
        let handle = try FileHandle(forWritingTo: journal)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("{incomplete".utf8)); try handle.close()
        let recovered = try XCTUnwrap(store.history().first)
        XCTAssertEqual(recovered.items.count, 1)
        XCTAssertEqual(recovered.items[0].error, "test failure")
        try store.finish(record: recovered)
        XCTAssertFalse(fm.fileExists(atPath: journal.path))
        XCTAssertEqual(try store.history().first?.items.count, 1)
    }
    func testCacheExclusionAppliesToScan() throws {
        let home = root.appendingPathComponent("home")
        let rule = CacheRule.supported[0]
        let cache = rule.root(home: home)
        try file("protected/old", base: cache, ageDays: 30)
        try file("eligible", base: cache, ageDays: 30)
        let (groups, _) = try CacheScanner.scan(ids: [rule.id], minimumDays: 14, home: home, token: Cancellation(),
            excludedPaths: [cache.appendingPathComponent("protected").path], running: { _ in false })
        XCTAssertEqual(groups[0].files.map { $0.url.lastPathComponent }, ["eligible"])
    }
    func testLanguageSelectionPersistsWithoutChangingCleanupSettings() throws {
        var settings = Settings(); settings.scheduleEnabled = true; settings.hour = 17
        try store.save(settings: settings)
        for language in AppLanguage.allCases {
            try store.save(language: language)
            XCTAssertEqual(try Store(root: store.root).language(), language)
            XCTAssertTrue(try store.settings().scheduleEnabled)
            XCTAssertEqual(try store.settings().hour, 17)
        }
    }
    func testLocalizedMessagesFollowLanguageAndPreservePathArguments() throws {
        let path = "/files/{1}/보고서.txt"
        let message: LocalizedMessage = "검사 후 파일이 변경되었습니다. 다시 검사해 주세요: \(path)"
        XCTAssertTrue(message.render(in: .english).hasPrefix("This file changed"))
        XCTAssertTrue(message.render(in: .japanese).hasPrefix("スキャン後"))
        XCTAssertTrue(message.render(in: .korean).hasPrefix("검사 후"))
        for language in AppLanguage.allCases { XCTAssertTrue(message.render(in: language).contains(path)) }
        let nested: LocalizedMessage = "설정 또는 기록을 읽지 못했습니다: \(message)"
        XCTAssertTrue(nested.render(in: .english).contains("This file changed"))
        let decoded = try JSONDecoder().decode(LocalizedMessage.self, from: JSONEncoder().encode(nested))
        XCTAssertEqual(decoded.render(in: .japanese), nested.render(in: .japanese))
    }
    func testHistoryLocalizationAndLegacyHistoryCompatibility() throws {
        var record = HistoryRecord(kind: "정기 캐시 청소")
        record.setNote("남은 작업을 취소했습니다.")
        try store.save(record: record)
        L10n.language = .english
        XCTAssertEqual(try store.history().first?.displayNote, "Remaining tasks were canceled.")
        L10n.language = .japanese
        XCTAssertEqual(try store.history().first?.displayNote, "残りの処理をキャンセルしました。")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        json.removeValue(forKey: "localizedNote")
        json["note"] = "남은 작업을 취소했습니다."
        let legacy = try JSONDecoder().decode(HistoryRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.displayNote, "残りの処理をキャンセルしました。")
        let item = HistoryItem(source: documents.appendingPathComponent("old.txt"), bytes: 1)
        var oldItem = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        oldItem.removeValue(forKey: "localizedError")
        _ = try JSONDecoder().decode(HistoryItem.self, from: JSONSerialization.data(withJSONObject: oldItem))
    }
    func testTranslationCatalogCoverageAndFormatting() throws {
        XCTAssertTrue(L10n.catalog.count >= 205)
        let placeholder = try NSRegularExpression(pattern: #"\{[0-9]+\}|%02d"#)
        func tokens(_ text: String) -> [String] {
            placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
                String(text[Range($0.range, in: text)!])
            }.sorted()
        }
        for (key, translations) in L10n.catalog {
            for language in [AppLanguage.english, .japanese] {
                let translated = try XCTUnwrap(translations[language.rawValue])
                XCTAssertFalse(translated.isEmpty)
                XCTAssertEqual(tokens(key), tokens(translated))
            }
        }
        L10n.language = .english
        XCTAssertEqual(L10n.bytes(1_500), "1.5 KB")
        XCTAssertEqual(L10n.bytes(42), "42 B")
        XCTAssertEqual(L10n.text("개요"), "Overview")
        let englishDate = L10n.date(Date(timeIntervalSince1970: 1_793_577_600))
        L10n.language = .japanese
        XCTAssertEqual(L10n.text("개요"), "概要")
        XCTAssertFalse(L10n.date(Date(timeIntervalSince1970: 1_793_577_600)) == englishDate)
    }
}
