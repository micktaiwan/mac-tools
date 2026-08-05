import SwiftUI
import EventKit

struct CalendarMailOptionsView: View {
    @ObservedObject var calendarService: CalendarService

    var body: some View {
        OptionsPage(title: "Calendrier et emails") {
            Text("Calendriers affiches")
                .font(.headline)

            if calendarService.calendars.isEmpty {
                Text("Aucun calendrier disponible")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(calendarService.calendars, id: \.calendarIdentifier) { calendar in
                            Toggle(isOn: binding(for: calendar)) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(nsColor: calendar.color ?? .secondaryLabelColor))
                                        .frame(width: 8, height: 8)
                                    Text(calendar.title)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()

            Text("Emails")
                .font(.headline)
            Text("Aucune option pour l'instant")
                .foregroundStyle(.secondary)
        }
    }

    private func binding(for calendar: EKCalendar) -> Binding<Bool> {
        Binding(
            get: { !calendarService.excludedCalendarIDs.contains(calendar.calendarIdentifier) },
            set: { enabled in
                if enabled {
                    calendarService.excludedCalendarIDs.remove(calendar.calendarIdentifier)
                } else {
                    calendarService.excludedCalendarIDs.insert(calendar.calendarIdentifier)
                }
            }
        )
    }
}
