# 검증 기록

2026-11-02, Apple Silicon macOS 27.2 / Apple Swift 6.4.2 Command Line Tools에서 검증했습니다. 지원 대상은 macOS 13 이상이지만 다른 macOS 버전이나 Intel Mac에서 직접 실행 검증하지는 않았습니다.

## 결과

- 안전성·동작·다국어 테스트 27개 통과: `zsh scripts/test.sh`
- 앱 문구 205개의 영어·일본어 번역과 치환값 검사 통과: `python3 scripts/check-localization.py`
- 한국어·日本語·English 즉시 전환, 검사 결과·선택 유지, 설정 저장·다음 실행의 언어 복원, 기존 기록 호환성을 확인했습니다.
- Release `.app` 빌드 및 ad-hoc 서명 검증 통과: `zsh scripts/build-app.sh`
- 실제 macOS `FileManager.trashItem`로 프로젝트의 테스트 파일을 휴지통으로 이동하고 원래 위치로 복원했습니다.
- launchd bootstrap → kickstart → GUI 없이 빈 대상의 예약 기록 생성 → bootout → plist 제거를 확인했습니다. 실제 사용자 캐시는 선택하지 않았습니다.
- 개발용 실제 앱에서 중복 검사 → 파일 선택 → 검토창 → 휴지통 이동 → 정리 기록 → 복원 → 대용량 검사 흐름을 실행했습니다. 이 테스트는 앱 내부 모델 동작을 구동하며, 외부 마우스·키보드 자동화 테스트는 아닙니다.
- 개요, 중복 파일, 검토창, 정리 기록, 대용량 파일, 캐시 빈 화면, 정기 청소, 설치 앱 화면을 앱 내부 캡처로 확인했습니다. 외부 화면 자동화 도구는 이 세션에서 시간 초과가 발생했습니다.
- 전체 Xcode/XCTest가 설치되지 않아 `swift test`는 사용할 수 없었습니다. 동일 테스트 메서드를 실행하는 독립 Swift assertion 실행기로 검증했습니다.

## 재현과 산출물

```sh
python3 scripts/check-localization.py
zsh scripts/test.sh
zsh scripts/build-app.sh
zsh scripts/ui-smoke.sh
swift -I codex-work/test-build -L codex-work/test-build -lSpacekeeperCore \
  scripts/ScheduleIntegration.swift "$PWD"
```

예약 통합 테스트는 기존 Spacekeeper 예약이 있으면 실행하지 않습니다. 빈 캐시 대상의 임시 등록만 사용하고 테스트가 끝나면 해제합니다.

초기 검증 로그와 앱 내부 화면 캡처는 `codex-work/2026-11-02-validation/`, 다국어 작업의 빌드·테스트 로그는 `codex-work/2026-11-02-localization/`에 있습니다. 이 폴더들은 로컬 검증 산출물이므로 공개 저장소에는 포함하지 않습니다. 실제 앱 상태와 테스트 상태는 별도 폴더에 저장됩니다. 개발용 UI 캡처 기능은 Release 빌드에 포함되지 않습니다.

최종 앱의 자동 청소는 기본값인 꺼짐 상태입니다. 테스트 중 실제 개인 문서 또는 사용자 캐시를 정리하지 않았습니다.

## Windows 추가 검증

2026-11-02, .NET 10 SDK와 GitHub의 `windows-2025-vs2026` x64 실행 환경에서 검증했습니다. [최종 Windows CI 실행](https://github.com/ddossss/spacekeeper/actions/runs/41378874576)의 소스는 `7092a2e3cb5d639d880d9ea268361de93fbc4cee`입니다.

- 핵심 동작·안전성 테스트 26개: 내용 비교, 보관 사본 보호, 수정된 파일 거부, 심볼릭 링크·NTFS 하드 링크 제외, 제외 경로, 설정 오류, 실행 잠금, 캐시 보관 기간·실행 앱·용량 한도, 취소, 기록, 복원 충돌 및 불확실한 이동 결과 보존.
- 실제 Windows Recycle Bin에 생성한 테스트 파일을 이동하고 원래 위치로 복원했습니다.
- 실제 WPF 앱의 내부 모델로 중복 검사 → 선택 → 3개 언어 전환 → 휴지통 이동 → 기록 → 복원을 구동했습니다. 3개 언어 × 5개 화면을 캡처하고, 선택 유지 및 언어 저장을 확인했습니다. 외부 마우스·키보드 자동화 검증은 아닙니다.
- Task Scheduler에 빈 캐시 대상의 작업을 등록하고 실행하여 정기 청소 기록을 확인한 뒤 작업을 제거했습니다. 실제 사용자 캐시는 정리하지 않았습니다.
- 공통·Windows 전용 문구 229개의 영어·일본어 치환값 및 Windows 소스 문구 누락 검사를 통과했습니다.
- x64·ARM64 런타임 포함 ZIP을 생성하고 체크섬·ZIP 무결성·PE 아키텍처를 확인했습니다.
- Mac에서 실행 가능한 C# 핵심 테스트 24개 및 기존 Swift 테스트 27개가 통과했습니다.

Windows 10/11 데스크톱 기기와 ARM64 기기에서 직접 실행 검증하지는 않았습니다. ARM64는 교차 빌드 검증만 완료했습니다. 배포 파일은 코드 서명되지 않았습니다. Windows의 파일 검증과 Shell 이동 사이에도 다른 프로세스가 파일을 변경할 수 있는 짧은 간격이 있습니다.

재현 명령은 [Windows 안내](../windows/README.md)에 있습니다. 빌드·테스트 결과와 캡처는 로컬 `codex-work/2026-11-02-windows/` 및 CI 아티팩트에 보관했습니다. Windows 자동 청소도 처음에는 꺼져 있습니다.
