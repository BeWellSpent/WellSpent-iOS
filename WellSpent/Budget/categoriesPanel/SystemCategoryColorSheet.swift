import SwiftUI
import WellSpentAPI

/// Color-only editor for a system category — mirrors web's
/// `SystemColorDialog.tsx`. System categories can't be renamed or deleted,
/// but each user can still color-code them for their own view.
struct SystemCategoryColorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let category: Wellspent_V1_Category
    let onConfirm: (String) -> Void

    @State private var color: String

    init(category: Wellspent_V1_Category, onConfirm: @escaping (String) -> Void) {
        self.category = category
        self.onConfirm = onConfirm
        _color = State(initialValue: category.color)
    }

    var body: some View {
        NavigationStack {
            VStack {
                PresetColorPickerView(hex: $color)
                    .padding()
                Spacer()
            }
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onConfirm(color)
                        dismiss()
                    }
                    .accessibilityIdentifier("confirmSystemCategoryColor")
                }
            }
        }
    }
}

#Preview {
    SystemCategoryColorSheet(category: .with {
        $0.id = 1
        $0.name = "Groceries"
        $0.isSystem = true
        $0.color = PresetColors.all[2]
    }) { _ in }
}
