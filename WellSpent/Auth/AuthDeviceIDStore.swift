import Foundation
import Security

/// A client-generated UUID, stable per app install, sent on every auth call to
/// scope the refresh token to this device. Plain Keychain storage (no access
/// control) — must be readable with no prompt, since it's needed to build the
/// very first login/register request, before any session exists.
///
/// Distinct from the APNs push device token (`AppDelegate.onDeviceToken`) —
/// unrelated concept, same "device token" vocabulary by coincidence only.
nonisolated final class AuthDeviceIDStore: Sendable {
    private let service: String

    init(service: String = "com.bewellspent.WellSpent.authDeviceID") {
        self.service = service
    }

    /// Reads the stored ID, generating and persisting one on first call.
    func deviceID() -> String {
        if let existing = read() { return existing }
        let generated = UUID().uuidString
        save(generated)
        return generated
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func save(_ value: String) {
        var attributes = baseQuery()
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }
}
