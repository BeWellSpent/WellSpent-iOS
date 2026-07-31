import SwiftUI
import WellSpentAPI

/// `DeletePaymentMethod` unconditionally requires a replacement on the
/// backend, so this always shows the picker — unlike web, which silently
/// skips the picker when the method has no transactions. Checking "has
/// transactions" first would need an extra `ListTransactions` call across
/// every period, not just the current one; always asking is simpler and
/// still correct against the backend contract.
struct DeletePaymentMethodView: View {
    @Environment(\.dismiss) private var dismiss
    let method: Wellspent_V1_PaymentMethod
    let otherMethods: [Wellspent_V1_PaymentMethod]
    let personName: (Int64) -> String?
    let onConfirm: (String) -> Void

    @State private var replacementID: String = ""

    private var displayName: String {
        method.alias.isEmpty ? method.name : method.alias
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("All transactions using \"\(displayName)\" will be moved to the replacement method.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Replacement", selection: $replacementID) {
                        Text("Select a payment method").tag("")
                        ForEach(otherMethods, id: \.id) { other in
                            Text(rowLabel(for: other)).tag(other.id)
                        }
                    }
                    .accessibilityIdentifier("replacementPaymentMethodPicker")
                }
            }
            .navigationTitle("Delete Payment Method")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Delete", role: .destructive) {
                        onConfirm(replacementID)
                        dismiss()
                    }
                    .disabled(replacementID.isEmpty)
                    .accessibilityIdentifier("confirmDeletePaymentMethodButton")
                }
            }
        }
    }

    private func rowLabel(for method: Wellspent_V1_PaymentMethod) -> String {
        let name = method.alias.isEmpty ? method.name : method.alias
        guard let owner = personName(method.budgetPersonID) else { return name }
        return "\(name) · \(owner)"
    }
}

#Preview {
    DeletePaymentMethodView(
        method: .with { $0.id = "pm-1"; $0.name = "Chase Visa"; $0.budgetPersonID = 1 },
        otherMethods: [.with { $0.id = "pm-2"; $0.name = "Cash"; $0.budgetPersonID = 1 }],
        personName: { _ in "Jane" }
    ) { _ in }
}
