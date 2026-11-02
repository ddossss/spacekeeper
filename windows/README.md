# Spacekeeper for Windows

**한국어 · 日本語 · English** — choose a language in the sidebar.

## Run / 실행 / 起動

Extract the whole ZIP to a permanent folder and open **Spacekeeper.exe**. Keep all extracted files together. Windows 10/11 on x64 or ARM64; choose the matching download. The .NET runtime is included. No administrator rights are requested. The package is currently unsigned.

ZIP 전체를 고정된 폴더에 풀고 **Spacekeeper.exe**를 실행하세요. 사이드바에서 한국어를 선택할 수 있습니다. 런타임은 포함되어 있습니다.

ZIP 全体を任意の固定フォルダーに展開して **Spacekeeper.exe** を起動してください。サイドバーで日本語を選択できます。ランタイムは同梱しています。

## Features

- Storage overview; known caches for Chrome, Edge, Brave, Firefox, VS Code and Spotify.
- Exact duplicates using size and SHA-256. Choose a retained copy; review selected paths before recycling.
- Large-file browser, exclusions, installed-app list and Windows Settings shortcuts.
- Daily/weekly cache cleanup through Task Scheduler while signed in, including when the app is closed. Disabled initially; save settings to enable it.
- Recycle Bin history and restoration without overwriting existing files.

Cache files must be at least 7 days old (14 by default), based on access and modification time. Running app processes are skipped. Automatic cleanup only covers the selected cache allowlist and has a per-run byte cap. Cookies, passwords, browsing history and personal documents are not automatic targets.

Only fixed local NTFS volumes are supported. System locations, hidden files, reparse points/junctions/symlinks, hard links, cloud placeholders and development dependencies are excluded. Fully downloaded cloud files may appear ordinary; exclude sync folders to avoid synchronized deletion. File identity and duplicate contents are checked again before cleanup. Other apps can still change files between validation and the Shell operation; close apps editing selected files.

Files are sent to the Windows Recycle Bin, with no permanent-delete fallback. They still occupy disk space until you empty the Recycle Bin yourself. Restore requires the recycled file and original parent folder to exist. Reclaimed physical space may differ from displayed logical sizes.

Settings and history stay in `%LOCALAPPDATA%\Spacekeeper`. No files or telemetry are uploaded. Native dialogs and Windows error details follow the system language.

After moving the app, save schedule settings again. Before removing the app, disable scheduled cleanup and save. Keep the state folder if you want to retain restoration records.

## Build

Install the .NET 10 SDK on Windows, then run from the checkout:

```powershell
./scripts/build-windows.ps1
./scripts/build-windows.ps1 -Runtime win-arm64
./scripts/test-windows.ps1 -Executable codex-work/dist/Spacekeeper-win-x64/Spacekeeper.exe
```

Build outputs, fixtures and screenshots are under `codex-work/`. Tests generate their own files. The schedule test refuses to replace an existing Spacekeeper task. x64 is exercised on GitHub's Windows runner; ARM64 is cross-compiled and requires native-device validation.

Windows uses WPF and .NET 10; macOS uses SwiftUI. Both share the main translation catalog. Windows-specific strings are in `windows/Spacekeeper.Core/translations.json`.

Independent project; not affiliated with CCleaner. Source: https://github.com/ddossss/spacekeeper
