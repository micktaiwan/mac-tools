import EventKit
import SwiftUI

private let excludedCalendarIDsKey = "excludedCalendarIDs"

let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()

@MainActor
final class CalendarService: ObservableObject {
    private let store = EKEventStore()
    private var timer: Timer?
    private var notificationObserver: Any?

    @Published var nextEvent: EKEvent?
    @Published var displayedEvents: [EKEvent] = []
    @Published var displayedEventsDate: Date?
    @Published var calendars: [EKCalendar] = []
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var excludedCalendarIDs: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(excludedCalendarIDs), forKey: excludedCalendarIDsKey)
            fetchEvents()
        }
    }

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: excludedCalendarIDsKey) {
            excludedCalendarIDs = Set(saved)
        }
        requestAccess()
    }

    deinit {
        timer?.invalidate()
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func requestAccess() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)

        guard authorizationStatus != .denied else { return }

        let handler: (Bool) -> Void = { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                if granted {
                    self.startMonitoring()
                    self.fetchEvents()
                }
            }
        }

        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, _ in handler(granted) }
        } else {
            store.requestAccess(to: .event) { granted, _ in handler(granted) }
        }
    }

    private func startMonitoring() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchEvents()
            }
        }

        notificationObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fetchEvents()
            }
        }
    }

    func fetchEvents() {
        calendars = store.calendars(for: .event)

        let now = Date()
        let cal = Calendar.current
        let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        let activeCalendars = calendars.filter { !excludedCalendarIDs.contains($0.calendarIdentifier) }
        let calendarsParam = activeCalendars.isEmpty ? nil : activeCalendars

        let isTimedEvent: (EKEvent) -> Bool = { !$0.isAllDay && $0.startDate != $0.endDate }

        let todayPredicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: calendarsParam)
        let filtered = store.events(matching: todayPredicate)
            .filter { isTimedEvent($0) && $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }

        if !filtered.isEmpty {
            displayedEvents = filtered
            displayedEventsDate = nil
            nextEvent = filtered.first
        } else {
            displayedEvents = []
            displayedEventsDate = nil
            nextEvent = nil

            var searchStart = endOfDay
            for _ in 1...14 {
                let searchEnd = cal.date(byAdding: .day, value: 1, to: searchStart)!
                let predicate = store.predicateForEvents(withStart: searchStart, end: searchEnd, calendars: calendarsParam)
                let dayEvents = store.events(matching: predicate)
                    .filter(isTimedEvent)
                    .sorted { $0.startDate < $1.startDate }
                if !dayEvents.isEmpty {
                    displayedEvents = dayEvents
                    displayedEventsDate = searchStart
                    nextEvent = dayEvents.first
                    break
                }
                searchStart = searchEnd
            }
        }
    }
}
