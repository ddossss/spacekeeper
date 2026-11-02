#if DEBUG
import SwiftUI
import AppKit
import SpacekeeperCore

/// Development-only interaction/capture harness. All fixture files live under the supplied state path.
@MainActor enum UIValidation {
    private static var started = false
    static func run(model: AppModel) async {
        guard !started else { return }; started = true
        let fm = FileManager.default
        let output = model.store.root.deletingLastPathComponent().appendingPathComponent("ui-captures")
        let fixtures = model.store.root.deletingLastPathComponent().appendingPathComponent("ui-fixtures")
        do {
            try fm.createDirectory(at: output, withIntermediateDirectories: true)
            try fm.createDirectory(at: fixtures, withIntermediateDirectories: true)
            for language in AppLanguage.allCases {
                model.changeLanguage(language)
                guard model.language == language, try model.store.language() == language,
                      AppModel(store: model.store).language == language else { throw failure("Language persistence failed") }
                model.navigate(.overview); await pause(); try capture("language-\(language.rawValue)-overview", to: output)
                model.navigate(.schedule); await pause(); try capture("language-\(language.rawValue)-schedule", to: output)
            }
            model.changeLanguage(.english); model.navigate(.overview)
            let original = fixtures.appendingPathComponent("분기 보고서.txt")
            let duplicate = fixtures.appendingPathComponent("분기 보고서 사본.txt")
            try Data("Spacekeeper UI 검증용 문서입니다.\n".utf8).write(to: original)
            try Data("Spacekeeper UI 검증용 문서입니다.\n".utf8).write(to: duplicate)
            try Data(repeating: 0x61, count: 11 * 1024 * 1024).write(to: fixtures.appendingPathComponent("검토할 큰 파일.bin"))
            await pause()
            try capture("01-overview", to: output)
            model.navigate(.duplicates); model.roots = [fixtures]; model.scan()
            try await waitForJob(model)
            guard model.duplicateGroups.count == 1 else { throw failure("중복 그룹 1개가 필요합니다.") }
            model.selected = [duplicate.path]
            model.keepers[model.duplicateGroups[0].id] = original.path
            for language in AppLanguage.allCases {
                model.changeLanguage(language)
                guard model.selected.contains(duplicate.path), model.duplicateGroups.count == 1 else { throw failure("Language switch lost scan results") }
                await pause(); try capture("language-\(language.rawValue)-duplicates", to: output)
            }
            model.changeLanguage(.english)
            await pause(); try capture("02-duplicates", to: output)
            model.review(); await pause(); try capture("03-review", to: output)
            model.clean(); try await waitForJob(model)
            guard !fm.fileExists(atPath: duplicate.path), fm.fileExists(atPath: original.path) else { throw failure("휴지통 이동 검증 실패") }
            model.message = nil; await pause(); try capture("04-history", to: output)
            for language in AppLanguage.allCases {
                model.changeLanguage(language); await pause(); try capture("language-\(language.rawValue)-history", to: output)
            }
            guard let record = model.history.first else { throw failure("정리 기록 없음") }
            model.restore(record.id); try await waitForJob(model); model.message = nil
            guard fm.fileExists(atPath: duplicate.path) else { throw failure("복원 검증 실패") }
            model.navigate(.large); model.largeThreshold = 10; model.scan(); try await waitForJob(model)
            guard model.largeFiles.count == 1 else { throw failure("대용량 파일 검사 실패") }
            await pause(); try capture("05-large-files", to: output)
            model.navigate(.caches); await pause(); try capture("06-cache-empty", to: output)
            model.navigate(.schedule); await pause(); try capture("07-schedule", to: output)
            model.navigate(.apps); await pause(); try capture("08-apps", to: output)
            try Data("PASS: ko/ja/en immediate switching, persistence, retained selection, localized history, overview, duplicate scan, review, native trash, restore, large-file scan, schedule and app views\n".utf8)
                .write(to: output.appendingPathComponent("result.txt"))
            NSApp.terminate(nil)
        } catch {
            try? Data("FAIL: \(error)\n".utf8).write(to: output.appendingPathComponent("result.txt"))
            NSApp.terminate(nil)
        }
    }
    private static func failure(_ text: String) -> Error { NSError(domain: "UIValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private static func pause() async { try? await Task.sleep(nanoseconds: 700_000_000) }
    private static func waitForJob(_ model: AppModel) async throws {
        let deadline = Date().addingTimeInterval(40)
        while model.busy {
            if Date() > deadline { throw failure("작업 시간 초과") }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        await pause()
    }
    private static func capture(_ name: String, to output: URL) throws {
        guard let window = NSApp.windows.first(where: { $0.title == "Spacekeeper" && $0.isVisible }),
              let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw failure("창 캡처 실패") }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw failure("PNG 생성 실패") }
        try png.write(to: output.appendingPathComponent(name + ".png"))
        if let sheet = window.attachedSheet, let sheetView = sheet.contentView,
           let sheetRep = sheetView.bitmapImageRepForCachingDisplay(in: sheetView.bounds) {
            sheetView.cacheDisplay(in: sheetView.bounds, to: sheetRep)
            try sheetRep.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(name + "-sheet.png"))
        }
    }
}
#endif
