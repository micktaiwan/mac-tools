# Keyboard shortcuts — how to add one for Mickael

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

`list` returns `{"ok", "shortcuts": [...]}`, each with `id`, `name`, `combo` (rendered, e.g. "⌃⌥G" — the `key`/`modifiers` given to `add` are not echoed back), `command`, `enabled`, plus `lastExitCode`, `lastOutput` and `lastRun` once it has fired — that is how a failing
script gets diagnosed instead of being a key press that does nothing.

Storage is `~/Library/Application Support/MacTools/shortcuts.json`. The app watches the
directory, so editing that file by hand re-registers the hotkeys within a second; the socket
is a convenience, not the only way in.

A global hotkey takes priority over app shortcuts, so binding a combo an app uses (⇧⌘S is
"Save As" in many) shadows it everywhere. Worth telling Mickael when it applies.

## Debugging a shortcut that "does nothing"

Start by recording what the keyboard actually sends, before looking for something that
intercepts it. On 13/10/2026 a ⌃⇧N "that did not work with Kova in front" was really a ⇧⌘N
press: an hour of hunting event taps, then one probe line settled it.

- `~/Library/Logs/MacTools-shortcuts.log` (`ShortcutLog`) — always on, one line per fire with
  its source: `hotkey <id>` for a real key press, `ipc-run <id>` for the socket's `run`.
  `lastRun` keeps only the latest run and cannot tell the two apart.
- `KeyProbe` — `defaults write com.micktaiwan.MacTools debugKeyLog -bool YES`, then relaunch.
  Logs keyCode, characters, modifiers and frontmost app for every key press held with ⌃, ⌥
  or ⌘ (never plain typing), into the same file. Needs the Accessibility grant. Delete the
  key and relaunch when done.

## Implementation (`MacTools/Features/Shortcuts/`)

- `UserShortcut` — Codable model. `key` is a single character ("l") or a named key ("f5", "space").
- `KeyCodeResolver` — Resolves `key` against the *current keyboard layout* via `UCKeyTranslate`,
  so "a" means the key that types an A on Mickael's French layout, not ANSI position A.
- `HotKeyCenter` — Carbon `RegisterEventHotKey`. Chosen over `CGEventTap` because it needs no
  Accessibility permission: the app only ever sees the combos it declared. The trade-off is no
  double-tap, no key sequences, no gestures. Changing that means an Accessibility prompt.
- `ActionRunner` — Runs the command through `/bin/zsh -lc` (login shell, so `~/.local/bin` is in
  PATH), captures stdout and stderr together with the exit code.
- `ShortcutStore` — Source of truth: loads/saves the JSON, watches the directory, re-registers.
- `ShortcutLog`, `KeyProbe` — the fire log and the key probe, see the debugging section above.
- `IPCServer` (`MacTools/Features/IPC/`) — Unix socket server. It also answers
  `next-event`, which has nothing to do with shortcuts: see the CLAUDE.md section.
- `ShortcutsService` — Unrelated to the above: read-only inventory of shortcuts *already taken*
  on the Mac, for conflict spotting. Reads `com.apple.symbolichotkeys` and `NSUserKeyEquivalents`.
  Names come from Apple's own tables in `KeyboardSettings.appex`, never from a hardcoded guess;
  ids absent from those tables are shown as `Raccourci systeme #N` rather than invented.
