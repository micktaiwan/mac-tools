import SwiftUI

@main
struct MacToolsApp: App {
    @StateObject private var calendarService = CalendarService()

    var body: some Scene {
        MenuBarExtra {
            CalendarMenuView(service: calendarService)
                .frame(width: 300)
        } label: {
            CalendarMenuBarLabel(service: calendarService)
        }
        .menuBarExtraStyle(.window)
    }
}
