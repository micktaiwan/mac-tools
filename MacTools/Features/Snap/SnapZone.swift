import AppKit

/// The areas a window can be snapped to when it is dropped against an edge.
///
/// Only the three edges in use are here. Corners and the bottom edge were left
/// out on purpose: dragging a window downwards is a normal gesture, and firing
/// a snap on it would fight the user rather than help.
enum SnapZone: String, CaseIterable {
    case fullScreen
    case leftHalf
    case rightHalf

    var label: String {
        switch self {
        case .fullScreen: return "Plein ecran"
        case .leftHalf: return "Moitie gauche"
        case .rightHalf: return "Moitie droite"
        }
    }

    /// Target frame in AppKit coordinates (origin bottom-left).
    ///
    /// Built from `visibleFrame`, so the result never sits under the menu bar
    /// or the Dock. Halves are rounded so the two of them tile the screen with
    /// no one-pixel gap down the middle on odd widths.
    func frame(in screen: NSScreen) -> CGRect {
        let area = screen.visibleFrame
        switch self {
        case .fullScreen:
            return area
        case .leftHalf:
            let width = (area.width / 2).rounded(.down)
            return CGRect(x: area.minX, y: area.minY, width: width, height: area.height)
        case .rightHalf:
            let width = (area.width / 2).rounded(.down)
            return CGRect(x: area.minX + width, y: area.minY, width: area.width - width, height: area.height)
        }
    }
}

/// Turns a cursor position into the zone it is asking for.
enum SnapZoneDetector {
    /// Zone under the cursor at the end of a movement, looking at the path
    /// travelled rather than only the final position.
    ///
    /// Sampling along the segment is what makes a fast drag through a shared
    /// edge register at all. Scanning backwards from where the cursor now is
    /// keeps the answer closest to the intent: the last band touched wins.
    static func hit(
        movingFrom previous: CGPoint,
        to current: CGPoint,
        threshold: CGFloat
    ) -> (zone: SnapZone, screen: NSScreen)? {
        if let direct = hit(at: current, threshold: threshold) { return direct }

        let travelled = hypot(current.x - previous.x, current.y - previous.y)
        guard travelled > 1 else { return nil }

        // One sample every few points, capped so a drag across three displays
        // cannot turn into a long loop.
        let steps = min(Int(travelled / 3), 64)
        guard steps > 0 else { return nil }

        for step in 1...steps {
            let ratio = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(
                x: current.x + (previous.x - current.x) * ratio,
                y: current.y + (previous.y - current.y) * ratio
            )
            if let hit = hit(at: point, threshold: threshold) { return hit }
        }
        return nil
    }

    /// `point` is in AppKit coordinates. Returns nil when the cursor is not
    /// against an edge, which is the common case during an ordinary drag.
    static func hit(at point: CGPoint, threshold: CGFloat) -> (zone: SnapZone, screen: NSScreen)? {
        guard let screen = screen(containing: point) else { return nil }
        let frame = screen.frame

        // Top wins over the sides so the corners still maximize rather than
        // being a dead spot between two zones.
        if point.y >= frame.maxY - threshold { return (.fullScreen, screen) }
        if point.x <= frame.minX + threshold { return (.leftHalf, screen) }
        if point.x >= frame.maxX - threshold { return (.rightHalf, screen) }
        return nil
    }

    /// The cursor is clamped to the desktop, but `contains` excludes the far
    /// edges of a frame, so fall back to the closest screen instead of
    /// dropping the event.
    private static func screen(containing point: CGPoint) -> NSScreen? {
        if let exact = NSScreen.screens.first(where: { $0.frame.contains(point) }) { return exact }
        return NSScreen.screens.min { lhs, rhs in
            distance(from: point, to: lhs.frame) < distance(from: point, to: rhs.frame)
        }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}
