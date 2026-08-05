import Foundation

/// Append-only trace of a drag, off unless asked for.
///
/// Snapping cannot be debugged from the outside: the interesting facts are the
/// cursor path, which zone each sample resolved to, and what the window did
/// when the frame was applied. Printing to stderr is not an option because it
/// is lost when the app is launched the normal way, and the app has to be
/// launched the normal way or macOS refuses it the Accessibility right.
///
/// `defaults write com.micktaiwan.MacTools debugSnapLog -bool YES`
enum SnapLog {
    static let path = NSString(string: "~/Library/Logs/MacTools-snap.log").expandingTildeInPath

    private static let isEnabled = UserDefaults.standard.bool(forKey: "debugSnapLog")
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func write(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = "\(formatter.string(from: Date())) \(message())\n"
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
