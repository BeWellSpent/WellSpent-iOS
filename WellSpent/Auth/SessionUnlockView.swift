import SwiftUI

/// Shown when a saved session couldn't be resumed this launch (Face ID
/// declined or failed, device locked, no connection). The session is intact;
/// nothing here has been deleted.
struct SessionUnlockView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "faceid")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Unlock WellSpent")
                .font(.headline)
            Text("We couldn't confirm it's you or reach the server. You're still signed in.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") { session.retryResume() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("retryUnlockButton")
            Button("Log in with password instead") { session.abandonResume() }
                .accessibilityIdentifier("usePasswordButton")
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sessionUnlockView")
    }
}
