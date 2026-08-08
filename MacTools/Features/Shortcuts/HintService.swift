import AppKit
import SwiftUI

/// Hold a modifier, see what it can reach. Owns the on/off state, the
/// Accessibility permission status, and wires the watcher to the panel.
///
/// Separate from `ShortcutStore` on purpose: the shortcuts themselves keep
/// working on Carbon with no permission at all if this is left off.
@MainActor
final class HintService: ObservableObject {
    private static let enabledKey = "shortcutHintsEnabled"

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            apply()
        }
    }
    @Published private(set) var hasPermission = AccessibilityPermission.isGranted

    private let store: ShortcutStore
    private let inventory: ShortcutsService
    private let hud = ShortcutHUD()
    private var watcher: ModifierWatcher?
    private var permissionTimer: Timer?

    init(store: ShortcutStore, inventory: ShortcutsService) {
        self.store = store
        self.inventory = inventory
        // Off by default: turning it on is what asks for Accessibility.
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    deinit {
        permissionTimer?.invalidate()
    }

    func start() {
        apply()
    }

    func requestPermission() {
        AccessibilityPermission.request()
        pollPermission()
    }

    private func apply() {
        hasPermission = AccessibilityPermission.isGranted

        guard isEnabled, hasPermission else {
            watcher?.stop()
            watcher = nil
            hud.hide()
            if isEnabled && !hasPermission { pollPermission() }
            return
        }

        guard watcher == nil else { return }
        let watcher = ModifierWatcher { [weak self] held in
            self?.update(held: held)
        }
        watcher.start()
        self.watcher = watcher
    }

    private func update(held: Set<UserShortcut.Modifier>) {
        guard !held.isEmpty else {
            hud.hide()
            return
        }
        hud.show(HUDContent.make(
            held: held,
            mine: store.shortcuts,
            system: inventory.shortcuts
        ))
    }

    /// The system grant lands asynchronously, and macOS sends no notification
    /// for it: polling is the only way to notice without a restart.
    private func pollPermission() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { return }
                let granted = AccessibilityPermission.isGranted
                guard granted != self.hasPermission else { return }
                self.hasPermission = granted
                timer.invalidate()
                self.apply()
            }
        }
    }
}
