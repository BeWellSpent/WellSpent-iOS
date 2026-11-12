import SwiftUI
import WellSpentAPI

/// One pending match: the bill, the transaction(s) that look like it, and Confirm / Not a match.
struct ReviewMatchCard: View {
    let group: ReviewGroup
    let spansOutsideMyView: Bool
    let currencyCode: String
    let localeIdentifier: String
    let canEdit: Bool
    let onDismiss: () -> Void
    let onConfirm: () -> Void

    private var score: Double { group.reviews.map(\.matchScore).max() ?? 0 }
    private var isStrong: Bool { score >= ReviewFilter.strongScore }

    private func format(_ money: Wellspent_V1_Money) -> String {
        MoneyFormatting.format(units: money.units, nanos: money.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            billRow
            VStack(alignment: .leading, spacing: 6) {
                ForEach(group.reviews, id: \.id) { review in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: review.transactionName).font(.body.weight(.semibold))
                            Text(verbatim: ReviewLineDetail.text(for: review, localeIdentifier: localeIdentifier))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Text(verbatim: format(review.transactionAmount))
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                    }
                }
                if group.reviews.count > 1 {
                    let total = TransactionAmountFormatting.sum(group.reviews.map { (units: $0.transactionAmount.units, nanos: $0.transactionAmount.nanos) })
                    Divider()
                    HStack {
                        Text("Together")
                        Spacer()
                        Text(verbatim: MoneyFormatting.format(units: total.units, nanos: total.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier))
                            .monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            if spansOutsideMyView {
                Label("Involves someone else's data. Turn off Just me to review it.", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("reviewSpansOutsideView_\(group.matchedTransactionID)")
            }

            if canEdit {
                HStack(spacing: 8) {
                    Button("Not a match", action: onDismiss)
                        .buttonStyle(OutlinedActionButtonStyle())
                        .accessibilityIdentifier("dismissReview_\(group.matchedTransactionID)")
                    Button("Confirm", action: onConfirm)
                        .buttonStyle(PrimaryActionButtonStyle())
                        .accessibilityIdentifier("confirmReview_\(group.matchedTransactionID)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("reviewRow_\(group.matchedTransactionName)")
    }

    private var billRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet")
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
                .frame(width: 26, height: 26)
                .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            billText
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            (isStrong ? Text("\(Int(score))% · strong") : Text("\(Int(score))% · possible"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(isStrong ? Color.green : Color.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((isStrong ? Color.green : Color.orange).opacity(0.14), in: Capsule())
                .accessibilityIdentifier("reviewScore_\(group.reviews.first?.id ?? "")")
        }
    }

    private var billText: Text {
        let planned = group.reviews.first.flatMap { $0.hasMatchedTransactionPlannedAmount ? format($0.matchedTransactionPlannedAmount) : nil }
        if let planned {
            return Text("Matches \(group.matchedTransactionName) · \(planned)")
        }
        return Text("Matches \(group.matchedTransactionName)")
    }
}
