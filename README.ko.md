# Spacekeeper

**한국어 · [日本語](README.ja.md) · [English](README.md)**

한국어·日本語·English를 지원하는 macOS·Windows 데스크톱 정리 앱입니다. macOS는 SwiftUI, Windows는 WPF·.NET 10으로 구현했습니다. 서버, 계정, 분석 SDK가 없습니다.

## Windows 실행

[Releases](https://github.com/ddossss/spacekeeper/releases)에서 **Spacekeeper-win-x64.zip** 또는 **Spacekeeper-win-arm64.zip**을 받고, ZIP 전체를 폴더에 푼 뒤 **Spacekeeper.exe**를 실행하세요. 일반적인 Intel·AMD PC는 x64, ARM 기반 PC는 arm64를 선택합니다. Windows 10/11용이며 .NET 런타임이 포함되어 있습니다.

사이드바에서 한국어·日本語·English를 바꿀 수 있습니다. Windows 작업 스케줄러로 예약 청소하고, 삭제할 파일은 Windows 휴지통으로 이동합니다. 설정과 복원 기록은 `%LOCALAPPDATA%\Spacekeeper`에 저장합니다. 로컬 고정 NTFS 드라이브를 지원합니다. ARM64 패키지는 교차 빌드했으며 실제 ARM64 기기 실행은 미검증입니다. 배포 파일은 코드 서명되지 않았습니다.

빌드·예약·복원에 관한 내용은 [Windows 안내](windows/README.md)를 참고하세요. 아래 내용은 macOS 버전 기준입니다.

## 실행

```sh
git clone https://github.com/ddossss/spacekeeper.git
cd spacekeeper
zsh scripts/build-app.sh
open codex-work/dist/Spacekeeper.app
```

빌드에는 Swift 5.9 이상의 Xcode Command Line Tools가 필요합니다. 로컬 앱은 ad-hoc 서명됩니다. 배포용 Developer ID 서명·공증은 포함하지 않습니다. 빌드한 Mac의 아키텍처용 앱입니다.

## 언어 선택

사이드바 아래의 **언어** 메뉴에서 한국어·日本語·English를 선택하세요. 즉시 적용되며 재실행 후에도 유지됩니다. 검사 결과와 파일 선택은 유지됩니다. 언어는 `codex-work/state/preferences.json`에 별도로 저장되므로 정기 청소 설정에 영향을 주지 않습니다. macOS가 제공하는 파일 선택창·권한 창 등은 시스템 언어 설정을 따릅니다.

## 제공 기능

- **개요:** 실제 볼륨 사용량과 남은 공간.
- **캐시 정리:** Chrome, Edge, Firefox, Brave, Spotify, VS Code의 알려진 사용자 캐시 경로. 최소 7일, 기본 14일 동안 사용·수정하지 않은 일반 파일만 표시. 실행 중인 앱 및 해당 bundle ID의 helper 프로세스 제외.
- **중복 파일:** 선택한 폴더에서 크기 → 스트리밍 SHA-256으로 정확히 같은 내용을 찾음. 이름이 같아도 내용이 다르면 중복으로 표시하지 않음. 보관 사본 선택, 추가 사본 선택, 경로 검색, Finder에서 보기.
- **대용량 파일:** 10 MB / 100 MB / 500 MB / 1 GB 이상 파일을 크기 순서로 검토하고 선택.
- **설치 앱:** `/Applications`, `~/Applications` 최상위 앱 이름·버전·위치 확인, Finder에서 관리. macOS 로그인 항목 설정 연결.
- **정기 청소:** 매일 또는 매주, 현지 시간 지정, 보관 기간, 대상 앱, 1회 최대 용량. 사용자 LaunchAgent가 앱 종료 중에도 실행. 잠자기 중 누락된 작업은 깨어난 뒤 실행될 수 있음. 로그아웃·전원 종료 중 실행하지 않음.
- **제외 폴더:** 검사 및 휴지통 이동 시 적용.
- **정리 기록과 복원:** 이동 전에 기록을 쓰고 각 파일 처리 후 갱신. 휴지통의 파일을 원래 경로로 복원하며 기존 파일을 덮어쓰지 않음.

## 사용 순서

1. 앱을 열어 캐시 검사를 실행하거나, 중복·대용량 파일 탭에서 검사할 폴더를 추가합니다.
2. 결과에서 파일을 직접 선택합니다. 중복 그룹은 기본적으로 경로 순 첫 사본을 보관하지만 다른 사본으로 바꿀 수 있습니다.
3. **선택 항목 검토**에서 전체 경로를 확인하고 **휴지통으로 이동**을 누릅니다.
4. **정리 기록**에서 결과·제외 이유를 확인하거나 복원합니다.
5. 자동화를 원하면 **정기 청소**에서 토글과 일정을 설정하고 **설정 저장**을 누릅니다. 기본값은 꺼짐이며 개발·검증 과정에서 실제 캐시 자동 청소를 켜지 않습니다.

휴지통으로 이동한 용량은 실제 확보 용량이 아닙니다. 확인 후 Finder에서 휴지통을 비워야 공간이 확보됩니다. 휴지통을 비우면 앱에서 복원할 수 없습니다. APFS 복제·스냅샷·압축 때문에 표시한 파일 크기와 실제 확보 공간은 다를 수 있습니다.

## 데이터와 예약 위치

- 이 프로젝트의 빌드 스크립트는 앱 설정·기록을 **프로젝트 안** `codex-work/state/`에 저장하도록 번들에 경로를 기록합니다.
- 빌드 결과: `codex-work/dist/Spacekeeper.app`
- 설정: `codex-work/state/settings.json`
- 기록: `codex-work/state/history/*.json` (처리 중 파일별 이벤트는 `.jsonl`에 추가하고 완료 시 합칩니다.)
- 예약 로그: `codex-work/state/scheduler*.log`
- 정기 청소를 켰을 때만 OS 등록 파일 `~/Library/LaunchAgents/local.spacekeeper.cache-cleanup.plist`를 생성합니다.
- 앱을 옮겼다면 새 위치에서 설정을 다시 저장해 실행 경로를 갱신하세요. 프로젝트 자체를 옮겼다면 재빌드하세요.
- 개발 중 `swift run`으로 실행하면 기본 상태 경로는 `~/Library/Application Support/Spacekeeper`입니다. 프로젝트 경로 정책을 유지하려면 위의 번들 빌드를 사용하세요.
- 제거할 때는 먼저 정기 청소를 끄고 저장한 다음 앱을 삭제하세요. 복원 기록이 필요하다면 `codex-work/state`를 보관하세요.

## 보호 범위와 한계

- 시스템 경로, 사용자 Library, 앱·문서 패키지, 숨김 파일, `.git`, `node_modules`, 가상환경, 심볼릭 링크, 하드 링크, iCloud 항목을 검사에서 제외합니다. Dropbox/OneDrive 등의 완전히 내려받은 파일은 일반 파일로 보일 수 있으므로 해당 폴더는 제외 목록에 추가하세요. 삭제가 동기화될 수 있습니다.
- 파일 수정·inode·장치·크기·링크 수를 이동 직전에 재확인합니다. 중복 파일은 삭제 대상과 남길 사본을 다시 해시 검증합니다. 선택한 그룹 전체를 삭제할 수 없습니다.
- 파일을 바꾸는 다른 프로세스를 강제 종료하거나 OS 전체 파일 잠금을 걸지는 않습니다. 검사와 휴지통 API 사이의 아주 짧은 동시 변경 경쟁을 완전히 제거하지는 못합니다. 정리 대상 파일을 편집하는 앱은 닫고 사용하세요.
- 캐시의 실행 중 앱 판별은 NSWorkspace bundle ID에 기반합니다. bundle ID가 없는 독립 백그라운드 프로세스까지 완전히 검출하는 것은 아닙니다.
- 휴지통 이동은 FileManager의 macOS API만 사용하고, 영구 삭제·휴지통 자동 비우기·관리자 권한 상승을 하지 않습니다.
- 볼륨에 휴지통이 없거나 접근 권한이 없는 항목은 실패로 기록합니다. 외장 볼륨의 휴지통 파일이 없으면 복원할 수 없습니다. 원래 부모 폴더가 없어지면 먼저 Finder에서 복구해야 합니다.
- 파일 수는 검사당 최대 20만 디렉터리 항목으로 제한하며 부분 결과임을 표시합니다. SHA-256은 1 MiB 청크 단위로 읽어 큰 파일 전체를 메모리에 올리지 않습니다.
- 캐시는 디렉터리 전체가 아닌 오래된 일반 파일 단위로 정리합니다. 빈 디렉터리는 남을 수 있습니다. 사용자 문서와 중복 파일은 자동 청소하지 않습니다.
- 앱 일괄 제거, 사진 유사도 판정, 브라우저 방문 기록/쿠키/비밀번호 삭제, 메모리 강제 해제는 구현하지 않았습니다.

## 검증

```sh
zsh scripts/test.sh
```

Command Line Tools만 설치된 환경에서도 실행할 수 있는 테스트 실행기입니다. 전체 Xcode에 XCTest가 설치되어 있으면 같은 테스트를 `swift test --scratch-path codex-work/build`로 실행할 수 있습니다.

추가 검증: `zsh scripts/ui-smoke.sh`는 개발용 앱에서 테스트 파일의 중복 검사·검토·휴지통 이동·복원과 각 화면을 검증하고 `codex-work/2026-11-02-validation/ui-captures/`에 앱 내부 화면 캡처를 저장합니다. `scripts/ScheduleIntegration.swift`는 기존 예약이 없을 때 빈 캐시 대상의 임시 예약을 등록·실행·해제하는 통합 테스트입니다.

테스트 파일과 가짜 휴지통은 모두 `codex-work/test-fixtures/` 안에서 생성·제거됩니다. 실제 캐시나 개인 문서를 삭제하지 않습니다. 내용 비교, 오래된 캐시 선별, 실행 중 앱 차단, 모든 사본 삭제 금지, 검사 후 변경, 심볼릭 링크·하드 링크, 겹치는 폴더, 제외 폴더, 복원 충돌, 취소, 잠금, 예약 설정 및 용량 한도를 검증합니다.

설계와 조사: [디자인](docs/design.md), [CCleaner 기능 조사](docs/research.md).
