#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
BUILD_DIR="$PROJECT_DIR/codex-work/build"
APP_DIR="$PROJECT_DIR/codex-work/dist/Spacekeeper.app"
STATE_DIR="$PROJECT_DIR/codex-work/state"
swift build -c release --scratch-path "$BUILD_DIR"
BIN_DIR="$(swift build -c release --scratch-path "$BUILD_DIR" --show-bin-path)"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Spacekeeper" "$APP_DIR/Contents/MacOS/Spacekeeper"
ditto "$BIN_DIR/Spacekeeper_SpacekeeperCore.bundle" "$APP_DIR/Contents/Resources/Spacekeeper_SpacekeeperCore.bundle"
ditto "$PROJECT_DIR/Resources" "$APP_DIR/Contents/Resources"
python3 - "$APP_DIR" "$STATE_DIR" <<'PY'
import plistlib, pathlib, sys
app, state = pathlib.Path(sys.argv[1]), sys.argv[2]
info = {
    'CFBundleName': 'Spacekeeper', 'CFBundleDisplayName': 'Spacekeeper',
    'CFBundleIdentifier': 'local.spacekeeper.app', 'CFBundleExecutable': 'Spacekeeper',
    'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '1.1.0',
    'CFBundleVersion': '2', 'LSMinimumSystemVersion': '13.0',
    'NSHighResolutionCapable': True, 'NSPrincipalClass': 'NSApplication',
    'CFBundleDevelopmentRegion': 'en', 'CFBundleLocalizations': ['ko', 'ja', 'en'],
    'NSHumanReadableCopyright': 'Spacekeeper — local-first Mac maintenance',
    'NSDocumentsFolderUsageDescription': '선택한 문서 폴더에서 중복 파일과 대용량 파일을 찾습니다.',
    'NSDownloadsFolderUsageDescription': '선택한 다운로드 폴더에서 중복 파일과 대용량 파일을 찾습니다.',
    'NSDesktopFolderUsageDescription': '선택한 데스크탑 폴더에서 중복 파일과 대용량 파일을 찾습니다.',
    'SpacekeeperStatePath': state,
    'CFBundleIconFile': 'AppIcon',
}
with (app / 'Contents/Info.plist').open('wb') as f: plistlib.dump(info, f)
PY
swift scripts/make-icon.swift "$PROJECT_DIR/codex-work/icon.iconset"
iconutil -c icns "$PROJECT_DIR/codex-work/icon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
printf 'Built: %s\n' "$APP_DIR"
