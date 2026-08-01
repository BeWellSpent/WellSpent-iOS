import SwiftUI
import WellSpentAPI

struct AllocateCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AllocateCategoryViewModel
    private let currencyCode: String
    private let onSave: (
        _ upserted: [(budgetPersonID: Int64, categoryID: Int32, plannedAmount: Wellspent_V1_Money)],
        _ deletedIDs: [Int64]
    ) -> Void

    init(
        category: Wellspent_V1_Category,
        people: [Wellspent_V1_BudgetPerson],
        existingAllocations: [Wellspent_V1_ExpenseAllocation],
        currencyCode: String,
        onSave: @escaping (
            _ upserted: [(budgetPersonID: Int64, categoryID: Int32, plannedAmount: Wellspent_V1_Money)],
            _ deletedIDs: [Int64]
        ) -> Void
    ) {
        _viewModel = State(initialValue: AllocateCategoryViewModel(
            category: category,
            people: people,
            existingAllocations: existingAllocations
        ))
        self.currencyCode = currencyCode
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(viewModel.rows) { row in
                        LabeledContent(row.person.userName) {
                            AmountTextField(text: viewModel.amountText(for: row.id))
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("allocateAmountField_\(row.person.userName)")
                        }
                    }
                } footer: {
                    Text("Leave an amount blank to remove that person's allocation for this category.")
                }
            }
            .navigationTitle(viewModel.category.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let changes = viewModel.computeChanges(currencyCode: currencyCode)
                        onSave(changes.upserted, changes.deletedIDs)
                        dismiss()
                    }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("saveAllocationsButton")
                }
            }
        }
    }
}

#Preview {
    AllocateCategoryView(
        category: .with { $0.id = 1; $0.name = "Groceries" },
        people: [
            .with { $0.id = 1; $0.userName = "Alex" },
            .with { $0.id = 2; $0.userName = "Sam" }
        ],
        existingAllocations: [
            .with {
                $0.id = 10
                $0.categoryID = 1
                $0.budgetPersonID = 1
                $0.plannedAmount = .with { $0.units = 200; $0.currency = "USD" }
            }
        ],
        currencyCode: "USD"
    ) { _, _ in }
}
