import Foundation
import Security

/// Reads and writes the JWT access token to the Keychain. Every method is a
/// synchronous, thread-safe call into the Security framework (Keychain's C API
/// is inherently thread-safe), so this is safe to call from the networking
/// layer's `TokenProvider` closure on any thread — not just the main actor.
nonisolated final class KeychainTokenStore: Sendable {
    private let service: String

    init(service: String = "com.bewellspent.WellSpent.accessToken") {
        self.service = service
    }

    func readToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(token: String) {
        let data = Data(token.utf8)
        let query = baseQuery()

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    func deleteToken() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }
}
