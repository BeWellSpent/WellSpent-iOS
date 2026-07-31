import SwiftUI

/// Rendered but disabled while `FeatureFlags.googleAuthEnabled` is off — same
/// posture as the web app's Google button (`NEXT_PUBLIC_FEATURE_GOOGLE_AUTH`).
/// Wiring real Google OAuth (`GetGoogleAuthURL`/`ExchangeGoogleCode` +
/// `ASWebAuthenticationSession`) is out of scope for this phase; see the
/// project plan's "Risks" section.
struct GoogleAuthButton: View {
    var body: some View {
        Button {
            // Intentionally a no-op until Google OAuth is wired up.
        } label: {
            Label("Continue with Google", systemImage: "g.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!FeatureFlags.googleAuthEnabled)
        .opacity(FeatureFlags.googleAuthEnabled ? 1 : 0.5)
        .accessibilityIdentifier("googleAuthButton")
        .overlay(alignment: .topTrailing) {
            if !FeatureFlags.googleAuthEnabled {
                Text("Coming soon")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .offset(x: 8, y: -10)
            }
        }
    }
}

#Preview {
    GoogleAuthButton()
        .padding()
}
