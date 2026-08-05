import AppKit

/// The translucent rectangle showing where the window will land.
///
/// Without it the feature is unusable: you would have to drop the window to
/// find out what it was going to do.
@MainActor
final class SnapOverlay {
    private let window: NSWindow
    private var shownFrame: CGRect?

    init() {
        window = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // The cursor is dragging a window across this thing, it must not exist
        // as far as the event system is concerned.
        window.ignoresMouseEvents = true
        // Above ordinary windows but below menus and alerts.
        window.level = .floating
        // Follows the user across spaces and never steals a place in the
        // window cycle of an LSUIElement app.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView = SnapOverlayView()
    }

    func show(frame: CGRect) {
        guard frame != shownFrame else { return }

        if shownFrame == nil {
            // First appearance: land at the right size, fade in.
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
            animate { $0.alphaValue = 1 }
        } else {
            // Moving between zones: slide, staying visible.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.allowsImplicitAnimation = true
                window.animator().setFrame(frame, display: true)
            }
        }
        shownFrame = frame
    }

    func hide() {
        guard shownFrame != nil else { return }
        shownFrame = nil
        animate { $0.alphaValue = 0 } completion: { [weak window] in
            window?.orderOut(nil)
        }
    }

    private func animate(
        _ body: @escaping (NSWindow) -> Void,
        completion: (() -> Void)? = nil
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            body(window.animator())
        } completionHandler: {
            completion?()
        }
    }
}

/// Draws the preview: a filled rounded rectangle in the user's accent colour.
private final class SnapOverlayView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 12, yRadius: 12)
        NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 3
        path.stroke()
    }
}
