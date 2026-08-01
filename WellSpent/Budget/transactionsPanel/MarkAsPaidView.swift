import SwiftUI
import WellSpentAPI

/// Small confirmation sheet — no network call of its own. Amount/date are
/// prefilled from the transaction (planned amount, its scheduled date);
/// confirming just hands the built `Money` + date back to the caller, which
/// delegates to `FixedExpensesViewModel.markPaid`. The backend, not this
/// view, is responsible for propagating a changed amount back to the
/// `FixedExpense` template.
struct MarkAsPaidView: View {
    @Environment(\.dismiss) private var dismiss
    let currencyCode: String
    let onConfirm: (Wellspent_V1_Money, Date) -> Void

    @State private var amountText: String
    @State private var paidDate: Date

    init(transaction: Wellspent_V1_Transaction, currencyCode: String, onConfirm: @escaping (Wellspent_V1_Money, Date) -> Void) {
        self.currencyCode = currencyCode
        self.onConfirm = onConfirm
        _amountText = State(initialValue: MoneyInput.formatForEditing(
            units: transaction.plannedAmount.units,
            nanos: transaction.plannedAmount.nanos
        ))
        _paidDate = State(initialValue: transaction.hasDate ? transaction.date.dateOnly : Date())
    }

    private var canConfirm: Bool {
        MoneyInput.parseAmount(amountText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("markAsPaidAmountField")

                DatePicker("Paid date", selection: $paidDate, displayedComponents: .date)
                    .accessibilityIdentifier("markAsPaidDatePicker")
            }
            .navigationTitle("Mark as Paid")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        if let amount = MoneyInput.parseAmount(amountText) {
                            let money = Wellspent_V1_Money.with {
                                $0.units = amount.units
                                $0.nanos = amount.nanos
                                $0.currency = currencyCode
                            }
                            onConfirm(money, paidDate)
                            dismiss()
                        }
                    }
                    .disabled(!canConfirm)
                    .accessibilityIdentifier("confirmMarkAsPaidButton")
                }
            }
        }
    }
}

#Preview {
    MarkAsPaidView(
        transaction: .with {
            $0.plannedAmount = .with { $0.units = 1500; $0.currency = "USD" }
        },
        currencyCode: "USD"
    ) { _, _ in }
}
