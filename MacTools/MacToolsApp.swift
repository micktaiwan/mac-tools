import SwiftUI
import EventKit
import Combine

@main
struct MacToolsApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let calendarService = CalendarService()
    private let gmailService = GmailService()
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "MacTools")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        let contentView = MenuContentView(
            calendarService: calendarService,
            gmailService: gmailService
        )
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)

        calendarService.$nextEvent
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBar() }
            .store(in: &cancellables)

        gmailService.$unreadMessages
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBar() }
            .store(in: &cancellables)

        // Periodic update for relative time display
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateMenuBar()
        }
    }

    private func updateMenuBar() {
        var title = ""
        if let event = calendarService.nextEvent {
            title = CalendarMenuBarLabel.formatEvent(event)
        }
        if gmailService.unreadCount > 0 {
            if !title.isEmpty { title += "  " }
            title += "✉ \(gmailService.unreadCount)"
        }
        statusItem.button?.title = title
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

struct MenuContentView: View {
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var gmailService: GmailService

    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button {
                    isRefreshing = true
                    calendarService.fetchEvents()
                    gmailService.fetch()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isRefreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 0.5) : .default, value: isRefreshing)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .padding(.top, 4)
            }

            CalendarMenuView(service: calendarService)

            Divider().padding(.vertical, 4)

            HStack {
                Image(systemName: "envelope")
                Text("Emails non lus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if gmailService.unreadCount > 0 {
                    Text("\(gmailService.unreadCount)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.red.opacity(0.8))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            GmailMenuView(service: gmailService)

            Divider().padding(.vertical, 4)

            SettingsSection(service: calendarService)
        }
        .frame(width: 320)
        .padding(.vertical, 4)
    }
}
