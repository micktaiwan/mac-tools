import SwiftUI
import EventKit

struct CalendarMenuBarLabel: View {
    @ObservedObject var service: CalendarService

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
            if let event = service.nextEvent {
                Text(formatEvent(event))
            }
        }
    }

    private func formatEvent(_ event: EKEvent) -> String {
        let now = Date()
        let title = event.title ?? "Sans titre"
        let shortTitle = title.count > 20 ? String(title.prefix(20)) + "..." : title

        if event.startDate <= now && event.endDate > now {
            let remaining = Int(event.endDate.timeIntervalSince(now) / 60)
            return "\(shortTitle) (\(remaining)min)"
        }

        let minutes = Int(event.startDate.timeIntervalSince(now) / 60)
        if minutes < 60 {
            return "\(minutes)min - \(shortTitle)"
        }

        return "\(timeFormatter.string(from: event.startDate)) \(shortTitle)"
    }
}
