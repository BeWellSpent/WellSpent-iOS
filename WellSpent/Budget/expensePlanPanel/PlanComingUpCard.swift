import SwiftUI
import WellSpentAPI

/// When the fixed baseline drops as payment plans end. Pro only: Free sees a
/// blurred placeholder under the "coming soon" note.
struct PlanComingUpCard: View {
    let projection: FixedExpenseProjectionMapping.Projection?
    let currencyCode: String
    let localeIdentifier: String

    var body: some View {
        if projection?.locked == true {
            locked
        } else if let drops = projection?.drops, !drops.isEmpty {
            HomeCard {
                ForEach(Array(drops.enumerated()), id: \.offset) { index, drop in
                    if index > 0 { Divider() }
                    row(month: Text(drop.endsOn.formatted(Date.FormatStyle().month(.wide).year().locale(Locale(identifier: localeIdentifier)))),
                        names: Text(drop.names.joined(separator: ", ")),
                        amount: "−\(format(drop.amount.units, drop.amount.nanos))")
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier("planComingUp")
        } else if projection != nil {
            HomeCard {
                Text("No payment plans end in the next six months.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    /// Placeholder rows, not real data: Free never receives the projection.
    private var locked: some View {
        HomeCard {
            ForEach(0..<2, id: \.self) { index in
                if index > 0 { Divider() }
                row(month: Text(verbatim: "December 2026"), names: Text(verbatim: "Payment plan ends"), amount: "−$420")
            }
        }
        .redacted(reason: .placeholder)
        .blur(radius: 4)
        .accessibilityHidden(true)
        .overlay {
            ProLockedNote(message: Text("See when your fixed costs go down"))
                .padding(.horizontal, 24)
        }
        .accessibilityIdentifier("planComingUpLocked")
    }

    private func row(month: Text, names: Text, amount: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
                .frame(width: 32, height: 32)
                .background(Color.green.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                month.font(.subheadline.weight(.semibold))
                names.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: amount)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.green)
                .monospacedDigit()
        }
    }

    private func format(_ units: Int64, _ nanos: Int32) -> String {
        MoneyFormatting.format(units: units, nanos: nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }
}
