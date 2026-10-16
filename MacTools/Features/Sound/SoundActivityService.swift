import AppKit
import CoreAudio

/// One application that played sound recently.
struct RecentSoundApp: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let lastHeard: Date
    let isPlaying: Bool

    var id: String { bundleID }
}

/// Which applications played sound on this Mac lately, newest first.
///
/// CoreAudio (macOS 14.2+) exposes one object per process that holds an audio connection, with a
/// flag saying whether it is producing output right now. Most of those processes are not the app
/// a person thinks of: Slack plays through "Slack Helper", Safari and Mira through a WebKit GPU
/// process. Each one is therefore folded onto the process macOS holds *responsible* for it, which
/// is the app with the Dock icon.
///
/// **Polled, fast.** A property listener on `kAudioProcessPropertyIsRunningOutput` registers
/// without error and never fires (measured 15/10/2026: zero callbacks while `afplay` played, a
/// 0.2 s poll saw it 12 times). Only the process *list* notifies. A notification ping lasts half a
/// second, hence a quarter-second poll: ~35 property reads, cheap.
///
/// **"Running output" means an open output stream, not an audible one.** An app that keeps an
/// `AVAudioEngine` started between sounds (track did) reads as playing forever. There is no
/// public per-process level short of a process tap, which needs the audio-capture permission.
///
/// The history is kept in UserDefaults, because the app is relaunched after every build and an
/// empty list right after a restart would read as "nothing played".
@MainActor
final class SoundActivityService: ObservableObject {
    @Published private(set) var apps: [RecentSoundApp] = []

    /// False below macOS 14.2, where the process objects do not exist.
    let isSupported: Bool

    private let maxEntries = 8
    private let defaultsKey = "soundActivityLastHeard"

    /// bundle ID → last time it was heard.
    private var lastHeard: [String: Date] = [:]
    private var names: [String: String] = [:]
    /// Bundle IDs producing output at this instant, keyed by audio process object.
    private var playingByObject: [AudioObjectID: String] = [:]
    private var timer: Timer?
    /// `systemsoundserverd` objects currently producing output, so one sound is attributed once.
    private var systemSoundObjects = Set<AudioObjectID>()
    /// When the current system sound started, until a notification claims it.
    private var pendingSystemSound: Date?
    private let notifications = NotificationWatcher()
    private let pollInterval: TimeInterval = 0.25

    init() {
        if #available(macOS 14.2, *) {
            isSupported = true
        } else {
            isSupported = false
        }
        loadHistory()
        guard isSupported else { return }
        if #available(macOS 14.2, *) {
            notifications.onPresented = { [weak self] in self?.notificationPresented($0) }
            notifications.start()
            poll()
            timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
        }
    }

    /// Brings the app to the front, or launches it if it has quit since.
    func focus(_ app: RecentSoundApp) {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first {
            running.unhide()
            running.activate(options: [.activateAllWindows])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - CoreAudio

    @available(macOS 14.2, *)
    private func poll() {
        var changed = false
        let objects = Self.processObjects()
        let alive = Set(objects)
        // A process that quit while playing must not stay "playing" forever.
        for (object, bundleID) in playingByObject where !alive.contains(object) {
            playingByObject[object] = nil
            lastHeard[bundleID] = Date()
            changed = true
        }
        for object in objects {
            if Self.isRunningOutput(object) {
                if let bundleID = playingByObject[object] {
                    lastHeard[bundleID] = Date()
                } else if let owner = owningApp(of: object) {
                    playingByObject[object] = owner.bundleID
                    names[owner.bundleID] = owner.name
                    lastHeard[owner.bundleID] = Date()
                    changed = true
                } else if !systemSoundObjects.contains(object), Self.bundleID(of: object) == "systemsoundserverd" {
                    systemSoundObjects.insert(object)
                    attributeNotificationSound()
                }
            } else if let bundleID = playingByObject.removeValue(forKey: object) {
                // Stopping is also a moment it was heard: the list says when the sound ended.
                lastHeard[bundleID] = Date()
                changed = true
            } else {
                systemSoundObjects.remove(object)
            }
        }
        // While something plays only its timestamp moves; republishing four times a second for
        // that would redraw the popover for nothing, so only start, stop and order matter.
        if changed { publish() }
    }

    /// A notification sound is played by `systemsoundserverd`, never by the app that posted the
    /// notification. It is credited to the app whose notification macOS presented within a second
    /// and a half of it, whichever of the two arrives first: `log stream` can lag the sound. A
    /// system sound with no notification next to it (a beep, a screenshot) stays unattributed.
    private func attributeNotificationSound() {
        let started = Date()
        if let bundleID = notifications.sender(near: started) {
            credit(bundleID)
        } else {
            pendingSystemSound = started
        }
    }

    private func notificationPresented(_ bundleID: String) {
        guard let started = pendingSystemSound, Date().timeIntervalSince(started) <= 1.5 else { return }
        pendingSystemSound = nil
        credit(bundleID)
    }

    private func credit(_ bundleID: String) {
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        lastHeard[bundleID] = Date()
        publish()
    }

    @available(macOS 14.2, *)
    private static func bundleID(of object: AudioObjectID) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = address(kAudioProcessPropertyBundleID)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() else { return nil }
        return string as String
    }

    @available(macOS 14.2, *)
    private static func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = address(kAudioProcessPropertyIsRunningOutput)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    /// The user-facing app behind an audio process, or nil for a system daemon.
    @available(macOS 14.2, *)
    private func owningApp(of object: AudioObjectID) -> (bundleID: String, name: String)? {
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        var address = Self.address(kAudioProcessPropertyPID)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr, pid > 0 else {
            return nil
        }
        let responsible = Self.responsiblePID(for: pid)
        guard let app = NSRunningApplication(processIdentifier: responsible)
                ?? NSRunningApplication(processIdentifier: pid),
              app.activationPolicy != .prohibited,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier
        else { return nil }
        return (bundleID, app.localizedName ?? bundleID)
    }

    @available(macOS 14.2, *)
    private static func processObjects() -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// The process macOS holds responsible for `pid`: the host app of an XPC helper.
    ///
    /// A private libSystem call, looked up at runtime so a future macOS without it degrades to
    /// "the process itself" instead of crashing. The parent PID is no substitute: XPC services
    /// such as WebKit's GPU process are children of launchd.
    private static let responsibleFunction: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    private static func responsiblePID(for pid: pid_t) -> pid_t {
        guard let function = responsibleFunction else { return pid }
        let responsible = function(pid)
        return responsible > 0 ? responsible : pid
    }

    // MARK: - State

    private func publish() {
        let playing = Set(playingByObject.values)
        let next = lastHeard
            .sorted { $0.value > $1.value }
            .prefix(maxEntries)
            .map { bundleID, date in
                RecentSoundApp(
                    bundleID: bundleID,
                    name: names[bundleID] ?? Self.displayName(for: bundleID),
                    lastHeard: date,
                    isPlaying: playing.contains(bundleID)
                )
            }
        // Older entries are dropped from storage too, so the history stays bounded.
        let kept = Set(next.map(\.bundleID))
        lastHeard = lastHeard.filter { kept.contains($0.key) }
        if next != apps {
            apps = next
            saveHistory()
        }
    }

    private static func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func loadHistory() {
        guard let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] else { return }
        lastHeard = stored.mapValues { Date(timeIntervalSince1970: $0) }
        publish()
    }

    private func saveHistory() {
        UserDefaults.standard.set(lastHeard.mapValues { $0.timeIntervalSince1970 }, forKey: defaultsKey)
    }
}
