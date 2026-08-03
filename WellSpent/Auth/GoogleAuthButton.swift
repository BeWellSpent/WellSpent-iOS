import SwiftUI
import WellSpentAPI

/// Rendered disabled with a "Coming soon" badge while
/// `FeatureFlags.googleAuthEnabled` is off (Debug builds) — see
/// `GoogleAuthCoordinator` for the real sign-in flow, on in Release builds.
struct GoogleAuthButton: View {
    @Environment(SessionStore.self) private var session
    let publicClient: ProtocolClient

    @State private var coordinator: GoogleAuthCoordinator?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                Task {
                    if coordinator == nil {
                        coordinator = GoogleAuthCoordinator(publicClient: publicClient)
                    }
                    await coordinator?.signIn(session: session)
                }
            } label: {
                HStack {
                    Label("Continue with Google", systemImage: "g.circle")
                        .frame(maxWidth: .infinity)
                    if coordinator?.isSigningIn == true {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(!FeatureFlags.googleAuthEnabled || coordinator?.isSigningIn == true)
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

            if let errorMessage = coordinator?.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("googleAuthErrorMessage")
            }
        }
    }
}

#Preview {
    GoogleAuthButton(publicClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
        .padding()
        .environment(SessionStore())
}
