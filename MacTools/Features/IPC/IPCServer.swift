import Foundation

/// The app's control socket, at ~/Library/Application Support/MacTools/ipc.sock.
///
/// One JSON request per connection, one JSON response, connection closed.
/// Driven from a terminal with:
///   echo '{"command":"list"}' | nc -U "$HOME/Library/Application Support/MacTools/ipc.sock"
///
/// Commands: list, add, remove, enable, run, reload — the shortcuts — plus
/// `next-event`, which is not about shortcuts at all. It was called
/// ShortcutsIPCServer while shortcuts were the only thing anybody asked it for.
/// They are not: this app is the one holding the calendar permission on this
/// Mac, so it is the only thing that can answer "when is the next meeting", and
/// Eko asks that through kited.
@MainActor
final class IPCServer {
    private let store: ShortcutStore
    private let calendar: CalendarService
    private var listenSource: DispatchSourceRead?
    private let ioQueue = DispatchQueue(label: "com.micktaiwan.MacTools.ipc")

    init(store: ShortcutStore, calendar: CalendarService) {
        self.store = store
        self.calendar = calendar
    }

    func start() {
        let path = ShortcutStore.socketURL.path
        unlink(path)

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let sunPathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < sunPathCapacity else {
            close(descriptor)
            return
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: sunPathCapacity) { destination in
                for (index, byte) in pathBytes.enumerated() { destination[index] = CChar(byte) }
                destination[pathBytes.count] = 0
            }
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(descriptor, 8) == 0 else {
            close(descriptor)
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
        source.setEventHandler { [weak self] in self?.acceptConnection(on: descriptor) }
        source.setCancelHandler {
            close(descriptor)
            unlink(path)
        }
        source.resume()
        listenSource = source
    }

    func stop() {
        listenSource?.cancel()
        listenSource = nil
    }

    // MARK: - Connection handling

    private func acceptConnection(on descriptor: Int32) {
        let client = accept(descriptor, nil, nil)
        guard client >= 0 else { return }

        ioQueue.async { [weak self] in
            guard let line = Self.readLine(from: client) else {
                close(client)
                return
            }
            Task { @MainActor in
                let response = self?.respond(to: line) ?? Data()
                self?.ioQueue.async {
                    Self.write(response, to: client)
                    close(client)
                }
            }
        }
    }

    private nonisolated static func readLine(from descriptor: Int32) -> Data? {
        var accumulated = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { return accumulated.isEmpty ? nil : accumulated }
            accumulated.append(contentsOf: buffer[0..<count])
            if accumulated.contains(UInt8(ascii: "\n")) { return accumulated }
            if accumulated.count > 1_000_000 { return accumulated }
        }
    }

    private nonisolated static func write(_ data: Data, to descriptor: Int32) {
        var payload = data
        payload.append(UInt8(ascii: "\n"))
        payload.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Foundation.write(descriptor, raw.baseAddress! + offset, raw.count - offset)
                guard written > 0 else { return }
                offset += written
            }
        }
    }

    // MARK: - Commands

    private func respond(to data: Data) -> Data {
        do {
            let request = try JSONDecoder().decode(Request.self, from: data)
            return try encode(handle(request))
        } catch {
            return (try? encode(Response(ok: false, error: error.localizedDescription)))
                ?? Data(#"{"ok":false,"error":"encoding"}"#.utf8)
        }
    }

    private func handle(_ request: Request) throws -> Response {
        switch request.command {
        case "list":
            return Response(ok: true, shortcuts: store.shortcuts.map(descriptor))

        case "add":
            guard let shortcut = request.shortcut else {
                return Response(ok: false, error: "champ 'shortcut' manquant")
            }
            try store.add(shortcut)
            let registrationError = store.registrationErrors[shortcut.id]
            return Response(
                ok: registrationError == nil,
                error: registrationError,
                shortcuts: [descriptor(shortcut)]
            )

        case "remove":
            guard let id = request.id else { return Response(ok: false, error: "champ 'id' manquant") }
            try store.remove(id: id)
            return Response(ok: true)

        case "enable":
            guard let id = request.id else { return Response(ok: false, error: "champ 'id' manquant") }
            try store.setEnabled(request.enabled ?? true, id: id)
            return Response(ok: true, error: store.registrationErrors[id])

        case "run":
            guard let id = request.id else { return Response(ok: false, error: "champ 'id' manquant") }
            // The socket answers immediately; the run result lands in `list`.
            Task { try? await store.run(id: id) }
            return Response(ok: true)

        case "reload":
            store.reload()
            return Response(ok: true, shortcuts: store.shortcuts.map(descriptor))

        case "next-event":
            return nextEvent()

        default:
            return Response(ok: false, error: "commande inconnue : \(request.command)")
        }
    }

    /// The next timed event, as facts rather than as a sentence: the caller
    /// decides how to word it. `minutes` is how long until it starts, rounded
    /// down, and it is never negative here because CalendarService only ever
    /// reports events that have not begun.
    ///
    /// A day with nothing left in it answers `present: false` rather than an
    /// error: no meeting is an answer, and a caller that treated it as a failure
    /// would show a broken screen every evening.
    private func nextEvent() -> Response {
        // Refusing here rather than answering "no meeting" is the whole point:
        // a robot that cannot tell "nothing today" from "this app was never
        // granted the calendar" would show an empty screen either way.
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = calendar.authorizationStatus == .fullAccess
        } else {
            granted = calendar.authorizationStatus == .authorized
        }
        guard granted else {
            return Response(ok: false, error: "MacTools n'a pas accès au calendrier")
        }
        guard let event = calendar.nextEvent, let start = event.startDate else {
            return Response(ok: true, event: EventDescriptor(present: false))
        }

        let minutes = Int(start.timeIntervalSinceNow / 60)
        return Response(
            ok: true,
            event: EventDescriptor(
                present: true,
                title: event.title ?? "(sans titre)",
                start: timeFormatter.string(from: start),
                minutes: minutes,
                startsAt: ISO8601DateFormatter().string(from: start),
                calendar: event.calendar?.title
            )
        )
    }

    private func descriptor(_ shortcut: UserShortcut) -> ShortcutDescriptor {
        let result = store.lastResults[shortcut.id]
        return ShortcutDescriptor(
            id: shortcut.id,
            name: shortcut.name,
            combo: shortcut.combo,
            command: shortcut.action.command,
            enabled: shortcut.enabled,
            registrationError: store.registrationErrors[shortcut.id],
            lastExitCode: result?.exitCode,
            lastOutput: result?.output,
            lastRun: result.map { ISO8601DateFormatter().string(from: $0.date) }
        )
    }

    private func encode(_ response: Response) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(response)
    }

    // MARK: - Wire types

    private struct Request: Decodable {
        let command: String
        let id: String?
        let enabled: Bool?
        let shortcut: UserShortcut?
    }

    private struct ShortcutDescriptor: Encodable {
        let id: String
        let name: String
        let combo: String
        let command: String
        let enabled: Bool
        let registrationError: String?
        let lastExitCode: Int32?
        let lastOutput: String?
        let lastRun: String?
    }

    /// What `next-event` answers with. Every field is a fact; none of them is a
    /// presentation choice. `minutes` is what a countdown is built from, `start`
    /// is the wall clock time in this Mac's locale, and `startsAt` is the same
    /// instant unambiguously, for a caller that wants to do its own arithmetic.
    private struct EventDescriptor: Encodable {
        var present: Bool
        var title: String?
        var start: String?
        var minutes: Int?
        var startsAt: String?
        var calendar: String?
    }

    private struct Response: Encodable {
        var ok: Bool
        var error: String?
        var shortcuts: [ShortcutDescriptor]?
        var event: EventDescriptor?
    }
}
