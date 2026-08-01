import SwiftUI
import WellSpentAPI

struct EditPersonColorView: View {
    @Environment(\.dismiss) private var dismiss
    let person: Wellspent_V1_BudgetPerson
    let onConfirm: (String) -> Void

    @State private var color: String

    init(person: Wellspent_V1_BudgetPerson, onConfirm: @escaping (String) -> Void) {
        self.person = person
        self.onConfirm = onConfirm
        _color = State(initialValue: person.color)
    }

    var body: some View {
        NavigationStack {
            VStack {
                PresetColorPickerView(hex: $color)
                    .padding()
                Spacer()
            }
            .navigationTitle("Choose Color")
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
                    .accessibilityIdentifier("confirmPersonColor")
                }
            }
        }
    }
}

#Preview {
    EditPersonColorView(person: .with {
        $0.id = 1
        $0.userName = "Jane"
        $0.color = PresetColors.all[2]
    }) { _ in }
}
