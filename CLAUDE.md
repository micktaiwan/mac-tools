# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

macOS menu bar app (13+) built with Swift/SwiftUI. Displays calendar events and Gmail unread count in the menu bar, runs Mickael's global keyboard shortcuts, and exposes an Options window. No Dock icon (LSUIElement).

## Build

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`.

```bash
xcodegen generate
xcodebuild -scheme MacTools -configuration Debug build
```

Install to /Applications:
```bash
rm -rf /Applications/MacTools.app
cp -R ~/Library/Developer/Xcode/DerivedData/MacTools-*/Build/Products/Debug/MacTools.app /Applications/
```

`rm -rf` first: `cp -R` alone merges into the existing bundle and leaves stale files behind.

## After every code change — do this without asking

Run the full loop automatically: `xcodegen generate`, build, install to /Applications,
then kill the running instance and relaunch it. Standing instruction from Mickael, it
overrides the global "never launch or kill a process without confirmation" rule for
this app only.

```bash
pkill -f "^/Applications/MacTools.app/Contents/MacOS/MacTools$"
open -a /Applications/MacTools.app
```

## Architecture

Single-target SwiftUI app with `@NSApplicationDelegateAdaptor` for menu bar integration via `NSStatusItem` + `NSPopover`.

### Entry point
- `MacToolsApp.swift` — App entry, `AppDelegate` manages the status item, popover, and coordinates services. `MenuContentView` composes the popover UI from feature views.

### Features (under `MacTools/Features/`)

**Calendar** (`Calendar/`)
- `CalendarService` — `ObservableObject` wrapping EventKit. Fetches today's upcoming timed events, falls back to tomorrow if none remain. Supports calendar filtering via `excludedCalendarIDs` persisted in UserDefaults.
- `CalendarMenuView` — Event list, plus the popover footer (`SettingsSection`, quit only). Handles authorization states. Calendar picking moved to the Options window.
- `CalendarMenuBarLabel` — Formats the next event for the menu bar title (relative time if <60min, absolute time otherwise).

**Gmail** (`Gmail/`)
- `GmailService` — Shells out to `gws` CLI (Google Workspace CLI) to fetch unread inbox messages. Looks for `gws` in `/usr/local/bin`, `/opt/homebrew/bin`, or nvm node versions. Polls every 2 minutes.
- `GmailMenuView` — Displays unread emails with trash action (moves to trash via `gws`).

**Shortcuts** (`Shortcuts/`) — see the dedicated section below.

**Options** (`Options/`)
- `OptionsWindowController` — Owns the single Options window. Activates the app (`NSApp.activate`) because LSUIElement apps open windows behind everything otherwise.
- `OptionsWindowView` — `NavigationSplitView` with the vertical tab list, plus the shared `OptionsPage` container. Tabs: General, Calendar and mail, Shortcuts.

### Key patterns
- Services are `@MainActor` `ObservableObject` classes with `@Published` properties
- `AppDelegate` subscribes to service publishers via Combine to update the menu bar title
- Menu bar updates every 30s (timer) for relative time freshness
- Calendar refreshes every 60s + on `EKEventStoreChanged` notifications
- UI text is in French

## Keyboard shortcuts — how to add one for Mickael

The whole point: Mickael says "I want ⌘⇧K to run <command>" in a conversation, and Claude
adds it over IPC. He never edits anything by hand.

```bash
S="$HOME/Library/Application Support/MacTools/ipc.sock"
echo '{"command":"add","shortcut":{"id":"focus-slack","name":"Slack au premier plan","key":"s","modifiers":["command","shift"],"action":{"type":"shell","command":"open -a Slack"},"enabled":true}}' | nc -U "$S"
echo '{"command":"list"}' | nc -U "$S"
```

Commands: `list`, `add` (needs `shortcut`), `remove` (needs `id`), `enable` (`id` + `enabled`),
`run` (`id`, fires the action now), `reload`. One JSON request per connection, one JSON
response, connection closed.

A successful `add` still returns `"ok": false` with an `error` when Carbon refuses the combo
because another app already owns it. Read the response, do not assume it worked.

`list` returns `lastExitCode`, `lastOutput` and `lastRun` per shortcut — that is how a failing
script gets diagnosed instead of being a key press that does nothing.

Storage is `~/Library/Application Support/MacTools/shortcuts.json`. The app watches the
directory, so editing that file by hand re-registers the hotkeys within a second; the socket
is a convenience, not the only way in.

### Implementation (`MacTools/Features/Shortcuts/`)

- `UserShortcut` — Codable model. `key` is a single character ("l") or a named key ("f5", "space").
- `KeyCodeResolver` — Resolves `key` against the *current keyboard layout* via `UCKeyTranslate`,
  so "a" means the key that types an A on Mickael's French layout, not ANSI position A.
- `HotKeyCenter` — Carbon `RegisterEventHotKey`. Chosen over `CGEventTap` because it needs no
  Accessibility permission: the app only ever sees the combos it declared. The trade-off is no
  double-tap, no key sequences, no gestures. Changing that means an Accessibility prompt.
- `ActionRunner` — Runs the command through `/bin/zsh -lc` (login shell, so `~/.local/bin` is in
  PATH), captures stdout and stderr together with the exit code.
- `ShortcutStore` — Source of truth: loads/saves the JSON, watches the directory, re-registers.
- `ShortcutsIPCServer` — Unix socket server.
- `ShortcutsService` — Unrelated to the above: read-only inventory of shortcuts *already taken*
  on the Mac, for conflict spotting. Reads `com.apple.symbolichotkeys` and `NSUserKeyEquivalents`.
  Names come from Apple's own tables in `KeyboardSettings.appex`, never from a hardcoded guess;
  ids absent from those tables are shown as `Raccourci systeme #N` rather than invented.

A global hotkey takes priority over app shortcuts, so binding a combo an app uses (⇧⌘S is
"Save As" in many) shadows it everywhere. Worth telling Mickael when it applies.

## Configuration

- `project.yml` — XcodeGen project spec (deployment target, signing, entitlements)
- `MacTools.entitlements` — Calendar access entitlement
- `Info.plist` — LSUIElement, calendar usage description
