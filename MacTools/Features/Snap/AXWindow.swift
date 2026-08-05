import AppKit
import ApplicationServices

/// A window belonging to another application, reached through the Accessibility
/// API.
///
/// The whole point of this type is the coordinate flip. Accessibility reports
/// and accepts frames in a space whose origin is the *top-left of the primary
/// screen*, y growing downwards. AppKit uses the bottom-left of that same
/// screen, y growing upwards. Mixing the two silently sends windows to the
/// wrong place, and on a multi-screen setup to the wrong display entirely, so
/// every frame crossing this boundary goes through `flip`.
struct AXWindow {
    let element: AXUIElement

    // MARK: - Finding a window

    /// The window under `point` (AppKit coordinates), or nil when there is
    /// nothing there we are allowed to move.
    static func atPoint(_ point: CGPoint) -> AXWindow? {
        let system = AXUIElementCreateSystemWide()
        // A hung application would otherwise block the drag: every one of these
        // calls is a synchronous round trip into another process.
        AXUIElementSetMessagingTimeout(system, messagingTimeout)

        let flipped = flip(point)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(flipped.x), Float(flipped.y), &hit) == .success,
              let hit else { return nil }

        guard let window = enclosingWindow(of: hit) else { return nil }
        AXUIElementSetMessagingTimeout(window, messagingTimeout)
        return AXWindow(element: window)
    }

    /// Walks up from whatever was hit (a button, a text field, the title bar)
    /// to the window containing it.
    private static func enclosingWindow(of element: AXUIElement) -> AXUIElement? {
        var current = element
        // Bounded on purpose: a malformed hierarchy must not hang the drag.
        for _ in 0..<16 {
            if copyString(current, kAXRoleAttribute) == kAXWindowRole { return current }
            guard let parent = copyElement(current, kAXParentAttribute) else { return nil }
            current = parent
        }
        return nil
    }

    // MARK: - Reading

    /// Frame in AppKit coordinates, or nil when the window will not answer.
    var frame: CGRect? {
        guard let positionValue = AXWindow.copyAXValue(element, kAXPositionAttribute),
              let sizeValue = AXWindow.copyAXValue(element, kAXSizeAttribute) else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }

        return AXWindow.flip(CGRect(origin: origin, size: size))
    }

    /// Whether snapping this window makes sense at all.
    ///
    /// A native full-screen window lives on its own space and ignores position
    /// changes; a window whose position is not settable (some panels, the
    /// desktop itself) would take the size and stay put, which looks like a bug.
    var isSnappable: Bool {
        guard !isFullScreen else { return false }
        return isSettable(kAXPositionAttribute) && isSettable(kAXSizeAttribute)
    }

    private var isFullScreen: Bool {
        // Not exposed as a constant by the SDK, the string is the public name.
        guard let value = AXWindow.copyValue(element, "AXFullScreen") as? Bool else { return false }
        return value
    }

    private func isSettable(_ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }

    // MARK: - Writing

    /// Moves and resizes the window to `target` (AppKit coordinates).
    ///
    /// Size comes first. A window still occupying the whole screen cannot be
    /// moved to the half it is being asked for without overflowing, and some
    /// applications clamp a move that would push them off the display. Shrink
    /// first, place second, then size once more because the move itself can
    /// re-expand a window that snapped back.
    func setFrame(_ target: CGRect) {
        let flipped = AXWindow.flip(target)
        let sizeFirst = setSize(flipped.size)
        let position = setPosition(flipped.origin)
        let sizeAgain = setSize(flipped.size)
        SnapLog.write("  ax [\(appName)] size=\(sizeFirst.rawValue) pos=\(position.rawValue) size2=\(sizeAgain.rawValue)")
    }

    /// Name of the owning application, for the trace: whether a window refuses
    /// to be resized is a property of the app, not of the snapping.
    var appName: String {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return "?" }
        return NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
    }

    @discardableResult
    private func setPosition(_ point: CGPoint) -> AXError {
        var value = point
        guard let axValue = AXValueCreate(.cgPoint, &value) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axValue)
    }

    @discardableResult
    private func setSize(_ size: CGSize) -> AXError {
        var value = size
        guard let axValue = AXValueCreate(.cgSize, &value) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, axValue)
    }

    // MARK: - Coordinate flip

    /// Height of the Accessibility coordinate space: the primary screen, the
    /// one whose AppKit origin is (0, 0), defines it for every display.
    private static var primaryScreenMaxY: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    /// Its own inverse, so the same call converts in both directions.
    static func flip(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenMaxY - point.y)
    }

    static func flip(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenMaxY - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: - Attribute plumbing

    private static let messagingTimeout: Float = 0.25

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        copyValue(element, attribute) as? String
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyValue(element, attribute) else { return nil }
        guard CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func copyAXValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = copyValue(element, attribute) else { return nil }
        guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
