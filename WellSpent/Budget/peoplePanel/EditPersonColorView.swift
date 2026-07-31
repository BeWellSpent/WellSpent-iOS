import SwiftUI
import WellSpentAPI

struct EditPersonColorView: View {
    @Environment(\.dismiss) private var dismiss
    let person: Wellspent_V1_BudgetPerson
    let onConfirm: (String) -> Void

    private static let presetColors = [
        "#EF5350", "#AB47BC", "#5C6BC0", "#29B6F6",
        "#26A69A", "#9CCC65", "#FFCA28", "#8D6E63",
    ]

    var body: some View {
        NavigationStack {
            List(Self.presetColors, id: \.self) { hex in
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
