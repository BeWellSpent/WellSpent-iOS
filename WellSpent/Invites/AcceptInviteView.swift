import SwiftUI
import WellSpentAPI

struct AcceptInviteView: View {
    @State private var viewModel: AcceptInviteViewModel
    /// `nil` when the invite link was opened while unauthenticated — the
    /// view shows Sign In/Register buttons instead of an Accept button.
    private let isAuthenticated: Bool
    private let onAccepted: () -> Void
    /// Toolbar "Close" — a true cancel, forgets the pending invite entirely.
    private let onDismiss: () -> Void
    /// Sign In / Register CTAs — hides this screen so the caller's own
    /// login/register UI underneath becomes reachable, *without* forgetting
    /// the pending invite (the caller re-presents this same screen once
    /// authenticated).
    private let onRequestAuth: () -> Void

    init(
        token: String,
        publicClient: ProtocolClient,
        authenticatedClient: ProtocolClient?,
        onAccepted: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onRequestAuth: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: AcceptInviteViewModel(
            token: token,
            publicClient: publicClient,
            authenticatedClient: authenticatedClient
        ))
        self.isAuthenticated = authenticatedClient != nil
        self.onAccepted = onAccepted
        self.onDismiss = onDismiss
        self.onRequestAuth = onRequestAuth
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.invite == nil {
                    ProgressView()
                } else if let invite = viewModel.invite {
                    content(invite)
                } else {
                    Text(viewModel.errorMessage ?? "That invite link isn't valid.")
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .navigationTitle("Budget Invite")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDismiss() }
                        .accessibilityIdentifier("closeAcceptInviteButton")
                }
            }
            .task {
                await viewModel.load()
            }
            .onChange(of: viewModel.acceptedBudgetProfileID) { _, newValue in
                if newValue != nil { onAccepted() }
            }
        }
    }

    @ViewBuilder
    private func content(_ invite: Wellspent_V1_BudgetInvite) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(invite.budgetName)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("\(invite.inviterName) invited you as \(BudgetRoleLabel.text(for: invite.role))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if invite.hasExpiresAt {
                    Text("Expires \(invite.expiresAt.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .accessibilityIdentifier("acceptInvitePreview")

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("acceptInviteErrorMessage")
            }

            if isAuthenticated {
                Button {
                    Task { await viewModel.accept() }
                } label: {
                    HStack {
                        Text("Accept Invite")
                        if viewModel.isAccepting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isAccepting)
                .accessibilityIdentifier("acceptInviteButton")
            } else {
                Text("Sign in or create an account to accept")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Sign In") {
                    onRequestAuth()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("acceptInviteSignInButton")

                Button("Register") {
                    onRequestAuth()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("acceptInviteRegisterButton")
            }

            Spacer()
        }
        .padding()
    }
}

#Preview {
    AcceptInviteView(
        token: "preview-token",
        publicClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
        authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1"),
        onAccepted: {},
        onDismiss: {},
        onRequestAuth: {}
    )
}
