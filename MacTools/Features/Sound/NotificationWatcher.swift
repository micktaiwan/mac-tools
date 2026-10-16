import Foundation

/// Which apps posted a notification allowed to make a sound, as macOS presents them.
///
/// A desktop notification's sound is not played by the app that posted it but by
/// `systemsoundserverd` (measured 15/10/2026 with `display notification … sound name`). Seen from
/// CoreAudio, a Slack ping is a system daemon making noise. The link back to Slack is the
/// notification, which `usernoted` logs at the instant it shows it:
/// `Presenting <NotificationRecord app:"com.tinyspeck.slackmacgap" …> as banner (["badge", "sound", "alert"])`.
///
/// **Why the unified log and not the notification database.** The database
/// (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`) sits in another app's group
/// container: TCC refuses it to MacTools (`kTCCServiceSystemPolicyAppDataDetailed`, no prompt),
/// and only Full Disk Access would open it. `log stream` needs nothing.
@MainActor
final class NotificationWatcher {
    /// bundle ID of the app, and when its notification was presented.
    private(set) var recent: [(bundleID: String, date: Date)] = []
    var onPresented: ((String) -> Void)?

    private var process: Process?
    private var buffer = Data()

    func start() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream", "--style", "ndjson",
            "--predicate", #"process == "usernoted" AND eventMessage BEGINSWITH "Presenting""#,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.consume(data) }
        }
        // `log stream` can die (log daemon restart); a dead watcher would silently stop
        // attributing notification sounds, so it comes back.
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self?.start()
            }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            NSLog("MacTools: log stream failed to start: \(error)")
        }
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    /// Notifications presented within `window` seconds of `date`, newest first.
    func sender(near date: Date, window: TimeInterval = 1.5) -> String? {
        recent.last { abs($0.date.timeIntervalSince(date)) <= window }?.bundleID
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(line)
        }
    }

    private func handle(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let message = object["eventMessage"] as? String,
              let bundleID = Self.appID(in: message),
              message.contains(#""sound""#)
        else { return }
        let now = Date()
        recent.append((bundleID, now))
        recent.removeAll { now.timeIntervalSince($0.date) > 10 }
        onPresented?(bundleID)
    }

    private static func appID(in message: String) -> String? {
        guard let start = message.range(of: #"app:""#) else { return nil }
        let rest = message[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }
}
