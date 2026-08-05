import AppKit

/// Watches left-button drags across the whole desktop and reports when one is
/// a window being carried against a screen edge.
///
/// The hard part is telling "the user is moving a window" from "the user is
/// selecting text" or "the user is drawing". Guessing from what was clicked
/// (title bar? tool bar?) is unreliable across applications, so this asks the
/// window itself: if its origin moved between the click and the drag, it is
/// being carried. Nothing else can produce that.
@MainActor
final class DragMonitor {
    struct Handlers {
        /// Fired whenever the previewed zone changes, nil when leaving an edge.
        let previewChanged: (SnapZone?, NSScreen?) -> Void
        /// Fired on mouse up over an edge, with the window to snap.
        let dropped: (AXWindow, SnapZone, NSScreen) -> Void
    }

    /// How close to an edge the cursor has to be. Small on purpose: the zone
    /// must be reachable by shoving the pointer at the edge, not by passing
    /// anywhere near it.
    var edgeThreshold: CGFloat = 6

    private let handlers: Handlers
    private var monitors: [Any] = []
    private var drag: Drag?

    /// The state of one press-drag-release cycle.
    private struct Drag {
        let window: AXWindow
        let originAtMouseDown: CGPoint
        var isCarryingWindow = false
        /// Times we asked the window whether it moved yet. Bounded so a drag
        /// that is not a window move (text selection) stops costing a round
        /// trip into the other process on every single event.
        var moveChecks = 0
        var zone: SnapZone?
        var screen: NSScreen?
        /// Where the cursor was at the previous sample, so a fast gesture can
        /// be tested along its path and not only where it happened to land.
        var lastPoint: CGPoint
    }

    private static let maxMoveChecks = 15

    init(handlers: Handlers) {
        self.handlers = handlers
    }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        // Global monitors never see events aimed at our own app, so the Options
        // window would not snap without this one.
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
        cancel()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: beginDrag()
        case .leftMouseDragged: continueDrag()
        case .leftMouseUp: endDrag()
        default: break
        }
    }

    private func beginDrag() {
        // `NSEvent.mouseLocation` rather than the event's own location: it is
        // already in global AppKit coordinates whatever window was hit.
        let point = NSEvent.mouseLocation
        drag = nil
        guard let window = AXWindow.atPoint(point) else {
            SnapLog.write("down (\(fmt(point))) -> aucune fenetre sous le curseur")
            return
        }
        guard window.isSnappable else {
            SnapLog.write("down (\(fmt(point))) -> fenetre non deplacable")
            return
        }
        guard let frame = window.frame else {
            SnapLog.write("down (\(fmt(point))) -> frame illisible")
            return
        }
        SnapLog.write("down (\(fmt(point))) fenetre \(fmt(frame))")
        drag = Drag(window: window, originAtMouseDown: frame.origin, lastPoint: point)
    }

    private func continueDrag() {
        guard var drag else { return }

        if !drag.isCarryingWindow {
            guard drag.moveChecks < Self.maxMoveChecks else {
                // Long drag, window never moved: not a window move. Drop it.
                self.drag = nil
                return
            }
            drag.moveChecks += 1
            guard let frame = drag.window.frame else {
                self.drag = nil
                return
            }
            let moved = hypot(
                frame.origin.x - drag.originAtMouseDown.x,
                frame.origin.y - drag.originAtMouseDown.y
            )
            // A couple of points of slack absorbs the jitter of a click that
            // was not meant to move anything.
            guard moved > 2 else {
                self.drag = drag
                return
            }
            drag.isCarryingWindow = true
        }

        let point = NSEvent.mouseLocation
        let hit = SnapZoneDetector.hit(movingFrom: drag.lastPoint, to: point, threshold: edgeThreshold)
        // Full cursor path: without it there is no way to tell a band that was
        // never entered from a band that was entered and ignored.
        SnapLog.write("  ..(\(fmt(point))) zone=\(hit?.zone.rawValue ?? "-")")
        drag.lastPoint = point
        let changed = hit?.zone != drag.zone || hit?.screen != drag.screen
        drag.zone = hit?.zone
        drag.screen = hit?.screen
        self.drag = drag

        if changed {
            SnapLog.write("drag (\(fmt(point))) -> zone \(hit?.zone.rawValue ?? "aucune") ecran \(hit.map { screenIndex($0.screen) } ?? -1)")
            handlers.previewChanged(hit?.zone, hit?.screen)
        }
    }

    private func endDrag() {
        defer { cancel() }
        guard let drag else {
            SnapLog.write("up -> aucun drag suivi")
            return
        }
        guard drag.isCarryingWindow else {
            SnapLog.write("up -> la fenetre n'a jamais bouge (checks=\(drag.moveChecks))")
            return
        }
        guard let zone = drag.zone, let screen = drag.screen else {
            SnapLog.write("up (\(fmt(drag.lastPoint))) -> aucune zone active, rien a appliquer")
            return
        }
        SnapLog.write("up (\(fmt(drag.lastPoint))) -> applique \(zone.rawValue) sur ecran \(screenIndex(screen))")
        handlers.dropped(drag.window, zone, screen)
    }

    private func screenIndex(_ screen: NSScreen) -> Int {
        NSScreen.screens.firstIndex(of: screen) ?? -1
    }

    private func fmt(_ point: CGPoint) -> String {
        String(format: "%.0f,%.0f", point.x, point.y)
    }

    private func fmt(_ rect: CGRect) -> String {
        String(format: "%.0f,%.0f %.0fx%.0f", rect.minX, rect.minY, rect.width, rect.height)
    }

    private func cancel() {
        let hadPreview = drag?.zone != nil
        drag = nil
        if hadPreview {
            handlers.previewChanged(nil, nil)
        }
    }
}
