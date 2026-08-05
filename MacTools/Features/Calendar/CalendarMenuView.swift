import SwiftUI
import EventKit

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

/// Settings live in the Options window; the popover keeps only Quit.
struct SettingsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Quitter") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}
