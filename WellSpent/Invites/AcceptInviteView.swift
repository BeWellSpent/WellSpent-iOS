import SwiftUI
import WellSpentAPI

struct AcceptInviteView: View {
    @State private var viewModel: AcceptInviteViewModel
    private let onAccepted: () -> Void
    private let onDismiss: () -> Void

    init(
        token: String,
        publicClient: ProtocolClient,
        authenticatedClient: ProtocolClient,
        onAccepted: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: AcceptInviteViewModel(
            token: token,
            publicClient: publicClient,
            authenticatedClient: authenticatedClient
        ))
        self.onAccepted = onAccepted
        self.onDismiss = onDismiss
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
        onDismiss: {}
    )
}
