import SwiftUI

/// Keeps the latest reading from Mickael's phone in front of him.
///
/// It reads `kited`'s store straight off the disk rather than asking the daemon over HTTP. The
/// two processes run on the same machine under the same user, so a port, a bearer token and a
/// running daemon would all be things that can be wrong for a file this side can simply open.
/// The daemon still has to be alive for the file to grow — but if it is not, the reading goes
/// stale, which is exactly what this screen is supposed to say.
///
/// **Stale is a state, not an absence.** A phone that stopped reporting looks identical to a
/// quiet phone if the last number is left on screen: same figure, no hint that it is frozen. So
/// anything older than `staleAfter` stops being a reading and becomes a dash. That is the same
/// lesson `phone.rs` carries in `kited`, learnt the day a stuck mirror spent four hours looking
/// healthy.
@MainActor
final class PhoneStatsService: ObservableObject {

    /// The most recent sample, whatever its age. `isStale` says whether it still means anything.
    @Published private(set) var latest: PhoneStats?

    /// True when nothing has arrived recently enough to be worth showing as a number.
    @Published private(set) var isStale = true

    /// The newest battery ranking seen, which is almost never on the newest sample.
    ///
    /// Held apart from `latest` on purpose. The phone attaches it every five minutes, so reading
    /// it off the last line alone would show it for one sample in fifteen and blank the rest of
    /// the time — a section that appears and disappears reads as a bug, not as a cadence.
    @Published private(set) var apps: [PhoneStats.AppDrain] = []

    private var timer: Timer?

    /// The phone reports every twenty seconds. Three missed passes is a phone that is off, out
    /// of reach, or a daemon that is down — all of them things to stop pretending about.
    private let staleAfter: TimeInterval = 70

    /// Polling a local file, so this is cheap; it is fast enough that the menu bar never shows a
    /// number more than a few seconds behind what the daemon holds.
    private let interval: TimeInterval = 5

    /// How much of the tail to read. The store is a week of samples and can reach tens of
    /// megabytes, while the answer is always its last line.
    private let tailBytes = 64 * 1024

    private var storeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/kited/stats.jsonl")
    }

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let (sample, ranking) = readLatest()
        latest = sample ?? latest
        if let ranking, !ranking.isEmpty { apps = ranking }
        // Measured against the instant the daemon received it, never against the poll: a reader
        // that ran a second ago proves nothing about a phone that stopped talking last night.
        if let receivedAt = latest?.receivedAt {
            isStale = Date().timeIntervalSince(receivedAt) > staleAfter
        } else {
            isStale = true
        }
    }

    /// The last complete line of the store, decoded.
    ///
    /// Reads a window off the end rather than the whole file, and drops the first fragment in it
    /// because a window that starts mid-line starts on half a JSON object. A file being appended
    /// to while this reads is the ordinary case, not a race to guard against: the worst outcome
    /// is a truncated final line, which fails to parse, and the line before it answers instead.
    private func readLatest() -> (PhoneStats?, [PhoneStats.AppDrain]?) {
        guard let handle = try? FileHandle(forReadingFrom: storeURL) else { return (nil, nil) }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return (nil, nil) }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return (nil, nil) }

        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if start > 0 && !lines.isEmpty { lines.removeFirst() }

        // One pass backwards for both answers: the newest sample of any kind, and the newest one
        // that happens to carry a ranking. They are rarely the same line.
        var newest: PhoneStats?
        var ranking: [PhoneStats.AppDrain]?
        for line in lines.reversed() {
            guard let stats = PhoneStats.decode(line: Data(line)) else { continue }
            if newest == nil { newest = stats }
            if ranking == nil, !stats.apps.isEmpty { ranking = stats.apps }
            if newest != nil, ranking != nil { break }
        }
        return (newest, ranking)
    }
}
