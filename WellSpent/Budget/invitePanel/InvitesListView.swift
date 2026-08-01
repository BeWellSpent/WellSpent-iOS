import SwiftUI
import WellSpentAPI

struct InvitesListView: View {
    @Environment(SessionStore.self) private var session
    let budgetProfileID: String
    let budgetOwnerUserID: String
    let authenticatedClient: ProtocolClient

    @State private var viewModel: InvitesViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Invitations")
        .task {
            if viewModel == nil {
                viewModel = InvitesViewModel(
                    budgetProfileID: budgetProfileID,
                    budgetOwnerUserID: budgetOwnerUserID,
                    currentUserID: session.userID,
                    authenticatedClient: authenticatedClient
                )
            }
            await viewModel?.load()
        }
        .refreshable {
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(viewModel: InvitesViewModel) -> some View {
        List {
            if viewModel.isAdmin {
                sendSection(viewModel: viewModel)
            }

            Section("Invites") {
                if viewModel.invites.isEmpty && viewModel.isLoading {
                    ProgressView()
                } else if viewModel.visibleInvites.isEmpty {
                    Text("No invites yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.visibleInvites, id: \.id) { invite in
                        inviteRow(invite, viewModel: viewModel)
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func sendSection(viewModel: InvitesViewModel) -> some View {
        Section("Send Invite") {
            TextField("Email", text: Binding(
                get: { viewModel.draftEmail },
                set: { viewModel.draftEmail = $0 }
            ))
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("inviteEmailField")

            Picker("Role", selection: Binding(
                get: { viewModel.draftRole },
                set: { viewModel.draftRole = $0 }
            )) {
                Text(BudgetRoleLabel.text(for: .collaborator)).tag(Wellspent_V1_BudgetRole.collaborator)
                Text(BudgetRoleLabel.text(for: .viewer)).tag(Wellspent_V1_BudgetRole.viewer)
            }
            .accessibilityIdentifier("inviteRolePicker")

            if !viewModel.guestPeople.isEmpty {
                Picker("Link to person", selection: Binding(
                    get: { viewModel.draftBudgetPersonID },
                    set: { viewModel.draftBudgetPersonID = $0 }
                )) {
                    Text("No person").tag(Int64(0))
                    ForEach(viewModel.guestPeople, id: \.id) { person in
                        Text(person.userName).tag(person.id)
                    }
                }
                .accessibilityIdentifier("inviteLinkPersonPicker")
            }

            Button {
                Task { await viewModel.send() }
            } label: {
                HStack {
                    Text("Send Invite")
                    if viewModel.isSending {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!viewModel.canSend)
            .accessibilityIdentifier("sendInviteButton")
        }
    }

    private func inviteRow(_ invite: Wellspent_V1_BudgetInvite, viewModel: InvitesViewModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(invite.email)
                HStack(spacing: 4) {
                    Text(BudgetRoleLabel.text(for: invite.role))
                    Text("·")
                    Text(InviteStatusLabel.text(for: invite.status))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isAdmin, invite.status != .accepted {
                Button {
                    Task { await viewModel.resend(invite) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("resendInvite_\(invite.email)")

                if invite.status == .pending {
                    Button {
                        Task { await viewModel.cancel(id: invite.id) }
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("cancelInvite_\(invite.email)")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        InvitesListView(
            budgetProfileID: "preview-budget",
            budgetOwnerUserID: "preview-owner",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }
    .environment(SessionStore())
}
