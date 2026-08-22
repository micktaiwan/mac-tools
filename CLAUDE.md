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

**IPC** (`IPC/`)
- `IPCServer` — the app's control socket, one JSON object in, one out. It was
  `Shortcuts/ShortcutsIPCServer.swift` while shortcuts were the only thing anybody asked it
  for; they are not any more, so it moved here. See the dedicated section below.

**Snap** (`Snap/`) — drag a window against a screen edge, it snaps. Top maximizes, left and right take half. See the dedicated section below.

**Phone** (`Phone/`) — the phone's processor, memory, heat and battery in a second status item.
See the dedicated section below.

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

## The control socket (`MacTools/Features/IPC/`)

One Unix socket at `~/Library/Application Support/MacTools/ipc.sock`, one JSON object per
connection in, one out, connection closed. Driven from a terminal with:

```bash
echo '{"command":"next-event"}' | nc -U "$HOME/Library/Application Support/MacTools/ipc.sock"
```

Commands: `list`, `add`, `remove`, `enable`, `run`, `reload` for the shortcuts, plus
`next-event`.

**`next-event` is why the file stopped being called `ShortcutsIPCServer`.** This app is the
one holding the calendar permission on this Mac, so it is the only thing that can answer
"when is the next meeting". Eko, the desk robot, asks that through `kited`
(`~/projects/perso/kite/daemon/src/mactools.rs`).

It answers with **facts and never with a screen**: a title, a wall-clock start, a number of
minutes, the ISO instant, the calendar's name. What the robot does with a meeting in four
minutes is the robot's business.

Two behaviours worth keeping if this is ever rewritten. A day with nothing left answers
`present: false` — no meeting is an answer, and a caller that read it as a failure would
show a broken screen every evening. And **it refuses outright when the calendar permission
is missing**, rather than answering "no meeting": without that, an empty day and an app that
was never granted access are indistinguishable at the other end.

## Keyboard shortcuts

Global hotkeys run shell commands. Adding one goes through the IPC socket, never by hand:
`docs/shortcuts.md`.

## Leaves (`MacTools/Features/Lucca/`)

Who is off today at lempire, read from Lucca's Timmi Absences module and shown in the
popover under the emails. It exists because Mickael was asking the same question four times
a day through the `/lucca` skill, which meant a terminal pane and a wait each time; here the
answer is already on screen when the menu opens.

- `LuccaClient` — the v3 API: `Authorization: lucca application=<key>`, collections wrapped
  in `{ data: { items: [] } }`, `paging={offset},{limit}`. Two calls, users and leaves, run
  concurrently. **A leave's `id` is a string** (`"3644-20260810-PM"`), which is why nothing
  decodes it — the owner comes from `leavePeriod.ownerId`, an Int. The morning flag ships as
  `isAM` on some Lucca versions and `isAm` on others, so both keys are decoded.
- `LuccaService` — one leave is a **half-day**; the two halves are folded into full / matin /
  après-midi per person, then grouped by department. The fetch covers 90 days even though
  only today is listed, because each row also shows the **last day of the current run** —
  weekends are stepped over (nobody books a Saturday, so Friday to Monday is one absence),
  public holidays are not, since this endpoint does not expose them. **Data and SRE roll up
  into Tech**:
  Lucca's departments split them out, the org chart does not. The day is resolved at fetch
  time and in the **local** timezone, so the app rolls over on its own and never asks for
  yesterday late at night. Refresh every 3 hours, plus the popover's refresh button. A
  failed fetch keeps the previous list and shows the error above it rather than blanking the
  section.
- `LuccaCredentials` — instance URL in UserDefaults, **API key in the Keychain**, never in
  the preferences. At first launch, both are read once from `~/projects/perso/lucca/.env`
  (the `lucca-leaves` CLI, which stays the reference implementation) so the key never has to
  be pasted; afterwards the Keychain is the only source.

The CLI is still the place for anything the menu does not answer — a date range, one
person's future leaves, JSON — through the `/lucca` skill.

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

## The phone (`MacTools/Features/Phone/`)

A second `NSStatusItem`, showing the processor load of Mickael's Pixel and its battery level, with
a popover for the detail. The measuring is done entirely by Kite on the phone and stored by
`kited`; nothing here computes anything, because nothing on this Mac can — the counters are behind
SELinux. What is and is not readable from an Android app is documented in
`~/projects/perso/kite/CLAUDE.md`, decision 8.

- `PhoneStatsService` reads `~/.local/share/kited/stats.jsonl` **off the disk**, not over HTTP.
  Same machine, same user, so a port, a bearer token and a reachable daemon would be three more
  things able to break for a file that can simply be opened. It reads a 64 KB window off the end
  and drops the first fragment, because a window that starts mid-line starts on half a JSON object.
- **Stale is a state, not an absence.** Anything older than 70 seconds stops being a reading and
  becomes a dash. A phone that stopped reporting is otherwise indistinguishable from a quiet one:
  same figure on screen, nothing saying it is frozen. Same lesson `phone.rs` carries in `kited`.
- **Why a second item rather than a third field in the existing title.** That title already
  concatenates the next meeting and the unread count, both of which vary in width; a third would
  let the phone push the meeting off a narrow screen. A separate item is also independently
  hideable and movable with a Cmd-drag.
- **Why the figure is the processor load.** Not because it is the most useful thing to know — the
  warnings matter far more — but because a number that moves is its own proof of life. A health
  dot sitting on green looks identical whether the phone is fine or whether nothing has arrived
  since Tuesday.
- **One colour, one meaning.** The load colours itself (green under 50%, orange to 85%, red
  above), the icon carries the warnings in orange, the battery has its own. The first version
  painted the processor figure with a thermal warning, which produced an alarming 6% with no way
  to learn the alarm was about heat.

- **The drain ranking is a different clock from everything above it.** Every other figure in the
  popover covers the last twenty seconds; the per-application ranking counts from the phone's last
  full charge and refreshes every five minutes. It is labelled with that window on screen, because
  a ranking silently covering the whole day gets read as "right now" and blames the wrong app. The
  service keeps the newest non-empty one rather than reading the last line, so the section does not
  blink in and out with the cadence.

**Two thresholds that had to be corrected the same evening, for the same mistake: alerting on a
normal state.** Both are worth keeping in mind before adding a third.

- **Thermal level 1 is not a warning.** Android documents `THERMAL_STATUS_LIGHT` as "light
  throttling where UX is not impacted", and this phone sits at 1 the entire time it is on a
  charger. The threshold is 2.
- **How full the swap is means nothing here.** It is zram, compressed pages held in RAM, which
  Android fills on purpose to keep applications warm; measured on 21/08/2026 it went from 2.7 GB
  free to 80 MB free within half an hour of a reboot while the phone was healthy. What actually
  separated a sick phone from a healthy one was the read-back rate: 206 pages a second at 20% load,
  against 6 a second at 5% afterwards. That rate lives in `/proc/vmstat`, which an app may not
  read, so this side cannot see it and there is no swap warning at all.

## Configuration

- `project.yml` — XcodeGen project spec (deployment target, signing, entitlements)
- `MacTools.entitlements` — Calendar access entitlement
- `Info.plist` — LSUIElement, calendar usage description
