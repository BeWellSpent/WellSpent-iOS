import SwiftUI
import WellSpentAPI

/// Step 1 of `BudgetSetupFlow`. Each "Add" tap is its own immediate
/// `AddBudgetPeople` call (see `BudgetSetupViewModel.addPerson`) rather than
/// web's local-pending-then-batch-on-continue — see `CLAUDE.md` for why.
struct PeopleSetupStepView: View {
    let viewModel: BudgetSetupViewModel
    @State private var name = ""
    @State private var isAdding = false

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
                HStack {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("setupPersonNameField")
                    Button {
                        Task {
                            isAdding = true
                            await viewModel.addPerson(name: name)
                            name = ""
                            isAdding = false
                        }
                    } label: {
                        if isAdding {
                            ProgressView()
                        } else {
                            Text("Add")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
                    .accessibilityIdentifier("setupAddPersonButton")
                }
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
