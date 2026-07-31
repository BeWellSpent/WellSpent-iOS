import SwiftUI
import WellSpentAPI

struct EditPersonColorView: View {
    @Environment(\.dismiss) private var dismiss
    let person: Wellspent_V1_BudgetPerson
    let onConfirm: (String) -> Void

    var body: some View {
        NavigationStack {
            List(PresetColors.all, id: \.self) { hex in
                Button {
                    onConfirm(hex)
                    dismiss()
                } label: {
                    HStack {
                        Text(hex)
                        Spacer()
                        if person.color == hex {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityIdentifier("colorOption_\(hex)")
            }
            .navigationTitle("Choose Color")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
