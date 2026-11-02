#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
swift build --scratch-path codex-work/build
BIN_DIR="$(swift build --scratch-path codex-work/build --show-bin-path)"
SMOKE_DIR="$PROJECT_DIR/codex-work/2026-11-02-validation"
APP_DIR="$SMOKE_DIR/Spacekeeper-UI.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Spacekeeper" "$APP_DIR/Contents/MacOS/Spacekeeper"
ditto "$BIN_DIR/Spacekeeper_SpacekeeperCore.bundle" "$APP_DIR/Contents/Resources/Spacekeeper_SpacekeeperCore.bundle"
ditto "$PROJECT_DIR/Resources" "$APP_DIR/Contents/Resources"
python3 - "$PROJECT_DIR" "$APP_DIR" "$SMOKE_DIR" <<'PY'
import plistlib, pathlib, sys
project, app, smoke = map(pathlib.Path, sys.argv[1:])
info = plistlib.loads((project / 'codex-work/dist/Spacekeeper.app/Contents/Info.plist').read_bytes())
info['CFBundleIdentifier'] = 'local.spacekeeper.ui-validation'
info['SpacekeeperStatePath'] = str(smoke / 'ui-state')
info.pop('CFBundleIconFile', None)
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
codesign --force --deep --sign - "$APP_DIR"
RESULT_FILE="$SMOKE_DIR/ui-captures/result.txt"
if [[ -f "$RESULT_FILE" ]]; then rm "$RESULT_FILE"; fi
"$APP_DIR/Contents/MacOS/Spacekeeper" --ui-smoke
python3 - "$RESULT_FILE" <<'PY'
import pathlib, sys
result = pathlib.Path(sys.argv[1]).read_text()
print(result, end='')
if not result.startswith('PASS:'):
    raise SystemExit(1)
PY
