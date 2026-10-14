import Foundation

/// One line per shortcut that fires, and how it was fired.
///
/// `lastRun` only keeps the latest run per shortcut, so it cannot tell "the key
/// press never arrived" from "it arrived, then something else overwrote it", nor
/// a real key press from an IPC `run`. This file can: each Carbon hotkey event
/// and each IPC run is appended with its source, never overwritten.
enum ShortcutLog {
    static let path = NSString(string: "~/Library/Logs/MacTools-shortcuts.log").expandingTildeInPath

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
