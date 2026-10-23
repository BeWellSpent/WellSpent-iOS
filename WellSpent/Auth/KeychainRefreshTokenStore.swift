import Foundation
import LocalAuthentication
import os
import Security

/// Lets `SessionStore` depend on something other than the real Keychain in
/// tests — reading the real store triggers a system Face ID/Touch ID prompt,
/// which a unit test can't answer.
protocol RefreshTokenStoring: Sendable {
    func exists() -> Bool
    func read() async -> String?
    func save(token: String, accessControl: RefreshTokenAccessControl)
    func clear()
}

/// Which Keychain access-control flag set guards the refresh token.
/// `.userPresence` accepts Face ID/Touch ID **or** the device passcode;
/// `.biometryCurrentSet` accepts only the currently-enrolled biometric data,
/// invalidating the item if that enrollment changes (e.g. Face ID
/// re-enrollment) — the conservative choice for a security-motivated
/// biometric-only setting. See `BiometricPreference` for the user-facing toggle.
enum RefreshTokenAccessControl: Sendable, Equatable {
    case userPresence
    case biometryCurrentSet

    var secFlags: SecAccessControlCreateFlags {
        switch self {
        case .userPresence: .userPresence
        case .biometryCurrentSet: .biometryCurrentSet
        }
    }
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
    private let instanceID = UUID().uuidString.prefix(8)
    private static let logger = AppLogger.logger("KeychainRefreshTokenStore")

    init(service: String = "com.bewellspent.WellSpent.refreshToken") {
        self.service = service
        Self.logger.info("instance created id=\(self.instanceID, privacy: .public)")
    }

    /// No-prompt check for whether a refresh token is stored at all.
    func exists() -> Bool {
        SecItemCopyMatching(baseQuery() as CFDictionary, nil) == errSecSuccess
    }

    /// Triggers the biometric/passcode prompt — call off the main actor.
    ///
    /// Evaluates the policy explicitly first and reuses this *already
    /// authenticated* context for the Keychain query below, instead of
    /// handing `SecItemCopyMatching` a bare, unevaluated `LAContext` via
    /// `kSecUseAuthenticationContext`. The latter lets the Keychain run its
    /// own internal re-authentication, which real-device logs showed
    /// re-presenting the Face ID sheet multiple times for a single call
    /// (Simulator never reproduced it) — a context that already passed
    /// evaluation shouldn't trigger that second pass.
    func read() async -> String? {
        let callID = UUID().uuidString.prefix(8)
        Self.logger.info("read() called instanceId=\(self.instanceID, privacy: .public) callId=\(callID, privacy: .public)")
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let context = LAContext()
                let reason = "Unlock WellSpent to resume your session"
                context.localizedReason = reason

                context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                    Self.logger.info("read() policy evaluation instanceId=\(self.instanceID, privacy: .public) callId=\(callID, privacy: .public) success=\(success, privacy: .public) error=\(String(describing: error), privacy: .public)")
                    guard success else {
                        continuation.resume(returning: nil)
                        return
                    }

                    var query = self.baseQuery()
                    query[kSecReturnData as String] = true
                    query[kSecMatchLimit as String] = kSecMatchLimitOne
                    query[kSecUseAuthenticationContext as String] = context

                    var result: AnyObject?
                    let status = SecItemCopyMatching(query as CFDictionary, &result)
                    Self.logger.info("read() finished instanceId=\(self.instanceID, privacy: .public) callId=\(callID, privacy: .public) status=\(status, privacy: .public)")
                    guard status == errSecSuccess, let data = result as? Data else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                }
            }
        }
    }

    /// A new/rotated token never requires authentication to write — only a read does.
    /// `accessControl` only takes effect for a freshly-added item: updating an
    /// already-present one leaves its existing access control untouched, so a
    /// caller that wants to actually change the flag set must `clear()` first.
    func save(token: String, accessControl: RefreshTokenAccessControl) {
        let data = Data(token.utf8)
        let query = baseQuery()

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            guard let secAccessControl = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, accessControl.secFlags, nil
            ) else { return }
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessControl as String] = secAccessControl
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
