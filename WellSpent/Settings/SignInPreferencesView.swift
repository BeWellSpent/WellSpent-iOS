import SwiftUI

/// "Face ID Only" — when on, resuming a saved session accepts only Face
/// ID/Touch ID, never the device passcode. Reachable from `SettingsView`.
struct SignInPreferencesView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel = SignInPreferencesViewModel()
    @AppStorage(BiometricPreference.key) private var biometricOnlyEnabled = false

    var body: some View {
        Form {
            Section("Security") {
                Toggle("Face ID Only", isOn: $biometricOnlyEnabled)
                    .disabled(!viewModel.isBiometricHardwareAvailable)
                    .accessibilityIdentifier("biometricOnlyToggle")
                    .onChange(of: biometricOnlyEnabled) {
                        session.applyBiometricPreferenceChange()
                    }

                caption
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sign-In Preferences")
        .task {
            viewModel.refreshBiometricAvailability()
        }
    }

    // Ternary kept outside `Text` — a ternary of string literals resolves to
    // a plain `String` before `Text` ever sees it, which skips localization.
    private var caption: Text {
        viewModel.isBiometricHardwareAvailable
            ? Text("When on, only Face ID can unlock your saved session — your device passcode won't work as a fallback.")
            : Text("Face ID or Touch ID isn't set up on this device.")
    }
}

#Preview {
    NavigationStack {
        SignInPreferencesView()
    }
    .environment(SessionStore())
}
