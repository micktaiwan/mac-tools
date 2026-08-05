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

**Snap** (`Snap/`) — drag a window against a screen edge, it snaps. Top maximizes, left and right take half. See the dedicated section below.

**Options** (`Options/`)
- `OptionsWindowController` — Owns the single Options window. Activates the app (`NSApp.activate`) because LSUIElement apps open windows behind everything otherwise.
- `OptionsWindowView` — `NavigationSplitView` with the vertical tab list, plus the shared `OptionsPage` container. Tabs: General, Calendar and mail, Shortcuts, Windows.

### Key patterns
- **Never use `fixedSize(horizontal: false, vertical: true)` on an options page.** Inside
  `OptionsPage` the proposed width is unbounded during the sizing pass, so the text asks for
  an infinite line and the *entire* `NavigationSplitView` renders blank — sidebar included,
  with no crash and no log. Give paragraphs an explicit `.frame(width:)` instead. Cost a full
  debugging session; the symptom points at the page you just added, the cause is the layout
  modifier.
- Debug hook for an options page: `defaults write com.micktaiwan.MacTools debugOpenOptionsTab
  <tab raw value>` opens the window on that tab at launch, so a page can be iterated on
  without clicking through the UI. Delete the key when done.
- Services are `@MainActor` `ObservableObject` classes with `@Published` properties
- `AppDelegate` subscribes to service publishers via Combine to update the menu bar title
- Menu bar updates every 30s (timer) for relative time freshness
- Calendar refreshes every 60s + on `EKEventStoreChanged` notifications
- UI text is in French

## Keyboard shortcuts

Global hotkeys run shell commands. Adding one goes through the IPC socket, never by hand:
`docs/shortcuts.md`.

## Window snapping (`MacTools/Features/Snap/`)

Off by default, turned on in Options > Fenetres. macOS ships its own edge tiling since 15,
but it does nothing on Mickael's Mac, which is why this exists.

- `SnapZone` — The three active zones (top = full screen, left/right = half) and the target
  frame, computed from `visibleFrame` so the menu bar and Dock stay clear. `SnapZoneDetector`
  turns a cursor position into a zone. Corners and the bottom edge are deliberately absent:
  dragging a window downwards is a normal gesture and snapping it would fight the user.
- `AXWindow` — Another app's window through the Accessibility API. **Owns the coordinate
  flip**: Accessibility is top-left origin of the primary screen, AppKit is bottom-left.
  Every frame crossing that boundary goes through `flip`, which is its own inverse. Get this
  wrong and windows land on the wrong display. Also sets an AX messaging timeout, because
  each call is a synchronous round trip into another process and a hung app would freeze the
  drag.
- `DragMonitor` — Global + local `NSEvent` monitors on left mouse down/dragged/up. Tells "the
  user is moving a window" from "the user is selecting text" by asking the window whether its
  origin moved since the click; nothing but a real window drag does that. The check is capped
  at 15 attempts so a text selection stops costing an IPC round trip per event.
- `SnapOverlay` — Borderless click-through `NSWindow` drawing the preview rectangle.
- `SnapLog` — Drag trace (cursor path, zone per sample, frame before/after, AX error codes,
  owning app) to `~/Library/Logs/MacTools-snap.log`, off unless `defaults write
  com.micktaiwan.MacTools debugSnapLog -bool YES`. Snapping cannot be debugged from the
  outside, and stderr is lost when the app is launched the normal way — which it must be, or
  macOS denies it the Accessibility right.
- `SnapService` — The `ObservableObject` wiring the above, owning the on/off state, the edge
  threshold, and the permission status.

**Accessibility permission is required** and there is no way around it: resizing a window you
do not own has no other API. This is the exception to the no-permission stance `HotKeyCenter`
takes for the shortcuts. Because macOS keys that grant to the code signature, `project.yml`
signs with the Apple Development identity (team `ZMKDR6H89Y`) rather than ad hoc — an ad-hoc
signature changes on every build, which would revoke the grant each time the app is
reinstalled.

**Resize before moving.** `AXWindow.setFrame` sets the size, then the position, then the size
again. A window filling the screen cannot be moved to the half it is being asked for without
hanging off the display, and applications refuse that move: the window ends up placed but
still full width, straddling both screens. The symptom reads like a coordinate bug and is
purely an ordering one. Always read back the resulting frame — the AX setters return an error
code that is easy to ignore, and a refused resize is otherwise silent.

Two permission traps, both hit for real while building this:

- **A denial is permanent and silent.** `AXIsProcessTrustedWithOptions` only shows its alert
  while TCC holds *no* decision. After one denial (dismissing the alert counts), every later
  call returns without doing anything and the button looks broken. `AccessibilityPermission`
  therefore runs `tccutil reset Accessibility <bundle id>` on itself first, which needs no
  privileges and puts the app back in the undecided state. Mickael must never be sent to
  System Settings to fix this by hand.
- **Accessibility lives in the system TCC database**, `/Library/Application Support/
  com.apple.TCC/TCC.db`, not the per-user one. Querying the user database to check the grant
  finds nothing and means nothing. `auth_value` 2 is granted, 0 is denied, no row is
  undecided.

Launching the app by running its binary directly (rather than `open -a`) breaks TCC
attribution: the request never reaches tccd. It also makes `AXIsProcessTrusted()` report the
*terminal's* trust, so a debug launch reads as permitted when the app is not. Debug
permissions the normal way.

**Changing the signing identity voids every existing grant**, not just Accessibility. The TCC
row survives with `auth_value` 2 but its code requirement no longer matches, so the framework
reports "not determined" while the system refuses to prompt again — the calendar silently
stopped working when this was switched away from ad hoc. Fix: `tccutil reset <service>
<bundle id>`, then relaunch through `open`.

Multi-screen is written for (every lookup goes through `NSScreen.screens`) but only tested on
one display so far.

## Configuration

- `project.yml` — XcodeGen project spec (deployment target, signing, entitlements)
- `MacTools.entitlements` — Calendar access entitlement
- `Info.plist` — LSUIElement, calendar usage description
