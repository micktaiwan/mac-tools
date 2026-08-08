import AppKit

/// Reports which modifier keys are being held, once they have been held long
/// enough to mean "show me what I can do from here" rather than "I am typing".
///
/// This is the one part of the shortcuts feature that needs the Accessibility
/// grant: a modifier pressed alone is not a hotkey, so Carbon cannot see it
/// (`HotKeyCenter`), and only a global event monitor can.
///
/// Deliberately limited to `.flagsChanged`. Watching `.keyDown` would make
/// dismissal slightly crisper, but it would also mean the app reads every
/// keystroke typed on the machine, which this feature does not need.
@MainActor
final class ModifierWatcher {
    /// Held long enough to be a question, not a keystroke in progress.
    var holdDelay: TimeInterval = 0.45

    private let onChange: (Set<UserShortcut.Modifier>) -> Void
    private var monitors: [Any] = []
    private var pendingReveal: DispatchWorkItem?
    private var revealed = false

    init(onChange: @escaping (Set<UserShortcut.Modifier>) -> Void) {
        self.onChange = onChange
    }

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        // Global monitors never see events aimed at our own app.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        cancelPending()
        if revealed {
            revealed = false
            onChange([])
        }
    }

    private func handle(_ event: NSEvent) {
        let held = Self.modifiers(from: event.modifierFlags)

        guard !held.isEmpty else {
            cancelPending()
            if revealed {
                revealed = false
                onChange([])
            }
            return
        }

        // Already on screen: follow every added or removed modifier live.
        if revealed {
            onChange(held)
            return
        }

        // Not on screen yet: restart the countdown on each change, so a quick
        // ⇧⌘L never flashes anything.
        cancelPending()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.revealed = true
            self.onChange(held)
        }
        pendingReveal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay, execute: work)
    }

    private func cancelPending() {
        pendingReveal?.cancel()
        pendingReveal = nil
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> Set<UserShortcut.Modifier> {
        var held: Set<UserShortcut.Modifier> = []
        if flags.contains(.command) { held.insert(.command) }
        if flags.contains(.shift) { held.insert(.shift) }
        if flags.contains(.option) { held.insert(.option) }
        if flags.contains(.control) { held.insert(.control) }
        return held
    }
}
