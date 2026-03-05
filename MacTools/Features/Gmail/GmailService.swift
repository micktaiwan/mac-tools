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

    var unreadCount: Int { unreadMessages.count }

    private var timer: Timer?
    private let maxResults = 10
    private let gwsPath: String

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
        isAvailable = true

        guard let listJson = try? JSONSerialization.jsonObject(with: listData) as? [String: Any] else { return }

        guard let messages = listJson["messages"] as? [[String: Any]] else {
            unreadMessages = []
            return
        }

        var fetched: [GmailMessage] = []
        for msg in messages {
            guard let msgId = msg["id"] as? String else { continue }
            if let detail = await fetchMessageDetail(id: msgId) {
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
