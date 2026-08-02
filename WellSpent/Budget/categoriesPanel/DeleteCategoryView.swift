import SwiftUI
import WellSpentAPI

/// `DeleteCategory` unconditionally requires a replacement on the backend
/// (unlike removing a budget person in 2A, where a replacement is only
/// needed sometimes), so this always shows the picker — no
/// needs-replacement check to make first.
struct DeleteCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    let category: Wellspent_V1_Category
    let otherCategories: [Wellspent_V1_Category]
    let onConfirm: (Int32) -> Void

    @State private var replacementID: Int32 = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("All transactions in \"\(category.name)\" will be moved to the replacement category.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ColorDotPickerField(
                        title: "Replacement",
                        selection: $replacementID,
                        options: otherCategories.map {
                            ColorDotOption(id: $0.id, name: $0.isSystem ? "\($0.name) (System)" : $0.name, hex: $0.color)
                        },
                        noneOption: (id: Int32(0), label: "Select a category"),
                        accessibilityIdentifier: "replacementCategoryPicker"
                    )
                }
            }
            .navigationTitle("Delete Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Delete", role: .destructive) {
                        onConfirm(replacementID)
                        dismiss()
                    }
                    .disabled(replacementID == 0)
                    .accessibilityIdentifier("confirmDeleteCategoryButton")
                }
            }
        }
    }
}

#Preview {
    DeleteCategoryView(
        category: .with { $0.id = 1; $0.name = "Groceries" },
        otherCategories: [
            .with { $0.id = 2; $0.name = "Dining"; $0.isSystem = true },
            .with { $0.id = 3; $0.name = "Shopping" },
        ]
    ) { _ in }
}
