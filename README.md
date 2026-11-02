# Spacekeeper

**[한국어](README.ko.md) · [日本語](README.ja.md) · English**

A native macOS and Windows app for reviewing disk clutter, finding exact duplicate files, and scheduling conservative cache cleanup. SwiftUI on macOS; WPF and .NET 10 on Windows. No account, server or analytics SDK.

## Windows download

Download **Spacekeeper-win-x64.zip** or **Spacekeeper-win-arm64.zip** from [Releases](https://github.com/ddossss/spacekeeper/releases), extract the entire ZIP, and run **Spacekeeper.exe**. Windows 10/11; .NET is included. Select 한국어, 日本語 or English in the sidebar.

Windows uses Task Scheduler, the Windows Recycle Bin, and `%LOCALAPPDATA%\Spacekeeper` for local state. Supports fixed local NTFS volumes. See the [Windows guide](windows/README.md) for building, scheduling, recovery and platform boundaries. ARM64 packages are cross-compiled; native ARM64 execution has not been tested. Packages are unsigned.

The instructions below describe the macOS version.

## Build and run

Requires macOS 13 or later and Swift 5.9 or later with Xcode Command Line Tools.

```sh
git clone https://github.com/ddossss/spacekeeper.git
cd spacekeeper
zsh scripts/build-app.sh
open codex-work/dist/Spacekeeper.app
```

The script builds for the current Mac's architecture and applies a local ad-hoc signature. Developer ID signing and notarization are not included.

## Choose your language

Use **Language** at the bottom of the sidebar to select **한국어**, **日本語**, or **English**. Changes apply immediately, preserve scan results and selections, and persist across launches. The first launch follows a supported system language, with English as the fallback.

Navigation, results, confirmations, app errors, history, and date/size formatting follow your selection. Native macOS panels, permission dialogs, and OS errors follow system settings. New history records retain message keys and arguments for later translation; legacy free-form error details remain as originally recorded.

## Features

| Feature | Behavior |
| --- | --- |
| Storage overview | Actual volume capacity, used space, and available space |
| Cache cleanup | Known cache paths for Chrome, Edge, Firefox, Brave, Spotify, and VS Code; skips running apps and recently accessed/modified files |
| Duplicate files | Size filtering followed by streaming SHA-256; choose a copy to keep; at least one copy must remain |
| Large files | Scan selected folders above 10 MB, 100 MB, 500 MB, or 1 GB |
| Installed apps | Names, versions, Finder links, and a shortcut to macOS Login Items |
| Scheduled cleanup | Daily/weekly local-time schedule, retention period, target apps, and per-run byte limit |
| Exclusions | Applied to both scanning and cleanup |
| History and restore | Review moved files and restore them without overwriting existing files |

Automatic cleanup is **off by default**. Enable it under **Scheduled cleanup** and save. A user LaunchAgent runs while you are logged in, even with the app closed. A missed run during sleep may execute after waking. Duplicate files and personal documents are never cleaned automatically.

## Cleanup and recovery

1. Scan caches or choose folders in Duplicate files / Large files.
2. Review files and choose what to remove. Duplicate groups always retain at least one copy.
3. Select **Review selection**, check the full paths, and select **Move to Trash**.
4. Check **Cleanup history**, where files still in Trash can be restored.

Moving files to Trash does **not** immediately reclaim disk space. Empty Trash in Finder after checking the result. Emptied files cannot be restored by this app. APFS clones, snapshots, and compression can make reclaimed space differ from logical file sizes.

The app does not permanently delete files, empty Trash automatically, request administrator privileges, remove browser passwords/cookies/history, or automatically uninstall apps.

## Safety boundaries

- System locations, user Library folders, app/document packages, hidden files, development dependencies, symbolic links, hard links, and iCloud items are excluded from personal-file scans.
- Fully downloaded files in other cloud-sync folders may look like regular files. Add those folders to exclusions if you do not want deletions to sync.
- Caches are kept for at least 7 days (14 by default), based on last access and modification. Running apps are identified through NSWorkspace bundle IDs; independent background processes without a bundle ID may not be detected.
- File identity, modification time, size, and link count are rechecked before moving. The selected duplicate and retained copy are both hashed again.
- Other processes are not locked out of the filesystem. A short race between validation and the macOS Trash API cannot be eliminated completely. Close apps editing the files being cleaned.
- A scan is limited to 200,000 directory entries and reports partial results. Hashing uses 1 MiB chunks.
- Restoration requires the Trash file and original parent folder to still exist. Existing files are never overwritten. External volumes must support Trash.

## Local data

The bundled build keeps generated files and app state inside the checkout:

```text
codex-work/
  dist/Spacekeeper.app
  state/
    preferences.json       # Selected language
    settings.json          # Cleanup configuration
    history/               # Records and in-progress append-only journals
    scheduler*.log
```

`codex-work/`, binaries, screenshots, and runtime state are ignored by Git. The build script records the checkout's state path only in the local app bundle, which is not committed.

Enabling a schedule creates `~/Library/LaunchAgents/local.spacekeeper.cache-cleanup.plist`. Save settings again after moving the app; rebuild after moving the checkout. Disable scheduled cleanup and save before deleting the app. Keep state if you need recovery records.

The unbundled `swift run` executable uses `~/Library/Application Support/Spacekeeper`. Use the bundle build above to keep state in the checkout.

## Development and tests

```sh
python3 scripts/check-localization.py
zsh scripts/test.sh
zsh scripts/build-app.sh
zsh scripts/ui-smoke.sh
```

The standalone runner works with Command Line Tools without XCTest. With full Xcode, the same tests can run using `swift test --scratch-path codex-work/build`.

Tests cover stale files, retained-copy protection, links, exclusions, cache rules, cancellation, locking, byte limits, journals, restore conflicts, language persistence, translated placeholders, and legacy-history decoding. The native Trash test moves and restores only a generated fixture. Other fixtures and the fake Trash live under `codex-work/test-fixtures/`.

The debug-only UI smoke harness drives app model actions and captures app-owned views in all three languages. It checks persistence, retained selection, duplicate review, native Trash, history, restoration, and large-file scans. This is not external mouse/keyboard automation. The harness is excluded from Release builds.

The optional launchd test registers an empty cache target, runs it, and unregisters it. It refuses to run if a Spacekeeper schedule already exists:

```sh
swift -I codex-work/test-build -L codex-work/test-build -lSpacekeeperCore \
  scripts/ScheduleIntegration.swift "$PWD"
```

Translations live in `Sources/SpacekeeperCore/Resources/translations.json`. Korean source strings are message keys; English/Japanese translations preserve numbered placeholders. Permission descriptions live in `Resources/*.lproj/InfoPlist.strings`.

See [feature research](docs/research.md), [design notes](docs/design.md), and [validation notes](docs/validation.md). Spacekeeper is independent and is not affiliated with CCleaner.
