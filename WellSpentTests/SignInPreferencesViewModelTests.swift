import Foundation
import Testing
@testable import WellSpent

@Suite("SignInPreferencesViewModel")
@MainActor
struct SignInPreferencesViewModelTests {
    @Test("defaults to available before the first check runs")
    func defaultsToAvailable() {
        let viewModel = SignInPreferencesViewModel(biometricAvailabilityCheck: { true })
        #expect(viewModel.isBiometricHardwareAvailable)
    }

    @Test("reflects a device with no biometric hardware enrolled")
    func reflectsUnavailableHardware() {
        let viewModel = SignInPreferencesViewModel(biometricAvailabilityCheck: { false })
        viewModel.refreshBiometricAvailability()
        #expect(!viewModel.isBiometricHardwareAvailable)
    }

    @Test("re-checks on every call, not just once")
    func reChecksEveryCall() {
        var available = false
        let viewModel = SignInPreferencesViewModel(biometricAvailabilityCheck: { available })

        viewModel.refreshBiometricAvailability()
        #expect(!viewModel.isBiometricHardwareAvailable)

        available = true
        viewModel.refreshBiometricAvailability()
        #expect(viewModel.isBiometricHardwareAvailable)
    }
}
