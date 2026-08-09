import AuthenticationServices
import SwiftUI
import WellSpentAPI

/// Sign in with Apple entry point, shown on both Login and Register.
///
/// Uses Apple's own `SignInWithAppleButton` rather than the SF-symbol `Label`
/// treatment `GoogleAuthButton` uses: the Human Interface Guidelines require
/// the official button for this flow, and it comes system-localized, so its
/// title needs no string-catalog entry.
struct AppleAuthButton: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    let publicClient: ProtocolClient

    @State private var coordinator: AppleAuthCoordinator?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task {
                    if coordinator == nil {
                        coordinator = AppleAuthCoordinator(publicClient: publicClient)
                    }
                    await coordinator?.handle(result: result, session: session)
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 44)
            .disabled(coordinator?.isSigningIn == true)
            .accessibilityIdentifier("appleAuthButton")

            if let errorMessage = coordinator?.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("appleAuthErrorMessage")
            }
        }
    }
}

#Preview {
    AppleAuthButton(publicClient: APIClient.makePublicClient(baseURL: "http://localhost:1"))
        .padding()
        .environment(SessionStore())
}
