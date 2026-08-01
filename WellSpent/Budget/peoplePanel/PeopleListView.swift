import SwiftUI
import WellSpentAPI

struct PeopleListView: View {
    let budgetProfileID: String
    let budgetOwnerUserID: String
    let authenticatedClient: ProtocolClient

    @State private var viewModel: PeopleViewModel?
    @State private var editingPerson: Wellspent_V1_BudgetPerson?
    @State private var removingPerson: Wellspent_V1_BudgetPerson?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("People")
        .task {
            if viewModel == nil {
                viewModel = PeopleViewModel(
                    budgetProfileID: budgetProfileID,
                    budgetOwnerUserID: budgetOwnerUserID,
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
    private func content(viewModel: PeopleViewModel) -> some View {
        List {
            Section {
                if viewModel.people.isEmpty && viewModel.isLoading {
                    ProgressView()
                } else if viewModel.people.isEmpty {
                    Text("No people yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.people, id: \.id) { person in
                        personRow(person, viewModel: viewModel)
                    }
                }
            }

            Section("Add person") {
                if viewModel.isAtLimit {
                    Text("Free plan: budgets are limited to 2 people. Upgrade to Pro for unlimited members.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("peopleLimitMessage")
                } else {
                    HStack {
                        TextField("Name", text: Binding(
                            get: { viewModel.newPersonName },
                            set: { viewModel.newPersonName = $0 }
                        ))
                            .accessibilityIdentifier("addPersonNameField")
                        Button("Add") {
                            Task { await viewModel.addPerson() }
                        }
                        .disabled(!viewModel.canAddPerson)
                        .accessibilityIdentifier("addPersonButton")
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { editingPerson != nil },
            set: { if !$0 { editingPerson = nil } }
        )) {
            if let editingPerson {
                EditPersonColorView(person: editingPerson) { color in
                    Task { await viewModel.updateColor(personID: editingPerson.id, color: color) }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { removingPerson != nil },
            set: { if !$0 { removingPerson = nil } }
        )) {
            if let removingPerson {
                RemovePersonView(
                    person: removingPerson,
                    otherPeople: viewModel.people.filter { $0.id != removingPerson.id },
                    needsReplacement: viewModel.needsReplacement(for: removingPerson)
                ) { replacementID in
                    Task { await viewModel.remove(personID: removingPerson.id, replacementPersonID: replacementID) }
                }
            }
        }
    }

    @ViewBuilder
    private func personRow(_ person: Wellspent_V1_BudgetPerson, viewModel: PeopleViewModel) -> some View {
        let isOwner = !viewModel.budgetOwnerUserID.isEmpty && person.userID == viewModel.budgetOwnerUserID
        let canEditRole = !isOwner && !person.userID.isEmpty && person.role != .unspecified

        HStack {
            ColorDotView(hex: person.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(person.userName)
                if isOwner {
                    Text("Owner").font(.caption).foregroundStyle(.secondary)
                } else if person.userID.isEmpty {
                    Text("Pending invite").font(.caption).foregroundStyle(.secondary)
                } else if !canEditRole {
                    Text(BudgetRoleLabel.text(for: person.role)).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if canEditRole {
                Picker("Role", selection: Binding(
                    get: { person.role },
                    set: { newRole in Task { await viewModel.updateRole(personID: person.id, role: newRole) } }
                )) {
                    Text(BudgetRoleLabel.text(for: .admin)).tag(Wellspent_V1_BudgetRole.admin)
                    Text(BudgetRoleLabel.text(for: .collaborator)).tag(Wellspent_V1_BudgetRole.collaborator)
                    Text(BudgetRoleLabel.text(for: .viewer)).tag(Wellspent_V1_BudgetRole.viewer)
                }
                .labelsHidden()
                .accessibilityIdentifier("rolePicker_\(person.id)")
            }

            Button {
                editingPerson = person
            } label: {
                Image(systemName: "paintpalette")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editPersonColor_\(person.id)")
        }
        .swipeActions {
            if !isOwner {
                Button("Remove", role: .destructive) {
                    removingPerson = person
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PeopleListView(
            budgetProfileID: "preview-budget",
            budgetOwnerUserID: "preview-owner",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }
}
