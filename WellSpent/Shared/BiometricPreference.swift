import Foundation

/// Whether resuming a session accepts only Face ID/Touch ID, with no device
/// passcode fallback. `@AppStorage`-backed, mirrors `ThemePreference`'s
/// pattern. False (default) keeps today's `.userPresence` Keychain behavior.
nonisolated enum BiometricPreference {
    static let key = "biometricOnlyEnabled"

    static var isEnabled: Bool { isEnabled(in: .standard) }

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: key)
    }

    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key)
    }

    /// The Keychain flag set this preference maps to.
    static var accessControl: RefreshTokenAccessControl { accessControl(in: .standard) }

    static func accessControl(in defaults: UserDefaults) -> RefreshTokenAccessControl {
        isEnabled(in: defaults) ? .biometryCurrentSet : .userPresence
    }
}
