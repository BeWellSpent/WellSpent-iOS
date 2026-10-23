import Foundation
import Testing
@testable import WellSpent

/// Pure preference-to-flag mapping — no Keychain/LocalAuthentication involved.
@Suite("BiometricPreference")
struct BiometricPreferenceTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.bewellspent.WellSpent.tests.biometricPreference.\(UUID().uuidString)")!
    }

    @Test("defaults to disabled, mapping to userPresence")
    func defaultsToUserPresence() {
        let defaults = makeDefaults()
        #expect(!BiometricPreference.isEnabled(in: defaults))
        #expect(BiometricPreference.accessControl(in: defaults) == .userPresence)
    }

    @Test("enabling maps to biometryCurrentSet")
    func enabledMapsToBiometryCurrentSet() {
        let defaults = makeDefaults()
        BiometricPreference.setEnabled(true, in: defaults)
        #expect(BiometricPreference.isEnabled(in: defaults))
        #expect(BiometricPreference.accessControl(in: defaults) == .biometryCurrentSet)
    }

    @Test("disabling after enabling maps back to userPresence")
    func disablingMapsBackToUserPresence() {
        let defaults = makeDefaults()
        BiometricPreference.setEnabled(true, in: defaults)
        BiometricPreference.setEnabled(false, in: defaults)
        #expect(BiometricPreference.accessControl(in: defaults) == .userPresence)
    }
}
