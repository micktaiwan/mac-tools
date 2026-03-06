import SwiftUI
import EventKit
import ServiceManagement

struct CalendarMenuView: View {
    @ObservedObject var service: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch service.authorizationStatus {
            case .fullAccess:
                eventsList
            case .denied, .restricted:
                Text("Acces calendrier refuse")
                    .padding(.horizontal, 12)
                Button("Ouvrir Preferences Systeme") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
                .padding(.horizontal, 12)
            default:
                Text("Autorisation en cours...")
                    .padding(.horizontal, 12)
                Button("Autoriser") { service.requestAccess() }
                    .padding(.horizontal, 12)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var eventsList: some View {
        if service.displayedEvents.isEmpty {
            Text("Aucun evenement a venir")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        } else {
            if let date = service.displayedEventsDate {
                Text(formatDayLabel(date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)
            }
            ForEach(service.displayedEvents, id: \.eventIdentifier) { event in
                eventRow(event)
            }
        }
    }

    private func formatDayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: date).capitalized
    }

    private func eventRow(_ event: EKEvent) -> some View {
        Button {
            openInCalendar(event)
        } label: {
            HStack(spacing: 6) {
                Text(formatTime(event))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(event.title ?? "Sans titre")
                    .lineLimit(1)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private func formatTime(_ event: EKEvent) -> String {
        "\(timeFormatter.string(from: event.startDate)) - \(timeFormatter.string(from: event.endDate))"
    }

    private func openInCalendar(_ event: EKEvent) {
        let url = URL(string: "ical://ekevent/\(event.eventIdentifier ?? "")?method=show&options=more")
            ?? URL(string: "ical://")!
        NSWorkspace.shared.open(url)
    }
}

struct SettingsSection: View {
    @ObservedObject var service: CalendarService
    @State private var showCalendars = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation { showCalendars.toggle() }
            } label: {
                HStack {
                    Text("Calendriers")
                    Spacer()
                    Image(systemName: showCalendars ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            if showCalendars {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(service.calendars, id: \.calendarIdentifier) { calendar in
                        Toggle(calendar.title, isOn: Binding(
                            get: { !service.excludedCalendarIDs.contains(calendar.calendarIdentifier) },
                            set: { enabled in
                                if enabled {
                                    service.excludedCalendarIDs.remove(calendar.calendarIdentifier)
                                } else {
                                    service.excludedCalendarIDs.insert(calendar.calendarIdentifier)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }

            Divider().padding(.vertical, 4)

            Toggle("Lancer au demarrage", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { enable in
                    try? enable ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
            ))
            .toggleStyle(.checkbox)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)

            Divider().padding(.vertical, 4)

            Button("Quitter") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}
