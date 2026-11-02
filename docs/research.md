# CCleaner 기능 조사와 적용

조사일: 2026-11-02. 독립적인 로컬 앱이며 CCleaner와 제휴하지 않습니다.

공식 출처:

- [CCleaner for Mac](https://www.ccleaner.com/ccleaner-mac)
- [What is the new CCleaner for Mac?](https://support.ccleaner.com/articles/en_US/Master_Article/what-is-the-new-ccleaner-for-mac)
- [Apple: Scheduling Timed Jobs](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/ScheduledJobs.html)
- [Apple: FileManager trashItem](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:))

| 공식 자료의 기능 | Spacekeeper 적용 |
|---|---|
| 불필요한 캐시·잡동사니 정리 | 알려진 사용자 앱 캐시만, 보관 기간·실행 중 앱 보호·미리보기 |
| 중복 파일 찾기 | 파일 전체 SHA-256, 최소 한 사본 보관, 삭제 직전 재검증 |
| 큰 파일 찾기 | 선택한 폴더를 크기 기준으로 검사·검토 |
| 앱 제거 | 설치 앱 목록·버전·Finder 연결. 앱 자체 및 잔여 설정의 자동 제거는 제외 |
| 시작 프로그램 관리 | macOS 로그인 항목 설정으로 연결하여 사용자가 변경 |
| 자동 브라우저 정리 | 브라우저 캐시만 일정에 따라 정리. 쿠키·방문 기록·비밀번호는 보존 |
| 휴지통 자동 비우기 | 복구 가능성을 유지하기 위해 제외 |
| 나쁜 사진·유사 사진 분석 | 잘못된 삭제를 피하려고 제외. 바이트가 같은 사진만 일반 중복 탐색에 포함 |

추가 기능: 볼륨 저장 공간 현황, 제외 폴더, 파일별 정리 이력, 원래 위치로 복원, 자동 청소 용량 제한.

macOS launchd의 StartCalendarInterval을 사용한다. ProgramArguments 배열로 경로를 전달하며 셸에 사용자 경로를 삽입하지 않는다. 앱이 꺼져도 로그인 세션에서 작동하고, 자동 실행은 명시적인 토글 저장 후 시작한다.
