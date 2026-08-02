import SwiftUI
import WellSpentAPI

/// Step 3 (final) of `BudgetSetupFlow`. Hosts `AddPaymentMethodViewModel`
/// as-is — each successful add is followed by a fresh instance so the form
/// resets. `personID` is pre-set to the first/only person on construction,
/// matching web's auto-preselect; the person picker itself is only shown
/// when there's more than one person to choose from, also matching web.
struct PaymentMethodsSetupStepView: View {
    let people: [Wellspent_V1_BudgetPerson]
    let authenticatedClient: ProtocolClient
    let onFinish: () -> Void

    @State private var viewModel: AddPaymentMethodViewModel
    @State private var addedMethods: [Wellspent_V1_PaymentMethod] = []

    init(people: [Wellspent_V1_BudgetPerson], authenticatedClient: ProtocolClient, onFinish: @escaping () -> Void) {
        self.people = people
        self.authenticatedClient = authenticatedClient
        self.onFinish = onFinish
        let initial = AddPaymentMethodViewModel(authenticatedClient: authenticatedClient)
        initial.personID = people.first?.id ?? 0
        _viewModel = State(initialValue: initial)
    }

    var body: some View {
        Form {
            if !addedMethods.isEmpty {
                Section("Added so far") {
                    ForEach(addedMethods, id: \.id) { method in
                        Text(method.name)
                    }
                }
            }

            Section {
                TextField("Name", text: $viewModel.name)
                    .accessibilityIdentifier("setupPaymentMethodNameField")

                Picker("Type", selection: $viewModel.type) {
                    ForEach(PaymentTypeLabel.selectable, id: \.self) { type in
                        Text(PaymentTypeLabel.text(for: type)).tag(type)
                    }
                }

                if people.count > 1 {
                    Picker("Owner", selection: $viewModel.personID) {
                        ForEach(people, id: \.id) { person in
                            ColorDotLabel(title: person.userName, hex: person.color).tag(person.id)
                        }
                    }
                }

                Button {
                    Task {
                        if let method = await viewModel.submit() {
                            addedMethods.append(method)
                            let fresh = AddPaymentMethodViewModel(authenticatedClient: authenticatedClient)
                            fresh.personID = people.first?.id ?? 0
                            viewModel = fresh
                        }
                    }
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Text("Add")
                    }
                }
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier("setupAddPaymentMethodButton")
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section {
                Button("Finish") { onFinish() }
                    .accessibilityIdentifier("setupSkipButton")
            }
        }
    }
}

#Preview {
    NavigationStack {
        PaymentMethodsSetupStepView(
            people: [.with { $0.id = 1; $0.userName = "Jane" }],
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        ) {}
    }
}
