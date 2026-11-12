import SwiftUI
import WellSpentAPI
import WellSpentREST

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
        SetupStepScaffold(step: .people) {
            HomeSectionHeader(title: Text("On this budget"))
            if viewModel.people.isEmpty {
                HomeCard { Text("Loading…").foregroundStyle(.secondary) }
            } else {
                SetupAddedList(items: viewModel.people) { person in
                    HStack(spacing: 12) {
                        ColorDotView(hex: person.color)
                        SetupRowText(title: person.userName, detail: BudgetRoleLabel.text(for: person.role))
                    }
                }
            }

            HomeSectionHeader(title: Text("Add someone"))
            addForm

            if let errorMessage = viewModel.errorMessage {
                InlineErrorBanner(message: errorMessage)
            }
        } action: {
            Button("Continue") { viewModel.advance() }
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityIdentifier("setupSkipButton")
        }
    }

    private var addForm: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 14) {
                LabeledFieldBox(label: Text("Name")) {
                    TextField("e.g. Sam", text: $name)
                        .accessibilityIdentifier("setupPersonNameField")
                }

                LabeledFieldBox(
                    label: Text("Email (optional)"),
                    footnote: isEmailInvalid ? Text("That doesn't look like an email address.") : Text("Sends them an invite to the app.")
                ) {
                    TextField("sam@example.com", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .accessibilityIdentifier("setupPersonEmailField")
                }

                // Only meaningful with an email: a person with no account has nothing to hold a role.
                VStack(alignment: .leading, spacing: 8) {
                    Text("They can")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("They can", selection: $role) {
                        ForEach(InviteEmail.invitableRoles, id: \.self) { option in
                            Text(BudgetRoleLabel.text(for: option)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(trimmedEmail.isEmpty)
                    .accessibilityIdentifier("setupPersonRolePicker")
                    Text(InviteEmail.roleDescription(for: role))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .opacity(trimmedEmail.isEmpty ? 0.5 : 1)

                SetupAddButton(title: Text("Add person"), isWorking: isAdding) {
                    Task {
                        isAdding = true
                        await viewModel.addPerson(name: name, email: trimmedEmail, role: role)
                        name = ""
                        email = ""
                        role = .collaborator
                        isAdding = false
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isEmailInvalid || isAdding)
                .accessibilityIdentifier("setupAddPersonButton")
            }
        }
    }
}

#Preview {
    NavigationStack {
        PeopleSetupStepView(viewModel: BudgetSetupViewModel(
            restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        ))
    }
}
