import Foundation

struct GmailMessage: Identifiable {
    let id: String
    let subject: String
    let from: String
    let snippet: String
    let date: Date
}

@MainActor
final class GmailService: ObservableObject {
    @Published var unreadMessages: [GmailMessage] = []
    @Published var isAvailable: Bool = true
    /// True when the inbox holds at least `maxResults` unread messages, so the
    /// count shown is a floor rather than the real total.
    @Published private(set) var reachedLimit = false

    var unreadCount: Int { unreadMessages.count }

    /// "12", or "50+" when the fetch hit its ceiling.
    var unreadCountLabel: String { "\(unreadCount)\(reachedLimit ? "+" : "")" }

    private var timer: Timer?
    private let maxResults = 50
    private let gwsPath: String
    /// Message details already fetched, kept between polls so each cycle only
    /// spawns a `gws` process for messages it has never seen.
    private var messageCache: [String: GmailMessage] = [:]

    init() {
        gwsPath = Self.findGws() ?? "gws"
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    private static func findGws() -> String? {
        let candidates = [
            "/usr/local/bin/gws",
            "/opt/homebrew/bin/gws",
        ]
        let nvmDir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".nvm/versions/node")
        if let nodeVersions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir.path()) {
            for version in nodeVersions.sorted().reversed() {
                let path = nvmDir.appending(path: "\(version)/bin/gws").path()
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func startMonitoring() {
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetch()
            }
        }
    }

    func fetch() {
        Task {
            await fetchUnread()
        }
    }

    private func fetchUnread() async {
        guard let listData = await runGws(args: [
            "gmail", "users", "messages", "list",
            "--params", "{\"userId\":\"me\",\"q\":\"is:unread in:inbox\",\"maxResults\":\(maxResults)}"
        ]) else {
            isAvailable = false
            return
        }
        guard let listJson = try? JSONSerialization.jsonObject(with: listData) as? [String: Any] else {
            // Unreadable output is not a working Gmail either; saying so beats
            // showing a stale list as if it were current.
            isAvailable = false
            return
        }
        isAvailable = true

        guard let messages = listJson["messages"] as? [[String: Any]] else {
            unreadMessages = []
            messageCache.removeAll()
            reachedLimit = false
            return
        }

        let ids = messages.compactMap { $0["id"] as? String }
        reachedLimit = ids.count >= maxResults

        // Forget messages that have been read or moved elsewhere.
        let stillUnread = Set(ids)
        messageCache = messageCache.filter { stillUnread.contains($0.key) }

        var fetched: [GmailMessage] = []
        for id in ids {
            if let cached = messageCache[id] {
                fetched.append(cached)
                continue
            }
            if let detail = await fetchMessageDetail(id: id) {
                messageCache[id] = detail
                fetched.append(detail)
            }
        }

        unreadMessages = fetched.sorted { $0.date > $1.date }
    }

    private func fetchMessageDetail(id: String) async -> GmailMessage? {
        guard let data = await runGws(args: [
            "gmail", "users", "messages", "get",
            "--params", "{\"userId\":\"me\",\"id\":\"\(id)\",\"format\":\"metadata\"}"
        ]) else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let snippet = json["snippet"] as? String ?? ""
        let internalDate = json["internalDate"] as? String ?? "0"
        let date = Date(timeIntervalSince1970: (Double(internalDate) ?? 0) / 1000)

        var subject = ""
        var from = ""
        if let payload = json["payload"] as? [String: Any],
           let headers = payload["headers"] as? [[String: Any]] {
            for header in headers {
                let name = (header["name"] as? String ?? "").lowercased()
                let value = header["value"] as? String ?? ""
                if name == "subject" { subject = value }
                if name == "from" { from = Self.extractName(from: value) }
            }
        }

        return GmailMessage(id: id, subject: subject, from: from, snippet: snippet, date: date)
    }

    func removeAndTrash(id: String) {
        unreadMessages.removeAll { $0.id == id }
        messageCache[id] = nil
        Task {
            let _ = await runGws(args: [
                "gmail", "users", "messages", "modify",
                "--params", "{\"userId\":\"me\",\"id\":\"\(id)\"}",
                "--json", "{\"addLabelIds\":[\"TRASH\"],\"removeLabelIds\":[\"INBOX\",\"UNREAD\"]}"
            ])
        }
    }

    private static func extractName(from header: String) -> String {
        if let range = header.range(of: "<") {
            let name = header[header.startIndex..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name.replacingOccurrences(of: "\"", with: "") }
        }
        return header
    }

    private func runGws(args: [String]) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [gwsPath] in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: gwsPath)
                process.arguments = args
                // Ensure node is in PATH for gws (#!/usr/bin/env node shebang)
                let gwsDir = URL(fileURLWithPath: gwsPath).deletingLastPathComponent().path
                var env = ProcessInfo.processInfo.environment
                let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
                env["PATH"] = "\(gwsDir):\(existingPath)"
                process.environment = env
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    // Read pipes before waitUntilExit to avoid deadlock if buffer fills
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    let _ = stderr.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0 ? data : nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
