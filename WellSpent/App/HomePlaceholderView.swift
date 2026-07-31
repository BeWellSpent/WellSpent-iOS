import SwiftUI
import WellSpentAPI

/// Placeholder authenticated screen — Phase 2 replaces this with the real
/// budgets list. Proves login/session/logout work end-to-end for Phase 1.
struct HomePlaceholderView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel: HomeViewModel?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let user = viewModel?.user, !user.isVerified {
                    VerifyEmailBannerView(publicClient: session.publicClient, email: user.email)
                }

                Text("You're logged in.")
                    .font(.title2)
                Text("Budgets are coming in the next phase.")
                    .foregroundStyle(.secondary)

                if viewModel?.isLoading == true {
                    ProgressView()
                }
                if let errorMessage = viewModel?.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()

                Button("Log Out", role: .destructive) {
                    session.endSession()
                }
                .accessibilityIdentifier("logoutButton")
            }
            .padding()
            .navigationTitle("WellSpent")
            // Deliberately no container-level .accessibilityIdentifier here:
            // SwiftUI lets an identifier set on a plain VStack bleed down and
            // override its child buttons' own identifiers (logoutButton,
            // resendVerificationButton both reported as "homePlaceholderView"
            // under XCUITest) — Form/List-backed screens don't have this
            // problem since each row gets independent accessibility identity.
            // UI tests key off logoutButton directly instead.
            .task {
                guard let authenticatedClient = session.authenticatedClient else { return }
                let model = HomeViewModel(authenticatedClient: authenticatedClient)
                viewModel = model
                await model.loadMe()
            }
        }
    }
}
