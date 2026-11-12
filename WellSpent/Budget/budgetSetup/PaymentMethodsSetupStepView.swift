import SwiftUI
import WellSpentAPI
import WellSpentREST

/// Step 3 (final) of `BudgetSetupFlow`. Hosts `AddPaymentMethodViewModel`
/// as-is — each successful add is followed by a fresh instance so the form
/// resets. `personID` is pre-set to the first/only person on construction,
/// matching web's auto-preselect; the person picker itself is only shown
/// when there's more than one person to choose from, also matching web.
struct PaymentMethodsSetupStepView: View {
    let people: [Wellspent_V1_BudgetPerson]
    let restClient: WellSpentREST.Client
    let onFinish: () -> Void

    @State private var viewModel: AddPaymentMethodViewModel
    @State private var addedMethods: [Wellspent_V1_PaymentMethod] = []

    init(people: [Wellspent_V1_BudgetPerson], restClient: WellSpentREST.Client, onFinish: @escaping () -> Void) {
        self.people = people
        self.restClient = restClient
        self.onFinish = onFinish
        let initial = AddPaymentMethodViewModel(restClient: restClient)
        initial.personID = people.first?.id ?? 0
        _viewModel = State(initialValue: initial)
    }

    var body: some View {
        SetupStepScaffold(step: .paymentMethods) {
            if !addedMethods.isEmpty {
                HomeSectionHeader(title: Text("Added so far"))
                SetupAddedList(items: addedMethods) { method in
                    HStack(spacing: 12) {
                        ColorDotView(hex: method.color)
                        SetupRowText(title: method.name, detail: detail(for: method))
                    }
                }
            }

            HomeSectionHeader(title: Text("Add a card or account"))
            addForm

            if let errorMessage = viewModel.errorMessage {
                InlineErrorBanner(message: errorMessage)
            }
        } action: {
            Button("Continue") { onFinish() }
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityIdentifier("setupSkipButton")
        }
    }

    private var addForm: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 14) {
                LabeledFieldBox(label: Text("Name")) {
                    TextField("e.g. Amex Gold", text: $viewModel.name)
                        .accessibilityIdentifier("setupPaymentMethodNameField")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Type")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(PaymentTypeLabel.selectable, id: \.self) { type in
                            typeChip(type)
                        }
                    }
                }

                if people.count > 1 {
                    ColorDotPickerField(
                        title: "Belongs to",
                        selection: $viewModel.personID,
                        options: people.map { ColorDotOption(id: $0.id, name: $0.userName, hex: $0.color) },
                        accessibilityIdentifier: "setupOwnerPicker"
                    )
                }

                SetupAddButton(title: Text("Add payment method"), isWorking: viewModel.isSubmitting) {
                    Task {
                        if let method = await viewModel.submit() {
                            addedMethods.append(method)
                            let fresh = AddPaymentMethodViewModel(restClient: restClient)
                            fresh.personID = people.first?.id ?? 0
                            viewModel = fresh
                        }
                    }
                }
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier("setupAddPaymentMethodButton")
            }
        }
    }

    private func typeChip(_ type: Wellspent_V1_PaymentType) -> some View {
        let isSelected = viewModel.type == type
        return Button {
            viewModel.type = type
        } label: {
            Text(PaymentTypeLabel.text(for: type))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.horizontal, 8)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Color.accentColor : Color(.separator)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func detail(for method: Wellspent_V1_PaymentMethod) -> String {
        let owner = people.first { $0.id == method.budgetPersonID }?.userName
        return [PaymentTypeLabel.text(for: method.type), owner].compactMap { $0 }.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        PaymentMethodsSetupStepView(
            people: [.with { $0.id = 1; $0.userName = "Jane" }],
            restClient: RESTClient.makePublicClient(baseURL: "http://localhost:1")
        ) {}
    }
}
