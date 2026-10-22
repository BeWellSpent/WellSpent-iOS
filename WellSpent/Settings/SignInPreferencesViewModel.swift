import Foundation
import LocalAuthentication
import Observation
import os

/// Owns the one piece of logic this screen needs beyond the `BiometricPreference`
/// toggle itself: whether the device even has biometric hardware enrolled.
/// The availability check is injected so it's testable without touching
/// `LAContext`/the real biometric subsystem.
@MainActor
@Observable
final class SignInPreferencesViewModel {
    private(set) var isBiometricHardwareAvailable = true

    private let biometricAvailabilityCheck: () -> Bool
    private static let logger = AppLogger.logger("SignInPreferences")

    init(biometricAvailabilityCheck: @escaping () -> Bool = SignInPreferencesViewModel.defaultBiometricAvailabilityCheck) {
        self.biometricAvailabilityCheck = biometricAvailabilityCheck
    }

    /// Call on every appearance, not just once — a user can enroll Face ID
    /// mid-session and the toggle should unlock without a relaunch.
    func refreshBiometricAvailability() {
        isBiometricHardwareAvailable = biometricAvailabilityCheck()
        if !isBiometricHardwareAvailable {
            Self.logger.info("biometric hardware unavailable — Face ID Only toggle disabled")
        }
    }

    private nonisolated static func defaultBiometricAvailabilityCheck() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
}
