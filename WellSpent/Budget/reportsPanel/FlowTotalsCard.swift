import SwiftUI
import WellSpentAPI

/// Money in · out · moved for a period (canvas "Reports" page, Trends). Every figure,
/// the In and Out totals included, is the server's.
struct FlowTotalsCard: View {
    let flows: ReportsRESTMapping.Flows
    let periodLabel: String
    let currencyCode: String
    let localeIdentifier: String

    private enum Direction { case inbound, outbound, card }

    var body: some View {
        HomeCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Money in · out · moved").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: periodLabel).font(.caption).foregroundStyle(.secondary)
            }

            HStack(alignment: .top) {
                total(Text("In"), "+" + format(flows.moneyIn), color: .green, id: "flowsMoneyIn")
                total(Text("Out"), format(flows.moneyOut), color: .primary, id: "flowsMoneyOut")
            }

            VStack(spacing: 0) {
                line(Text("Income"), sub: nil, flows.income, .inbound, icon: "arrow.down", first: true)
                line(Text("Refunds"), sub: Text("Lowered their categories"), flows.refunds, .inbound, icon: "arrow.down")
                line(Text("Transfers in"), sub: nil, flows.transfersIn, .inbound, icon: "arrow.left.arrow.right")
                line(Text("Spent"), sub: nil, flows.spent, .outbound, icon: "arrow.up")
                line(Text("Transfers out"), sub: nil, flows.transfersOut, .outbound, icon: "arrow.left.arrow.right")
                line(Text("Paid to cards"), sub: Text("Already counted as spending"), flows.paidToCards, .card, icon: "creditcard")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reportsFlowTotals")
    }

    private func total(_ label: Text, _ amount: String, color: Color, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(verbatim: amount).font(.title2.bold()).foregroundStyle(color).monospacedDigit()
                .accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ label: Text, sub: Text?, _ amount: Wellspent_V1_Money, _ direction: Direction, icon: String, first: Bool = false) -> some View {
        let tint: Color = switch direction {
        case .inbound: .green
        case .outbound: .red
        case .card: .secondary
        }
        return VStack(spacing: 0) {
            if !first { Divider() }
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    label.font(.subheadline)
                    if let sub { sub.font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(verbatim: (direction == .inbound ? "+" : "") + format(amount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(direction == .inbound ? .green : (direction == .card ? .secondary : .primary))
                    .monospacedDigit()
            }
            .padding(.vertical, 6)
        }
    }

    private func format(_ money: Wellspent_V1_Money) -> String {
        MoneyFormatting.format(units: money.units, nanos: money.nanos, currencyCode: currencyCode, localeIdentifier: localeIdentifier)
    }
}
