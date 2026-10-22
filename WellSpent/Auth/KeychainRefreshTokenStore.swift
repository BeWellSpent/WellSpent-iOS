import Foundation
import LocalAuthentication
import Security

/// Lets `SessionStore` depend on something other than the real Keychain in
/// tests — reading the real store triggers a system Face ID/Touch ID prompt,
/// which a unit test can't answer.
protocol RefreshTokenStoring: Sendable {
    func exists() -> Bool
    func read() async -> String?
    func save(token: String)
    func clear()
}

/// Stores the refresh token behind a biometric (Face ID/Touch ID, device
/// passcode fallback) gate. Two asymmetries make this usable:
///
/// - **Writing never prompts** — only a query that asks for the actual secret
///   (`kSecReturnData`) triggers Face ID/Touch ID; a plain existence check or a
///   data update on an already-present item doesn't.
/// - **`exists()` never prompts either**, for the same reason — used at
///   `SessionStore.init` to decide whether resuming is worth attempting at all.
nonisolated final class KeychainRefreshTokenStore: RefreshTokenStoring, Sendable {
    private let service: String

    init(service: String = "com.bewellspent.WellSpent.refreshToken") {
        self.service = service
    }

    /// No-prompt check for whether a refresh token is stored at all.
    func exists() -> Bool {
        SecItemCopyMatching(baseQuery() as CFDictionary, nil) == errSecSuccess
    }

    /// Triggers the biometric/passcode prompt — call off the main actor.
    func read() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let context = LAContext()
                context.localizedReason = "Unlock WellSpent to resume your session"

                var query = self.baseQuery()
                query[kSecReturnData as String] = true
                query[kSecMatchLimit as String] = kSecMatchLimitOne
                query[kSecUseAuthenticationContext as String] = context

                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                guard status == errSecSuccess, let data = result as? Data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }

    /// A new/rotated token never requires authentication to write — only a read does.
    func save(token: String) {
        let data = Data(token.utf8)
        let query = baseQuery()

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            guard let accessControl = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil
            ) else { return }
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessControl as String] = accessControl
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }
}
