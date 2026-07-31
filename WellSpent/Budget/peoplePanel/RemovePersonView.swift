import SwiftUI
import WellSpentAPI

struct RemovePersonView: View {
    @Environment(\.dismiss) private var dismiss
    let person: Wellspent_V1_BudgetPerson
    let otherPeople: [Wellspent_V1_BudgetPerson]
    let needsReplacement: Bool
    let onConfirm: (Int64) -> Void

    @State private var replacementID: Int64 = 0

    var body: some View {
        NavigationStack {
            Form {
                if needsReplacement {
                    Section {
                        Text("\(person.userName) has income attributed to them. Choose who to reassign it to before removing them.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("Reassign to", selection: $replacementID) {
                            Text("Select a person").tag(Int64(0))
                            ForEach(otherPeople, id: \.id) { p in
                                Text(p.userName).tag(p.id)
                            }
                        }
                        .accessibilityIdentifier("replacementPersonPicker")
                    }
                } else {
                    Section {
                        Text("Remove \(person.userName) from this budget?")
                    }
                }
            }
            .navigationTitle("Remove Person")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Remove", role: .destructive) {
                        onConfirm(replacementID)
                        dismiss()
                    }
                    .disabled(needsReplacement && replacementID == 0)
                    .accessibilityIdentifier("confirmRemovePersonButton")
                }
            }
        }
    }
}

#Preview("Needs replacement") {
    RemovePersonView(
        person: .with { $0.id = 1; $0.userName = "Jane" },
        otherPeople: [.with { $0.id = 2; $0.userName = "John" }],
        needsReplacement: true
    ) { _ in }
}

#Preview("No replacement needed") {
    RemovePersonView(
        person: .with { $0.id = 1; $0.userName = "Jane" },
        otherPeople: [],
        needsReplacement: false
    ) { _ in }
}
