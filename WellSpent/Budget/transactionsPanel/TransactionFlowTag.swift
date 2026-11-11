import SwiftUI

/// The small pill beside a row's category saying what kind of movement it was.
/// Plain spending has none.
struct TransactionFlowTag: View {
    let flow: TransactionFlowKind

    var body: some View {
        if flow.showsTag {
            Text(flow.label)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .foregroundStyle(tint)
                .background(tint.opacity(0.14), in: Capsule())
                .accessibilityIdentifier("transactionFlowTag_\(flow.rawValue)")
        }
    }

    private var tint: Color {
        switch flow {
        case .refund: .green
        case .transfer: .blue
        case .income, .payment, .spend: .secondary
        }
    }
}
