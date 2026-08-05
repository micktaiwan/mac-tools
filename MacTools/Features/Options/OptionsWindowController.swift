import AppKit
import SwiftUI

/// Owns the single Options window. The app is LSUIElement, so showing a window
/// also requires activating the app to bring it to the front.
@MainActor
final class OptionsWindowController {
    private let calendarService: CalendarService
    private let shortcutStore: ShortcutStore
    private let snapService: SnapService
    private var window: NSWindow?

    init(calendarService: CalendarService, shortcutStore: ShortcutStore, snapService: SnapService) {
        self.calendarService = calendarService
        self.shortcutStore = shortcutStore
        self.snapService = snapService
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        window?.makeKeyAndOrderFront(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Options"
        // Debug hook: `defaults write com.micktaiwan.MacTools debugOpenOptionsTab snap`
        // opens the window straight on that tab at launch, so a page can be
        // iterated on without clicking through the UI every build.
        let initialTab = UserDefaults.standard.string(forKey: "debugOpenOptionsTab")
            .flatMap(OptionsWindowView.Tab.init(rawValue:)) ?? .general
        let rootView = OptionsWindowView(
            calendarService: calendarService,
            shortcutStore: shortcutStore,
            snapService: snapService,
            initialTab: initialTab
        )
        window.contentView = NSHostingView(rootView: rootView)
        // Keep the instance alive across closes so state is preserved.
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("OptionsWindow")
        return window
    }
}
