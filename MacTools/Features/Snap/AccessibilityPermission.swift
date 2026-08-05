import AppKit
import ApplicationServices

/// Moving another application's windows goes through the Accessibility API,
/// which is gated behind an explicit user grant.
///
/// This is the one thing in MacTools that needs a permission of this weight:
/// the shortcuts deliberately use Carbon to avoid it (see `HotKeyCenter`).
/// Snapping has no such escape hatch, there is no other way to resize a window
/// you do not own.
enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks for the right, and actually gets the system alert on screen.
    ///
    /// `AXIsProcessTrustedWithOptions` only prompts while TCC holds no decision
    /// for this app. Once the user has denied once (or dismissed the alert,
    /// which counts as a denial), every later call returns silently and the
    /// button looks broken. Clearing our own TCC entry first puts the app back
    /// in the undecided state, so the alert can be shown again.
    static func request() {
        if !isGranted { clearOwnDecision() }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// `tccutil reset <service> <bundle id>` scoped to ourselves. Resetting our
    /// own entry needs no privileges; it cannot touch any other app.
    private static func clearOwnDecision() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Nothing to do: the prompt below is attempted either way.
        }
    }

    static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
