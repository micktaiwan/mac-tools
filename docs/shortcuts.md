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

`list` returns `lastExitCode`, `lastOutput` and `lastRun` per shortcut — that is how a failing
script gets diagnosed instead of being a key press that does nothing.

Storage is `~/Library/Application Support/MacTools/shortcuts.json`. The app watches the
directory, so editing that file by hand re-registers the hotkeys within a second; the socket
is a convenience, not the only way in.

A global hotkey takes priority over app shortcuts, so binding a combo an app uses (⇧⌘S is
"Save As" in many) shadows it everywhere. Worth telling Mickael when it applies.

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
- `ShortcutsIPCServer` — Unix socket server.
- `ShortcutsService` — Unrelated to the above: read-only inventory of shortcuts *already taken*
  on the Mac, for conflict spotting. Reads `com.apple.symbolichotkeys` and `NSUserKeyEquivalents`.
  Names come from Apple's own tables in `KeyboardSettings.appex`, never from a hardcoded guess;
  ids absent from those tables are shown as `Raccourci systeme #N` rather than invented.
