import Foundation

/// Minimal client for Lucca's v3 API (Timmi Absences module).
///
/// API v3 conventions:
///  - auth through the `Authorization: lucca application={apiKey}` header
///  - collections come back as `{ data: { items: [...] } }`
///  - paging through `paging={offset},{limit}`
///  - field selection through `fields=a,b,c`
///
/// Ported from the `lucca-leaves` Node tool (`~/projects/perso/lucca`), which
/// stays the reference for the endpoints and their quirks.
struct LuccaClient {
    let instanceURL: URL
    let apiKey: String

    /// One page of a v3 collection.
    private struct Collection<T: Decodable>: Decodable {
        struct Payload: Decodable { let items: [T]? }
        let data: Payload?
    }

    private func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> [T] {
        guard var components = URLComponents(url: instanceURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw LuccaError.badInstanceURL
        }
        components.queryItems = query
        guard let url = components.url else { throw LuccaError.badInstanceURL }

        var request = URLRequest(url: url)
        request.setValue("lucca application=\(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LuccaError.http(status: -1, path: path) }
        guard (200..<300).contains(http.statusCode) else {
            throw LuccaError.http(status: http.statusCode, path: path)
        }
        return try JSONDecoder().decode(Collection<T>.self, from: data).data?.items ?? []
    }

    /// Walks the pagination until a short page comes back.
    private func getAll<T: Decodable>(path: String, query: [URLQueryItem], pageSize: Int = 1000) async throws -> [T] {
        var items: [T] = []
        var offset = 0
        while true {
            var paged = query
            paged.append(URLQueryItem(name: "paging", value: "\(offset),\(pageSize)"))
            let page: [T] = try await get(path: path, query: paged)
            items.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }
        return items
    }

    /// Directory of every Lucca user, keyed by the id leaves refer to.
    func fetchUsers() async throws -> [Int: LuccaUser] {
        let raw: [RawUser] = try await getAll(
            path: "/api/v3/users",
            query: [URLQueryItem(name: "fields", value: "id,name,mail,department.name")]
        )
        var users: [Int: LuccaUser] = [:]
        for user in raw {
            users[user.id] = LuccaUser(
                id: user.id,
                name: user.name,
                mail: user.mail,
                department: user.department?.name
            )
        }
        return users
    }

    /// Every user's half-days off over an inclusive date range.
    func fetchLeaves(since: String, until: String) async throws -> [RawLeave] {
        try await getAll(
            path: "/api/v3/leaves",
            query: [
                URLQueryItem(name: "leavePeriod.ownerId", value: "notequal,0"),
                URLQueryItem(name: "date", value: "between,\(since),\(until)"),
                URLQueryItem(name: "fields", value: "id,date,isAM,leavePeriod[ownerId]"),
            ]
        )
    }
}

enum LuccaError: LocalizedError {
    case notConfigured
    case badInstanceURL
    case http(status: Int, path: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Lucca non configuré (URL d'instance ou clé API manquante)"
        case .badInstanceURL:
            return "URL d'instance Lucca invalide"
        case .http(let status, let path):
            return "Lucca a répondu \(status) sur \(path)"
        }
    }
}

struct LuccaUser {
    let id: Int
    let name: String
    let mail: String?
    /// Direct department name, which is what Lucca calls a team ("Tech", "Product"…).
    let department: String?
}

private struct RawUser: Decodable {
    struct Department: Decodable { let name: String? }
    let id: Int
    let name: String
    let mail: String?
    let department: Department?
}

/// One Lucca leave is a half-day: `isAM` true is the morning, false the afternoon.
struct RawLeave: Decodable {
    let date: String
    let isMorning: Bool
    let ownerId: Int?

    private struct LeavePeriod: Decodable { let ownerId: Int? }

    private enum CodingKeys: String, CodingKey {
        case date
        case isAM
        case isAm
        case leavePeriod
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        // Lucca spells this field `isAM` on some versions and `isAm` on others.
        let upper = try container.decodeIfPresent(Bool.self, forKey: .isAM)
        let lower = try container.decodeIfPresent(Bool.self, forKey: .isAm)
        isMorning = (upper ?? lower) == true
        ownerId = try container.decodeIfPresent(LeavePeriod.self, forKey: .leavePeriod)?.ownerId
    }
}
