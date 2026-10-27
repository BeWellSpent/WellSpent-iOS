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
/// passcode fallback) gate. `exists()` is kept only for tests asserting
/// post-state — `SessionStore` doesn't call it before `read()`.
nonisolated final class KeychainRefreshTokenStore: RefreshTokenStoring, Sendable {
    private let service: String
    private let instanceID = UUID().uuidString.prefix(8)
    private static let logger = AppLogger.logger("KeychainRefreshTokenStore")

    /// The context `read()` last authenticated, so `save()` moments later in
    /// the same cold-start cycle can reuse it instead of prompting again —
    /// confirmed live this cuts cold start from 2 Face ID prompts to 1.
    /// `save()` falls back to its normal prompting path if reuse fails.
    private let lock = NSLock()
    private var recentContext: LAContext?

    init(service: String = "com.bewellspent.WellSpent.refreshToken") {
        self.service = service
        Self.logger.info("instance created id=\(self.instanceID, privacy: .public)")
    }

    /// Whether a refresh token is stored. Can prompt on some devices.
    func exists() -> Bool {
        let status = SecItemCopyMatching(baseQuery() as CFDictionary, nil)
        Self.logger.info("exists() instanceId=\(self.instanceID, privacy: .public) status=\(status, privacy: .public)")
        return status == errSecSuccess
    }

    /// Triggers the biometric/passcode prompt — call off the main actor.
    func read() async -> String? {
        let callID = UUID().uuidString.prefix(8)
        Self.logger.info("read() called instanceId=\(self.instanceID, privacy: .public) callId=\(callID, privacy: .public)")
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let context = LAContext()
                context.localizedReason = "Unlock WellSpent to resume your session"
                context.touchIDAuthenticationAllowableReuseDuration = LATouchIDAuthenticationMaximumAllowableReuseDuration

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
                self.lock.lock()
                self.recentContext = context
                self.lock.unlock()
                continuation.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }

    /// `accessControl` only takes effect on a freshly-added item — updating
    /// an existing one leaves its access control untouched; `clear()` first
    /// to actually change it. Tries update before add to avoid a redundant
    /// existence-check round trip on the common (already-present) path.
    func save(token: String, accessControl: RefreshTokenAccessControl) {
        let data = Data(token.utf8)
        let query = baseQuery()

        lock.lock()
        let reused = recentContext
        lock.unlock()

        var updateStatus: OSStatus = errSecParam // placeholder — not yet attempted
        if let reused {
            var reusedQuery = query
            reusedQuery[kSecUseAuthenticationContext as String] = reused
            updateStatus = SecItemUpdate(reusedQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            Self.logger.info("save() update reused-context instanceId=\(self.instanceID, privacy: .public) status=\(updateStatus, privacy: .public)")
        }

        // Try silently first; only fall back to letting this prompt if the
        // device actually requires it — never skip the write outright.
        if updateStatus != errSecSuccess {
            var silentQuery = query
            silentQuery[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
            updateStatus = SecItemUpdate(silentQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            Self.logger.info("save() update silent instanceId=\(self.instanceID, privacy: .public) status=\(updateStatus, privacy: .public)")
        }

        if updateStatus == errSecInteractionNotAllowed {
            updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            Self.logger.info("save() update interactive instanceId=\(self.instanceID, privacy: .public) status=\(updateStatus, privacy: .public)")
        }

        guard updateStatus == errSecItemNotFound else { return }

        guard let secAccessControl = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, accessControl.secFlags, nil
        ) else { return }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessControl as String] = secAccessControl
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        Self.logger.info("save() add instanceId=\(self.instanceID, privacy: .public) status=\(addStatus, privacy: .public)")
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
