# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

macOS menu bar app (13+) built with Swift/SwiftUI. Displays calendar events and Gmail unread count in the menu bar. No Dock icon (LSUIElement).

## Build

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`.

```bash
xcodegen generate
xcodebuild -scheme MacTools -configuration Debug build
```

Install to /Applications:
```bash
cp -R ~/Library/Developer/Xcode/DerivedData/MacTools-*/Build/Products/Debug/MacTools.app /Applications/
```

## Architecture

Single-target SwiftUI app with `@NSApplicationDelegateAdaptor` for menu bar integration via `NSStatusItem` + `NSPopover`.

### Entry point
- `MacToolsApp.swift` — App entry, `AppDelegate` manages the status item, popover, and coordinates services. `MenuContentView` composes the popover UI from feature views.

### Features (under `MacTools/Features/`)

**Calendar** (`Calendar/`)
- `CalendarService` — `ObservableObject` wrapping EventKit. Fetches today's upcoming timed events, falls back to tomorrow if none remain. Supports calendar filtering via `excludedCalendarIDs` persisted in UserDefaults.
- `CalendarMenuView` — Event list + settings (calendar toggles, launch at startup, quit). Handles authorization states.
- `CalendarMenuBarLabel` — Formats the next event for the menu bar title (relative time if <60min, absolute time otherwise).

**Gmail** (`Gmail/`)
- `GmailService` — Shells out to `gws` CLI (Google Workspace CLI) to fetch unread inbox messages. Looks for `gws` in `/usr/local/bin`, `/opt/homebrew/bin`, or nvm node versions. Polls every 2 minutes.
- `GmailMenuView` — Displays unread emails with trash action (moves to trash via `gws`).

### Key patterns
- Services are `@MainActor` `ObservableObject` classes with `@Published` properties
- `AppDelegate` subscribes to service publishers via Combine to update the menu bar title
- Menu bar updates every 30s (timer) for relative time freshness
- Calendar refreshes every 60s + on `EKEventStoreChanged` notifications
- UI text is in French

## Configuration

- `project.yml` — XcodeGen project spec (deployment target, signing, entitlements)
- `MacTools.entitlements` — Calendar access entitlement
- `Info.plist` — LSUIElement, calendar usage description
