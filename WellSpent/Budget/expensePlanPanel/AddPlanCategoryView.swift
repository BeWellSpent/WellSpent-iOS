import SwiftUI
import WellSpentAPI

/// Picker sheet for categories not yet visible in the Plan list. Selecting
/// one dismisses this sheet and hands the category back to `ExpensePlanView`,
/// which presents `AllocateCategoryView` for it — kept as a flat selection
/// list rather than nesting a second sheet inside this one.
struct AddPlanCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [Wellspent_V1_Category]
    let onSelect: (Wellspent_V1_Category) -> Void

    var body: some View {
        NavigationStack {
            List {
                if categories.isEmpty {
                    Text("Every category is already in the plan.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(categories, id: \.id) { category in
                        Button {
                            onSelect(category)
                            dismiss()
                        } label: {
                            HStack {
                                ColorDotView(hex: category.color)
                                Text(category.displayName)
                            }
                        }
                        .accessibilityIdentifier("addPlanCategory_\(category.name)")
                    }
                }
            }
            .navigationTitle("Add Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    AddPlanCategoryView(
        categories: [
            .with { $0.id = 1; $0.name = "Entertainment" },
            .with { $0.id = 2; $0.name = "Travel" }
        ]
    ) { _ in }
}
