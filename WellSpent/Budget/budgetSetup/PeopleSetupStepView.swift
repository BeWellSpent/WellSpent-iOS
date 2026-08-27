import SwiftUI
import WellSpentAPI

/// Step 1 of `BudgetSetupFlow`. Each "Add" tap is its own immediate
/// `AddBudgetPeople` call (see `BudgetSetupViewModel.addPerson`) rather than
/// web's local-pending-then-batch-on-continue — see `CLAUDE.md` for why.
///
/// An email is optional. Given one, the person is also invited to the budget
/// with the chosen role, so a partner ends up with their own account rather
/// than a name someone else types transactions against.
struct PeopleSetupStepView: View {
    let viewModel: BudgetSetupViewModel
    @State private var name = ""
    @State private var email = ""
    @State private var role: Wellspent_V1_BudgetRole = .collaborator
    @State private var isAdding = false

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespaces)
    }

    private var isEmailInvalid: Bool {
        !trimmedEmail.isEmpty && !InviteEmail.isValid(trimmedEmail)
    }

    var body: some View {
        Form {
            Section("People on this budget") {
                if viewModel.people.isEmpty {
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.people, id: \.id) { person in
                        HStack {
                            ColorDotView(hex: person.color)
                            Text(person.userName)
                        }
                    }
                }
            }

            Section {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("setupPersonNameField")

                TextField("Email (optional)", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .accessibilityIdentifier("setupPersonEmailField")

                if isEmailInvalid {
                    Text("That doesn't look like an email address.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Only meaningful alongside an email — a person with no account
                // has nothing to hold a role. Disabled rather than hidden so
                // the row does not appear and vanish as the email is typed.
                Picker("They can", selection: $role) {
                    ForEach(InviteEmail.invitableRoles, id: \.self) { option in
                        Text(BudgetRoleLabel.text(for: option)).tag(option)
                    }
                }
                .disabled(trimmedEmail.isEmpty)
                .accessibilityIdentifier("setupPersonRolePicker")

                if !trimmedEmail.isEmpty {
                    Text(InviteEmail.roleDescription(for: role))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        isAdding = true
                        await viewModel.addPerson(name: name, email: trimmedEmail, role: role)
                        name = ""
                        email = ""
                        role = .collaborator
                        isAdding = false
                    }
                } label: {
                    if isAdding {
                        ProgressView()
                    } else {
                        Text("Add")
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isEmailInvalid || isAdding)
                .accessibilityIdentifier("setupAddPersonButton")
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section {
                Button("Continue") {
                    viewModel.advance()
                }
                .accessibilityIdentifier("setupSkipButton")
            }
        }
    }
}

#Preview {
    NavigationStack {
        PeopleSetupStepView(viewModel: BudgetSetupViewModel(authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")))
    }
}
