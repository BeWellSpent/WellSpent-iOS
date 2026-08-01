import SwiftUI
import WellSpentAPI

/// Mirrors web's `BudgetPickerDialog.tsx` — which budget new imported
/// transactions should be written to, for a fresh Plaid connect.
struct BudgetPickerSheet: View {
    let budgets: [Wellspent_V1_BudgetProfile]
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if budgets.isEmpty {
                    Text("No budgets yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(budgets, id: \.id) { budget in
                        Button(budget.name) {
                            onSelect(budget.id)
                        }
                        .accessibilityIdentifier("pickBudget_\(budget.name)")
                    }
                }
            }
            .navigationTitle("Choose a Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    BudgetPickerSheet(
        budgets: [.with { $0.id = "1"; $0.name = "Household Budget" }],
        onSelect: { _ in }
    )
}
