import AppKit
import Combine

/// Ties the pieces together: watches drags, previews the target zone, applies
/// it on drop. Owns the on/off state and the Accessibility permission status
/// the options page displays.
@MainActor
final class SnapService: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            // Turning it on is the moment to ask: the checkbox is the only
            // thing the user should have to touch, the permission is our
            // problem to sort out from there.
            if isEnabled && !hasPermission { requestPermission() }
            syncMonitor()
        }
    }

    @Published var edgeThreshold: Double {
        didSet {
            UserDefaults.standard.set(edgeThreshold, forKey: Keys.edgeThreshold)
            dragMonitor?.edgeThreshold = CGFloat(edgeThreshold)
        }
    }

    @Published private(set) var hasPermission: Bool = AccessibilityPermission.isGranted

    private enum Keys {
        static let enabled = "snapEnabled"
        static let edgeThreshold = "snapEdgeThreshold"
    }

    private var dragMonitor: DragMonitor?
    /// Built on the first preview, not before. The service is created while the
    /// app is still launching, which is too early to be making windows.
    private var overlay: SnapOverlay?
    private var permissionTimer: Timer?

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? false
        edgeThreshold = defaults.object(forKey: Keys.edgeThreshold) as? Double ?? 6
    }

    func start() {
        syncMonitor()
        watchPermission()
    }

    /// Shows the system alert, then keeps polling: macOS grants the right the
    /// moment the checkbox is ticked, with no notification of any kind.
    func requestPermission() {
        AccessibilityPermission.request()
        refreshPermission()
        watchPermission()
    }

    private func refreshPermission() {
        let granted = AccessibilityPermission.isGranted
        guard granted != hasPermission else { return }
        hasPermission = granted
        syncMonitor()
    }

    /// Polls only while the right is missing. Once granted, macOS restarts the
    /// app if it is ever revoked, so there is nothing left to watch.
    private func watchPermission() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshPermission()
                if self.hasPermission { timer.invalidate(); self.permissionTimer = nil }
            }
        }
    }

    private func syncMonitor() {
        let shouldRun = isEnabled && hasPermission
        if shouldRun {
            if dragMonitor == nil {
                let monitor = DragMonitor(handlers: DragMonitor.Handlers(
                    previewChanged: { [weak self] zone, screen in
                        self?.updatePreview(zone: zone, screen: screen)
                    },
                    dropped: { [weak self] window, zone, screen in
                        self?.apply(zone: zone, to: window, on: screen)
                    }
                ))
                monitor.edgeThreshold = CGFloat(edgeThreshold)
                monitor.start()
                dragMonitor = monitor
            }
        } else {
            dragMonitor?.stop()
            dragMonitor = nil
            overlay?.hide()
        }
    }

    private func updatePreview(zone: SnapZone?, screen: NSScreen?) {
        guard let zone, let screen else {
            overlay?.hide()
            return
        }
        if overlay == nil { overlay = SnapOverlay() }
        overlay?.show(frame: zone.frame(in: screen))
    }

    private func apply(zone: SnapZone, to window: AXWindow, on screen: NSScreen) {
        overlay?.hide()
        let target = zone.frame(in: screen)
        SnapLog.write("apply \(zone.rawValue) cible \(Self.describe(target)) avant \(Self.describe(window.frame))")
        window.setFrame(target)
        SnapLog.write("apply -> apres \(Self.describe(window.frame))")

        // The drop is the moment the window server is still finishing the drag
        // it was running, and a resize landing in that window can be dropped on
        // the floor. One late retry costs nothing and catches it.
        guard !Self.matches(window.frame, target) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            window.setFrame(target)
            SnapLog.write("apply -> reprise \(Self.describe(window.frame))")
        }
    }

    private static func matches(_ frame: CGRect?, _ target: CGRect) -> Bool {
        guard let frame else { return false }
        return abs(frame.width - target.width) <= 2 && abs(frame.height - target.height) <= 2
    }

    private static func describe(_ rect: CGRect?) -> String {
        guard let rect else { return "illisible" }
        return String(format: "%.0f,%.0f %.0fx%.0f", rect.minX, rect.minY, rect.width, rect.height)
    }
}
