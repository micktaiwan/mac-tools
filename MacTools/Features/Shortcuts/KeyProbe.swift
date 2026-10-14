import AppKit

/// Logs what the keyboard actually sends when a modifier combo is pressed, to
/// tell "the hotkey is not registered" from "the key press is not the combo we
/// think it is". Off unless `defaults write com.micktaiwan.MacTools debugKeyLog
/// -bool YES`. Only key presses held with control, option or command are
/// logged, never plain typing. Writes to the same file as `ShortcutLog`.
///
/// A global keyDown monitor needs the Accessibility grant; without it macOS
/// delivers nothing, so the trust status is logged at start.
@MainActor
enum KeyProbe {
    private static var monitors: [Any] = []

    static func startIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "debugKeyLog"), monitors.isEmpty else { return }
        ShortcutLog.write("probe start accessibility=\(AXIsProcessTrusted())")

        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            MainActor.assumeIsolated { log(event, scope: "global") }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            MainActor.assumeIsolated { log(event, scope: "local") }
            return event
        }) {
            monitors.append(local)
        }
    }

    private static func log(_ event: NSEvent, scope: String) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.control, .option, .command]).isEmpty else { return }

        var names: [String] = []
        if flags.contains(.control) { names.append("control") }
        if flags.contains(.option) { names.append("option") }
        if flags.contains(.shift) { names.append("shift") }
        if flags.contains(.command) { names.append("command") }
        if flags.contains(.function) { names.append("fn") }
        if flags.contains(.capsLock) { names.append("capslock") }

        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        let chars = event.charactersIgnoringModifiers ?? ""
        ShortcutLog.write("probe \(scope) keyCode=\(event.keyCode) chars=\(chars.debugDescription) flags=\(names.joined(separator: "+")) front=\(front)")
    }
}
