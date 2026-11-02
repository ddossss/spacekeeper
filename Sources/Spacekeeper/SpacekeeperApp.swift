import SwiftUI
import AppKit
import SpacekeeperCore

@main struct EntryPoint {
    static func main() {
        if CommandLine.arguments.contains("--scheduled") {
            let args = CommandLine.arguments
            let state = args.firstIndex(of: "--state").flatMap { $0 + 1 < args.count ? URL(fileURLWithPath: args[$0 + 1]) : nil }
            do { try Scheduler.run(store: Store(root: state ?? Store.defaultRoot)) }
            catch { fputs("Spacekeeper: \(error.localizedDescription)\n", stderr); exit(1) }
        } else { SpacekeeperApp.main() }
    }
}

struct SpacekeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel(store: Store(root: Store.defaultRoot))
    var body: some Scene {
        WindowGroup("Spacekeeper") {
            ContentView().environmentObject(model).frame(minWidth: 1020, minHeight: 700)
                .environment(\.locale, model.language.locale)
                .onAppear {
                    #if DEBUG
                    if CommandLine.arguments.contains("--ui-smoke") {
                        Task { await UIValidation.run(model: model) }
                    }
                    #endif
                }
        }
        .defaultSize(width: 1180, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(L("정기 청소 설정…")) { model.navigate(.schedule) }.keyboardShortcut(",")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
