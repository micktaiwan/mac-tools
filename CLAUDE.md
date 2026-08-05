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

## Keyboard shortcuts

Global hotkeys run shell commands. Adding one goes through the IPC socket, never by hand:
`docs/shortcuts.md`.

## Configuration

- `project.yml` — XcodeGen project spec (deployment target, signing, entitlements)
- `MacTools.entitlements` — Calendar access entitlement
- `Info.plist` — LSUIElement, calendar usage description
