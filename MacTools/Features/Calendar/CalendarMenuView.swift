import SwiftUI
import EventKit
import ServiceManagement

struct CalendarMenuView: View {
    @ObservedObject var service: CalendarService
    @State private var showCalendars = false

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

            Divider().padding(.vertical, 4)

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
        .padding(.top, 8)
    }

    @ViewBuilder
    private var eventsList: some View {
        let now = Date()
        let current = service.todayEvents.filter { $0.startDate <= now && $0.endDate > now }
        let upcoming = service.todayEvents.filter { $0.startDate > now }

        if current.isEmpty && upcoming.isEmpty {
            Text("Aucun evenement aujourd'hui")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        }

        if !current.isEmpty {
            sectionHeader("En cours")
            ForEach(current, id: \.eventIdentifier) { event in
                eventRow(event, isCurrent: true)
            }
        }

        if !upcoming.isEmpty {
            sectionHeader("A venir")
            ForEach(upcoming, id: \.eventIdentifier) { event in
                eventRow(event, isCurrent: false)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 4)
    }

    private func eventRow(_ event: EKEvent, isCurrent: Bool) -> some View {
        Button {
            openInCalendar(event)
        } label: {
            HStack(spacing: 6) {
                if isCurrent {
                    Circle().fill(.red).frame(width: 6, height: 6)
                }
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
