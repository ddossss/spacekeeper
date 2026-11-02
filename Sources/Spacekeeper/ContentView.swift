import SwiftUI
import AppKit
import SpacekeeperCore

private let accent = Color(red: 0.03, green: 0.48, blue: 0.50)
private let surface = Color(nsColor: .controlBackgroundColor)
// Select the macOS 13-compatible wrapper, including SDKs that also expose a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.horizontal, 32).padding(.top, 34).padding(.bottom, 24)
                if model.busy {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(model.status.rendered).lineLimit(1)
                        Spacer()
                        Button(L("취소")) { model.cancel() }
                            .disabled(model.page == .schedule || model.page == .history)
                    }.padding(12).background(accent.opacity(0.08)).padding(.horizontal, 32).padding(.bottom, 12)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch model.page {
                        case .overview: overview
                        case .caches: caches
                        case .duplicates: duplicates
                        case .large: largeFiles
                        case .apps: apps
                        case .schedule: ScheduleView()
                        case .history: history
                        }
                    }.padding(.horizontal, 32).padding(.bottom, 28)
                }
                if [.caches, .duplicates, .large].contains(model.page) { selectionBar }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(accent)
        .sheet(isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } })) {
            ReviewSheet()
        }
        .alert("Spacekeeper", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button(L("확인")) { model.message = nil }
        } message: { Text(model.message?.rendered ?? "") }
        .alert(L("원래 위치로 복원할까요?"), isPresented: Binding(get: { model.restoreID != nil }, set: { if !$0 { model.restoreID = nil } })) {
            Button(L("취소"), role: .cancel) { model.restoreID = nil }
            Button(L("복원")) { if let id = model.restoreID { model.restoreID = nil; model.restore(id) } }
        } message: { Text(L("휴지통에 남아 있는 파일을 복원합니다. 같은 이름의 파일이 있으면 덮어쓰지 않습니다.")) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 25)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Spacekeeper").font(.system(size: 17, weight: .semibold))
                    Text(L("나의 Mac 정리 도구")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(.top, 46).padding(.bottom, 32).padding(.horizontal, 20)
            ForEach(Page.allCases) { page in
                if page == .schedule { Divider().padding(.horizontal, 20).padding(.vertical, 16) }
                Button { model.navigate(page) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: page.icon).font(.system(size: 16)).frame(width: 22)
                        Text(page.title).font(.system(size: 13, weight: model.page == page ? .semibold : .regular))
                        Spacer()
                        if page == .schedule && model.settings.scheduleEnabled && model.scheduleLoaded {
                            Circle().fill(accent).frame(width: 6, height: 6)
                        }
                    }.padding(.horizontal, 13).padding(.vertical, 11)
                        .foregroundStyle(model.page == page ? accent : Color.primary)
                        .background(model.page == page ? accent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(model.busy).padding(.horizontal, 12).padding(.bottom, 4)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Label(L("언어"), systemImage: "globe").font(.system(size: 12, weight: .medium))
                Picker(L("언어"), selection: Binding(get: { model.language }, set: { model.changeLanguage($0) })) {
                    ForEach(AppLanguage.allCases) { language in Text(language.name).tag(language) }
                }.labelsHidden().disabled(model.busy).accessibilityIdentifier("language-picker")
            }.padding(.horizontal, 20).padding(.top, 20)
            VStack(alignment: .leading, spacing: 8) {
                Label(L("내 Mac 안에서만"), systemImage: "lock.shield").font(.system(size: 12, weight: .medium))
                Text(L("파일을 외부 서버로 전송하지 않습니다.")).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }.padding(20)
        }.frame(width: 216).background(surface.opacity(0.65))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 9) {
                Text(model.page.title).font(.system(size: 28, weight: .semibold))
                Text(model.page.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            if [.caches, .duplicates, .large].contains(model.page) {
                Button { model.scan() } label: {
                    Label(model.scannedPage == model.page ? L("다시 검사") : L("검사 시작"), systemImage: "magnifyingglass")
                        .padding(.horizontal, 10).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).disabled(model.busy)
            } else if model.page == .overview {
                Button { model.refreshDisk(); model.reloadHistory() } label: { Image(systemName: "arrow.clockwise") }.help(L("새로 고침"))
            }
        }
    }

    private var overview: some View {
        Group {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L("Mac 저장 공간"), systemImage: "internaldrive").foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(formatBytes(model.available)).font(.system(size: 42, weight: .medium, design: .rounded)).monospacedDigit()
                            Text(L("사용 가능")).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "internaldrive.fill").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(accent.opacity(0.7))
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(accent.opacity(0.10))
                        Capsule().fill(accent).frame(width: proxy.size.width * CGFloat(model.capacity > 0 ? min(1, max(0, Double(model.capacity - model.available) / Double(model.capacity))) : 0))
                    }
                }.frame(height: 13).accessibilityLabel(L("전체 \(formatBytes(model.capacity)) 중 \(formatBytes(model.available)) 사용 가능"))
                HStack {
                    Label(L("사용 중 \(formatBytes(max(0, model.capacity - model.available)))"), systemImage: "circle.fill").foregroundStyle(accent)
                    Spacer()
                    Text(L("전체 \(formatBytes(model.capacity))")).foregroundStyle(.secondary)
                }.font(.system(size: 12)).monospacedDigit()
            }.padding(28).background(surface, in: RoundedRectangle(cornerRadius: 14))

            HStack(alignment: .top, spacing: 16) {
                feature(.caches, detail: L("오래된 캐시를 골라\n가볍게 정리하세요."))
                feature(.duplicates, detail: L("같은 내용의 파일,\n한 사본이면 충분해요."))
                feature(.large, detail: L("공간을 많이 쓰는 파일부터\n차근차근 살펴보세요."))
            }

            VStack(alignment: .leading, spacing: 14) {
                Text(L("자동으로, 조심스럽게")).font(.system(size: 18, weight: .semibold))
                HStack(spacing: 18) {
                    Image(systemName: "calendar.badge.clock").font(.system(size: 28)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.settings.scheduleEnabled && model.scheduleLoaded ? L("정기 캐시 청소가 켜져 있습니다") : L("정기 캐시 청소를 설정하세요")).fontWeight(.medium)
                        Text(L("최근 사용한 캐시와 실행 중인 앱은 보관합니다.")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("설정 열기")) { model.navigate(.schedule) }
                }
            }.padding(.vertical, 10)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("되돌릴 수 있는 정리")).fontWeight(.semibold)
                    Text(L("선택한 파일은 휴지통으로 이동합니다. 정리 기록에서 복원할 수 있어요.")).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("기록 보기")) { model.navigate(.history) }
            }
        }
    }

    private func feature(_ page: Page, detail: String) -> some View {
        Button { model.navigate(page) } label: {
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: page.icon).font(.system(size: 24)).foregroundStyle(accent)
                Text(page.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
                .background(surface, in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var caches: some View {
        Group {
            Notice(icon: "shield.lefthalf.filled", text: L("최근 \(model.settings.minimumDays)일 동안 수정하거나 사용한 캐시는 보관합니다. 브라우저 방문 기록·쿠키·비밀번호는 정리 대상에 포함하지 않습니다."))
            if model.scannedPage != .caches {
                emptyState(icon: "sparkles", title: L("오래된 캐시부터 확인해 볼까요?"), text: L("지원 앱: Chrome, Edge, Firefox, Brave, Spotify, VS Code\n실행 중인 앱은 종료한 뒤 검사해 주세요."))
            } else {
                HStack {
                    Text(L("정리 가능 \(formatBytes(model.cacheGroups.reduce(0) { $0 + $1.bytes }))")).font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Button(L("가능한 캐시 선택")) { model.selected = Set(model.cacheGroups.flatMap(\.files).map(\.id)) }
                }.disabled(model.busy)
                ForEach(model.cacheGroups) { group in
                    DisclosureGroup {
                        ForEach(Array(group.files.prefix(100))) { file in
                            FileRow(file: file, selected: selection(file.id), disabled: model.busy)
                        }
                        if group.files.count > 100 {
                            Text(L("미리보기에는 100개를 표시합니다. 그룹 선택은 전체 \(group.files.count)개에 적용됩니다.")).font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Toggle(L("\(group.rule.name) 선택"), isOn: Binding(
                                get: { !group.files.isEmpty && group.files.allSatisfy { model.selected.contains($0.id) } },
                                set: { value in
                                    if value { model.selected.formUnion(group.files.map(\.id)) }
                                    else { model.selected.subtract(group.files.map(\.id)) }
                                })).labelsHidden().disabled(group.files.isEmpty || model.busy)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.rule.name).fontWeight(.semibold)
                                Text(group.status.rendered).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatBytes(group.bytes)).monospacedDigit().foregroundStyle(.secondary)
                        }.padding(.vertical, 10)
                    }
                    Divider()
                }
                scanIssues
            }
        }
    }

    private var folderPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("검사할 폴더")).fontWeight(.semibold)
                Spacer()
                Button { model.selectFolder() } label: { Label(L("폴더 추가"), systemImage: "folder.badge.plus") }.disabled(model.busy)
            }
            if model.roots.isEmpty { Text(L("폴더를 선택하면 그 안의 파일만 검사합니다.")).foregroundStyle(.secondary).font(.caption) }
            ForEach(model.roots, id: \.path) { url in
                HStack {
                    Image(systemName: "folder").foregroundStyle(accent)
                    Text(url.path).font(.system(size: 12)).lineLimit(1).truncationMode(.middle).help(url.path)
                    Spacer()
                    Button { model.roots.removeAll { $0 == url }; model.invalidate() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(L("검사 폴더에서 제외")).disabled(model.busy)
                }
            }
        }.padding(16).background(surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private var duplicates: some View {
        Group {
            folderPicker
            if model.scannedPage != .duplicates {
                emptyState(icon: "doc.on.doc", title: L("이름이 달라도, 내용이 같다면"), text: L("파일 전체 내용을 비교해 정확한 중복만 찾습니다.\n앱 내부, 라이브러리, 클라우드 파일, 심볼릭 링크는 제외합니다."))
            } else {
                HStack {
                    Text(L("\(model.duplicateGroups.count)개 중복 그룹")).font(.system(size: 18, weight: .semibold))
                    Text(L("추가 사본 \(formatBytes(model.duplicateGroups.reduce(0) { $0 + $1.reclaimable }))")).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("추가 사본 선택")) {
                        model.selected = Set(model.duplicateGroups.flatMap { group in group.files.filter { $0.id != model.keepers[group.id] }.map(\.id) })
                    }.disabled(model.busy || model.duplicateGroups.isEmpty)
                }
                if model.duplicateGroups.isEmpty { emptyState(icon: "checkmark.circle", title: L("중복 파일이 없습니다"), text: L("검사할 수 있는 파일 중 내용이 같은 파일을 찾지 못했습니다.")) }
                else {
                    TextField(L("파일 이름 또는 경로 검색"), text: $model.search).textFieldStyle(.roundedBorder)
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(model.duplicateGroups.filter { model.search.isEmpty || $0.files.contains(where: { matches($0.url.path) }) }) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Text(L("\(group.files.count)개 사본")).fontWeight(.semibold)
                                    Spacer()
                                    Text(L("파일당 \(formatBytes(group.files.first?.bytes ?? 0))")).foregroundStyle(.secondary)
                                }.padding(.bottom, 8)
                                ForEach(group.files) { file in
                                    HStack(spacing: 8) {
                                        FileRow(file: file, selected: selection(file.id), disabled: model.busy || model.keepers[group.id] == file.id)
                                        if model.keepers[group.id] == file.id {
                                            Label(L("보관"), systemImage: "checkmark.shield.fill").font(.caption).foregroundStyle(accent).frame(width: 88)
                                        } else {
                                            Button(L("이 사본 보관")) { model.keepers[group.id] = file.id; model.selected.remove(file.id) }
                                                .font(.caption).frame(width: 88).disabled(model.busy)
                                        }
                                    }
                                    Divider()
                                }
                            }.padding(18).background(surface, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                scanIssues
            }
        }
    }

    private var largeFiles: some View {
        Group {
            folderPicker
            HStack {
                Text(L("최소 파일 크기"))
                Picker(L("최소 파일 크기"), selection: $model.largeThreshold) {
                    Text("10 MB").tag(10); Text("100 MB").tag(100); Text("500 MB").tag(500); Text("1 GB").tag(1024)
                }.labelsHidden().frame(width: 130).disabled(model.busy).onChange(of: model.largeThreshold) { _ in model.invalidate() }
                Spacer()
            }
            if model.scannedPage != .large {
                emptyState(icon: "externaldrive.badge.plus", title: L("큰 파일을 먼저 살펴보세요"), text: L("크기가 큰 순서대로 표시합니다.\n필요 없는 파일인지 확인한 뒤 직접 선택해 주세요."))
            } else {
                HStack {
                    Text(L("\(model.largeFiles.count)개 파일")).font(.system(size: 18, weight: .semibold))
                    Spacer()
                    TextField(L("파일 이름 또는 경로 검색"), text: $model.search).textFieldStyle(.roundedBorder).frame(width: 240)
                }
                if model.largeFiles.isEmpty { emptyState(icon: "checkmark.circle", title: L("조건에 맞는 큰 파일이 없습니다"), text: L("최소 크기를 낮추거나 다른 폴더를 검사해 보세요.")) }
                LazyVStack(spacing: 0) {
                    ForEach(model.largeFiles.filter { matches($0.url.path) }) { file in
                        FileRow(file: file, selected: selection(file.id), disabled: model.busy)
                        Divider()
                    }
                }
                scanIssues
            }
        }
    }

    private var apps: some View {
        Group {
            HStack(spacing: 14) {
                Notice(icon: "switch.2", text: L("시작 프로그램이 많다면 로그인 항목을 확인하세요. 변경은 macOS 설정에서 직접 할 수 있습니다."))
                Button(L("로그인 항목 열기")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                }
            }
            HStack {
                Text(L("\(model.apps.count)개 앱")).font(.system(size: 18, weight: .semibold))
                Spacer()
                Button(L("새로 고침")) { model.loadApps() }
                TextField(L("앱 검색"), text: $model.search).textFieldStyle(.roundedBorder).frame(width: 220)
            }
            Text(L("/Applications와 사용자 Applications 폴더의 앱을 표시합니다. 제거가 필요하면 Finder에서 앱을 확인한 뒤 휴지통으로 이동하세요."))
                .font(.caption).foregroundStyle(.secondary)
            LazyVStack(spacing: 0) {
                ForEach(model.apps.filter { matches($0.name) }) { app in
                    HStack(spacing: 14) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name).fontWeight(.medium)
                            Text(app.url.path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(app.version).font(.caption).foregroundStyle(.secondary)
                        Button(L("Finder에서 보기")) { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                    }.padding(.vertical, 12)
                    Divider()
                }
            }
        }
    }

    private var history: some View {
        Group {
            Notice(icon: "trash", text: L("휴지통으로 옮긴 파일은 아직 디스크 공간을 차지합니다. 정리를 확인한 뒤 Finder에서 휴지통을 비우세요. 비운 파일은 복원할 수 없습니다."))
            HStack {
                Text(L("\(model.history.count)번의 정리 기록")).font(.system(size: 18, weight: .semibold))
                Spacer()
                Button(L("휴지통 열기")) { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")) }
                Button(L("새로 고침")) { model.reloadHistory() }.disabled(model.busy)
            }
            if model.history.isEmpty { emptyState(icon: "clock.arrow.circlepath", title: L("아직 정리 기록이 없습니다"), text: L("파일을 정리하면 이동한 경로와 복원 상태가 여기에 표시됩니다.")) }
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(model.history) { record in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.text(record.kind)).fontWeight(.semibold)
                                Text(L10n.date(record.date)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(L("휴지통 이동 \(record.movedCount)개 · \(formatBytes(record.movedBytes))")).foregroundStyle(.secondary)
                            Button(L("복원")) { model.restoreID = record.id }.disabled(record.movedCount == 0 || model.busy)
                        }
                        if !record.note.isEmpty { Text(record.displayNote).font(.caption).foregroundStyle(.secondary) }
                        DisclosureGroup(L("파일 상세 \(record.items.count)개")) {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(record.items) { item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(item.source.lastPathComponent).lineLimit(1)
                                            Spacer()
                                            Text(item.restored ? L("복원됨") : item.trashURL != nil ? L("휴지통으로 이동") : item.pending == true ? L("처리 중단 · Finder에서 확인") : L("이동되지 않음"))
                                                .foregroundStyle(item.restored ? accent : Color.secondary)
                                        }
                                        Text(item.source.path).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                                        if let error = item.displayError { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                                    }
                                    Divider()
                                }
                            }.padding(.top, 12)
                        }
                    }.padding(20).background(surface, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var scanIssues: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let date = model.lastScan {
                Text(L("\(L10n.date(date, includeDate: false)) 검사 · \(model.status)")).font(.caption).foregroundStyle(.secondary)
            }
            if !model.issues.isEmpty {
                DisclosureGroup(L("확인할 항목 \(model.issues.count)개")) {
                    ForEach(Array(model.issues.enumerated()), id: \.offset) { _, text in
                        Text(text.rendered).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                    }
                }.foregroundStyle(.orange)
                Text(L("접근 권한이 없는 폴더는 건너뜁니다. 필요한 폴더를 직접 선택하거나 macOS 개인정보 보호 설정에서 접근을 허용한 뒤 다시 검사하세요."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L("\(model.selectedFiles.count)개 선택 · \(formatBytes(model.selectedBytes))")).fontWeight(.semibold).monospacedDigit()
                Text(L("선택한 파일은 검토 후 휴지통으로 이동합니다.")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !model.selected.isEmpty { Button(L("선택 해제")) { model.selected = [] }.disabled(model.busy) }
            Button(L("선택 항목 검토")) { model.review() }.buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.selectedFiles.isEmpty || model.busy)
        }.padding(.horizontal, 32).padding(.vertical, 18).background(surface)
    }

    private func selection(_ id: String) -> Binding<Bool> {
        Binding(get: { model.selected.contains(id) }, set: { if $0 { model.selected.insert(id) } else { model.selected.remove(id) } })
    }
    private func matches(_ text: String) -> Bool { model.search.isEmpty || text.localizedCaseInsensitiveContains(model.search) }
    private func emptyState(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 40, weight: .light)).foregroundStyle(accent.opacity(0.65))
            Text(title).font(.system(size: 19, weight: .semibold))
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(6)
        }.frame(maxWidth: .infinity).padding(.vertical, 58)
    }
}

struct Notice: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(accent)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(accent.opacity(0.065), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct FileRow: View {
    let file: FileEntry
    @Binding var selected: Bool
    var disabled = false
    var body: some View {
        HStack(spacing: 12) {
            Toggle(L("\(file.url.lastPathComponent) 선택"), isOn: $selected).labelsHidden().disabled(disabled)
            Image(systemName: "doc").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(file.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(file.url.deletingLastPathComponent().path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }.help(file.url.path)
            Spacer(minLength: 12)
            Text(formatBytes(file.bytes)).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
            Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help(L("Finder에서 보기"))
        }.padding(.vertical, 11)
    }
}

struct ReviewSheet: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L("휴지통으로 이동하기 전 확인"), systemImage: "trash").font(.system(size: 22, weight: .semibold))
            if let request = model.pending {
                Text(L("\(request.files.count)개 파일 · \(formatBytes(request.files.reduce(0) { $0 + $1.bytes }))")).font(.title3)
                Text(L("파일을 확인해 주세요. 정리 기록에서 복원할 수 있으며, 휴지통을 비우기 전까지는 디스크 공간을 차지합니다."))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(request.files) { file in
                            HStack(alignment: .top) {
                                Text(file.url.path).font(.system(size: 11)).textSelection(.enabled)
                                Spacer()
                                Text(formatBytes(file.bytes)).font(.caption).monospacedDigit()
                            }
                            Divider()
                        }
                    }
                }.frame(height: 260)
            }
            HStack {
                Spacer()
                Button(L("취소")) { model.pending = nil }.keyboardShortcut(.cancelAction)
                Button(L("휴지통으로 이동")) { model.clean() }.buttonStyle(.borderedProminent)
            }
        }.padding(28).frame(width: 660).background(Color(nsColor: .windowBackgroundColor)).tint(accent)
    }
}

struct ScheduleView: View {
    @EnvironmentObject var model: AppModel
    @ViewState private var draft = SpacekeeperCore.Settings()
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("정기 캐시 청소")).font(.system(size: 19, weight: .semibold))
                    Text(model.scheduleLoaded ? L("macOS 예약 작업이 등록되어 있습니다.") : L("아직 예약 작업이 등록되지 않았습니다.")).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(L("정기 청소 사용"), isOn: $draft.scheduleEnabled).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            HStack(spacing: 18) {
                Text(L("청소 주기")).frame(width: 100, alignment: .leading)
                Picker(L("주기"), selection: $draft.daily) { Text(L("매주")).tag(false); Text(L("매일")).tag(true) }.labelsHidden().frame(width: 110)
                if !draft.daily {
                    Picker(L("요일"), selection: $draft.weekday) {
                        ForEach(Array([L("일요일"), L("월요일"), L("화요일"), L("수요일"), L("목요일"), L("금요일"), L("토요일")].enumerated()), id: \.offset) { index, name in Text(name).tag(index) }
                    }.labelsHidden().frame(width: 110)
                }
                Spacer()
            }
            HStack(spacing: 18) {
                Text(L("실행 시간")).frame(width: 100, alignment: .leading)
                Picker(L("시"), selection: $draft.hour) { ForEach(0..<24) { Text(String(format: L("%02d시"), $0)).tag($0) } }.labelsHidden().frame(width: 90)
                Picker(L("분"), selection: $draft.minute) { ForEach(0..<60) { Text(String(format: L("%02d분"), $0)).tag($0) } }.labelsHidden().frame(width: 90)
                Text(L("Mac의 현지 시간 기준")).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 18) {
                Text(L("캐시 보관 기간")).frame(width: 100, alignment: .leading)
                Picker(L("보관 기간"), selection: $draft.minimumDays) {
                    Text(L("7일")).tag(7); Text(L("14일")).tag(14); Text(L("30일")).tag(30); Text(L("90일")).tag(90)
                }.labelsHidden().frame(width: 110)
                Text(L("마지막 사용·수정 이후 경과 일수")).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                Text(L("1회 정리 한도")).frame(width: 100, alignment: .leading)
                Picker(L("정리 한도"), selection: $draft.maxScheduledBytes) {
                    Text("500 MB").tag(Int64(500 * 1024 * 1024)); Text("2 GB").tag(Int64(2 * 1024 * 1024 * 1024)); Text("5 GB").tag(Int64(5 * 1024 * 1024 * 1024))
                }.labelsHidden().frame(width: 110)
                Text(L("초과 파일은 다음 예약에 다시 확인")).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text(L("청소할 앱 캐시")).font(.system(size: 16, weight: .semibold))
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 16) {
                ForEach(CacheRule.supported) { rule in
                    Toggle(rule.name, isOn: Binding(get: { draft.cacheIDs.contains(rule.id) }, set: {
                        if $0 { draft.cacheIDs.insert(rule.id) } else { draft.cacheIDs.remove(rule.id) }
                    }))
                }
            }
            Divider()
            HStack {
                Text(L("검사·정리에서 제외할 폴더")).font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(L("폴더 추가")) { addExclusion() }
            }
            if draft.excludedPaths.isEmpty { Text(L("제외할 개인 폴더를 추가할 수 있습니다.")).font(.caption).foregroundStyle(.secondary) }
            ForEach(draft.excludedPaths, id: \.self) { path in
                HStack {
                    Text(path).font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(L("제외 해제")) { draft.excludedPaths.removeAll { $0 == path } }.font(.caption)
                }
            }
            Notice(icon: "info.circle", text: L("앱을 종료해도 로그인한 동안 실행됩니다. 잠자기 중 놓친 예약은 깨어난 뒤 실행될 수 있습니다. 중복 파일과 개인 문서는 자동으로 정리하지 않습니다. 앱 위치를 옮겼다면 설정을 다시 저장하세요."))
            HStack {
                Text(L("변경 사항은 저장한 뒤 적용됩니다.")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("설정 저장")) { model.saveSettings(draft) }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(draft.scheduleEnabled && draft.cacheIDs.isEmpty)
            }
        }.padding(24).background(surface, in: RoundedRectangle(cornerRadius: 12)).disabled(model.busy)
            .onAppear { draft = model.settings }
    }
    private func addExclusion() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.prompt = L("검사에서 제외")
        if panel.runModal() == .OK {
            draft.excludedPaths = Array(Set(draft.excludedPaths + panel.urls.map(\.path))).sorted()
        }
    }
}
