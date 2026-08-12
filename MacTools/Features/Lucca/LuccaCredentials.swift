import Foundation
import Security

/// Where the Lucca instance URL and API key live.
///
/// The URL is a plain preference; the key is a credential and goes to the
/// Keychain, never to UserDefaults.
enum LuccaCredentials {
    private static let instanceURLKey = "luccaInstanceURL"
    private static let keychainService = "com.micktaiwan.MacTools.lucca"
    private static let keychainAccount = "apiKey"

    /// The `lucca-leaves` CLI already holds both values on this Mac. Reading it
    /// once at first launch saves pasting the key into the Options window; after
    /// that the Keychain is the only source and this file is never read again.
    private static let dotEnvPath = "\(NSHomeDirectory())/projects/perso/lucca/.env"

    static var instanceURL: String {
        get { UserDefaults.standard.string(forKey: instanceURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmed, forKey: instanceURLKey) }
    }

    static var apiKey: String {
        get { readKeychain() ?? "" }
        set { writeKeychain(newValue.trimmed) }
    }

    static var isConfigured: Bool {
        !instanceURL.isEmpty && !apiKey.isEmpty
    }

    /// Builds a client, or nil when either half of the configuration is missing.
    static func makeClient() -> LuccaClient? {
        let urlString = instanceURL
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return nil }
        let key = apiKey
        guard !key.isEmpty else { return nil }
        return LuccaClient(instanceURL: url, apiKey: key)
    }

    /// True when the values came from the CLI's `.env` rather than the Options window.
    private(set) static var importedFromDotEnv = false

    /// Fills empty settings from the `lucca-leaves` `.env`. Never overwrites a
    /// value already set here.
    static func importFromDotEnvIfNeeded() {
        guard !isConfigured else { return }
        guard let raw = try? String(contentsOfFile: dotEnvPath, encoding: .utf8) else { return }

        var values: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<eq]).trimmed
            var value = String(trimmed[trimmed.index(after: eq)...]).trimmed
            if value.count >= 2, (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }

        if instanceURL.isEmpty, let url = values["LUCCA_INSTANCE_URL"], !url.isEmpty {
            instanceURL = url.hasSuffix("/") ? String(url.dropLast()) : url
            importedFromDotEnv = true
        }
        if apiKey.isEmpty, let key = values["LUCCA_API_KEY"], !key.isEmpty {
            apiKey = key
            importedFromDotEnv = true
        }
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var insert = base
        insert[kSecValueData as String] = Data(value.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
