import SwiftUI
import WellSpentAPI

/// A Fixed transaction row in the merged list. Never reaches here if it was
/// settled by a confirmed Transaction Review match — that Variable row shows
/// instead, fully editable, with an expand of its own showing this bill (see
/// `TransactionReviewMatching`, issue #97). This row is strictly a plain,
/// non-expanding row now.
///
/// Extracted out of `FixedExpensesListView` (Stage 2 of
/// docs/features/overview-plan-navigation-rework.md) so the merged
/// Transactions list can render a Fixed row directly — parameterized over
/// `TransactionsViewModel`, which now carries the lookups this row needs
/// (category/payment-method names and colors, payments progress, paid-off-
/// early), rather than `FixedExpensesViewModel`.
struct FixedExpenseRow: View {
    let transaction: Wellspent_V1_Transaction
    let viewModel: TransactionsViewModel
    let currencyCode: String
    let localeIdentifier: String
    let canMutate: Bool
    /// The budget's auto_update_planned_amount setting — drives the re-plan marker.
    let autoUpdatePlannedAmount: Bool
    @State private var isRePlanNoticePresented = false

    /// Paid at a different amount than planned, with the setting on that
    /// would carry the real amount into future periods — see
    /// `rePlanMarker`'s doc comment for why this stays its own inline
    /// affordance rather than a swipe action.
    private var showsRePlanNotice: Bool {
        transaction.isPaid && autoUpdatePlannedAmount && !transaction.fixedExpenseID.isEmpty
            && MoneyFormatting.differs(transaction.amount, transaction.plannedAmount)
    }

    var body: some View {
        HStack {
            fixedExpenseNameContent
                .accessibilityIdentifier("fixedExpenseRow_\(transaction.name)")

            Spacer()

            // Informational, not a mutation, so it stays its own
            // inline affordance rather than joining mark-paid/match/
            // exclude/delete on a swipe action (issue #92).
            if canMutate && showsRePlanNotice {
                rePlanMarker
            }

            // Planned, not what was actually paid — see rePlanMarker.
            Text(MoneyFormatting.format(
                units: transaction.plannedAmount.units,
                nanos: transaction.plannedAmount.nanos,
                currencyCode: currencyCode,
                localeIdentifier: localeIdentifier
            ))
            .foregroundStyle(.primary)
        }
    }

    /// No hover on iOS, so this is a tappable popover rather than web's
    /// tooltip.
    private var rePlanMarker: some View {
        Button {
            isRePlanNoticePresented = true
        } label: {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rePlanMarker_\(transaction.name)")
        .popover(isPresented: $isRePlanNoticePresented) {
            Text("Paid at a different amount than planned. From the next period on, this bill will be planned at what you actually paid.")
                .font(.footnote)
                .padding()
                .frame(maxWidth: 280)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var fixedExpenseNameContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(transaction.name)
                    .foregroundStyle(.primary)
                // The payment that settled the plan's remaining balance
                // early — the template deactivates and disappears from
                // `listFixedExpenses`, so this is its only lasting record.
                if viewModel.isPaidOffEarly(transaction) {
                    Text("(paid off early)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("paidOffEarlyBadge_\(transaction.name)")
                }
            }
            HStack(spacing: 4) {
                if let categoryName = viewModel.categoryName(for: transaction.categoryID) {
                    ColorDotView(hex: viewModel.categoryColor(for: transaction.categoryID), diameter: 8)
                    Text(categoryName)
                }
                if let methodName = viewModel.paymentMethodName(for: transaction.paymentMethodID) {
                    Text("·")
                    ColorDotView(hex: viewModel.paymentMethodColor(for: transaction.paymentMethodID), diameter: 8)
                    Text(methodName)
                }
                if let progressText = viewModel.paymentsProgressText(for: transaction) {
                    Text("·")
                    Text(progressText)
                        .accessibilityIdentifier("fixedExpensePaymentsProgress_\(transaction.name)")
                }
                Text("·")
                // `.dateOnly`, not `.date` — see Shared/DateOnly.swift.
                Text(transaction.date.dateOnly.formatted(
                    Date.FormatStyle(locale: Locale(identifier: localeIdentifier)).month(.abbreviated).day()
                ))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
