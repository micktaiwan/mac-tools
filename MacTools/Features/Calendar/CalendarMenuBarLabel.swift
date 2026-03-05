import EventKit

enum CalendarMenuBarLabel {
    static func formatEvent(_ event: EKEvent) -> String {
        let now = Date()
        let title = event.title ?? "Sans titre"
        let shortTitle = title.count > 20 ? String(title.prefix(20)) + "..." : title

        if Calendar.current.isDateInToday(event.startDate) {
            let minutes = Int(event.startDate.timeIntervalSince(now) / 60)
            if minutes < 60 {
                return "\(minutes)min - \(shortTitle)"
            }
        }

        return "\(timeFormatter.string(from: event.startDate)) \(shortTitle)"
    }
}
