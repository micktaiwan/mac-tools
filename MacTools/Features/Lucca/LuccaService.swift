import Foundation

/// How much of the day a person is off.
enum LuccaDayKind {
    case full
    case morning
    case afternoon

    /// Empty for a full day: a name on its own already means "off today".
    var label: String {
        switch self {
        case .full: return ""
        case .morning: return "matin"
        case .afternoon: return "après-midi"
        }
    }
}

struct LuccaPersonLeave: Identifiable {
    let id: Int
    let name: String
    /// Which halves of *today* the person is off.
    let kind: LuccaDayKind
    /// Last day of the run of leave that started on or before today.
    let until: Date
    /// True when today is that last day, so the person is back tomorrow.
    let isLastDay: Bool
}

struct LuccaTeamLeaves: Identifiable {
    /// The team name is the grouping key, so it is also the identity.
    var id: String { department }
    let department: String
    let people: [LuccaPersonLeave]
}

/// Who is off today, grouped by team, refreshed in the background.
@MainActor
final class LuccaService: ObservableObject {
    @Published private(set) var teams: [LuccaTeamLeaves] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var isConfigured = false

    var totalPeople: Int { teams.reduce(0) { $0 + $1.people.count } }

    /// Shown when a person has no department in Lucca. Always sorted last.
    private static let noDepartment = "(sans équipe)"
    private static let tech = "Tech"

    /// Lucca splits Data (and one day SRE) out of Tech, while in the real org
    /// chart those teams sit under the CTO. Merged back for display.
    private static let techUmbrella: Set<String> = [tech, "Data", "SRE"]

    private var timer: Timer?
    /// Leaves are booked days in advance, so polling often buys nothing.
    private let refreshInterval: TimeInterval = 3 * 60 * 60

    init() {
        LuccaCredentials.importFromDotEnvIfNeeded()
        isConfigured = LuccaCredentials.isConfigured
        start()
    }

    deinit {
        timer?.invalidate()
    }

    private func start() {
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetch() }
        }
    }

    /// Re-reads the settings and refetches. Called when the Options window saves.
    func configurationChanged() {
        isConfigured = LuccaCredentials.isConfigured
        teams = []
        lastUpdate = nil
        fetch()
    }

    func fetch() {
        guard !isLoading else { return }
        guard let client = LuccaCredentials.makeClient() else {
            isConfigured = false
            teams = []
            errorMessage = nil
            return
        }
        isConfigured = true
        isLoading = true

        // The day is resolved at fetch time, so a long-running app rolls over
        // to the next day on its own.
        let now = Date()
        let today = Self.isoDay(now)
        // Only today's absences are listed, but the range runs further out so
        // each of them can be followed to the day the person comes back.
        let horizon = Self.isoDay(now.addingTimeInterval(Double(Self.horizonDays) * 86400))

        Task {
            do {
                async let users = client.fetchUsers()
                async let leaves = client.fetchLeaves(since: today, until: horizon)
                let grouped = Self.group(leaves: try await leaves, users: try await users, today: today)
                teams = grouped
                errorMessage = nil
                lastUpdate = Date()
            } catch {
                // Keep the previous list on screen rather than blanking it: a
                // stale answer plus an error banner beats an empty one.
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    /// Days fetched past today, only to find where each ongoing leave ends.
    /// Long enough for a summer break, short enough to stay a couple of pages.
    private static let horizonDays = 90

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// Local calendar day, not UTC: near midnight the two differ and the wrong
    /// one would ask Lucca for yesterday.
    private static func isoDay(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static func rollup(_ department: String) -> String {
        techUmbrella.contains(department) ? tech : department
    }

    /// Folds the half-days into one entry per person, then groups by team.
    /// Only people off on `today` are listed; the later days serve to find the
    /// last day of their current run of leave.
    static func group(leaves: [RawLeave], users: [Int: LuccaUser], today: String) -> [LuccaTeamLeaves] {
        // ownerId -> day -> which halves are off
        var byOwner: [Int: [String: (morning: Bool, afternoon: Bool)]] = [:]
        for leave in leaves {
            guard let ownerId = leave.ownerId else { continue }
            let day = String(leave.date.prefix(10))
            var days = byOwner[ownerId] ?? [:]
            var entry = days[day] ?? (false, false)
            if leave.isMorning { entry.morning = true } else { entry.afternoon = true }
            days[day] = entry
            byOwner[ownerId] = days
        }

        var byTeam: [String: [LuccaPersonLeave]] = [:]
        for (ownerId, days) in byOwner {
            guard let half = days[today] else { continue }
            let user = users[ownerId]
            let kind: LuccaDayKind = half.morning && half.afternoon ? .full : (half.morning ? .morning : .afternoon)
            let lastDay = endOfRun(from: today, days: Set(days.keys))
            let person = LuccaPersonLeave(
                id: ownerId,
                name: user?.name ?? "#\(ownerId) (inconnu)",
                kind: kind,
                until: dayFormatter.date(from: lastDay) ?? Date(),
                isLastDay: lastDay == today
            )
            let department = rollup(user?.department ?? noDepartment)
            byTeam[department, default: []].append(person)
        }

        return byTeam
            .map { department, people in
                LuccaTeamLeaves(
                    department: department,
                    // Soonest back first: the question is who is coming back, not who is who.
                    people: people.sorted {
                        $0.until == $1.until
                            ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                            : $0.until < $1.until
                    }
                )
            }
            .sorted { a, b in
                if a.department == noDepartment { return false }
                if b.department == noDepartment { return true }
                return a.department.localizedCaseInsensitiveCompare(b.department) == .orderedAscending
            }
    }

    /// Walks forward from `start` and returns the last day of the unbroken run
    /// of leave, the day the person is off for the last time before coming back.
    ///
    /// Weekends are stepped over without ending the run: nobody books leave on a
    /// Saturday, so a Friday-to-Monday absence is one leave, not two. A public
    /// holiday inside a leave has the same shape and does end the run here —
    /// Lucca does not expose them on this endpoint, so the date shown is the day
    /// before the holiday rather than the real return.
    private static func endOfRun(from start: String, days: Set<String>) -> String {
        guard var cursor = dayFormatter.date(from: start) else { return start }
        let calendar = calendar
        var last = start
        // The fetch window bounds the answer; the cap only guards the loop.
        for _ in 0..<(horizonDays + 1) {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            if calendar.isDateInWeekend(next) { continue }
            let day = isoDay(next)
            guard days.contains(day) else { break }
            last = day
        }
        return last
    }
}
