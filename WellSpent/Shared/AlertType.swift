/// `AlertSubscription.alert_type` / `Notification.alert_type` are plain
/// strings on the wire, not a proto enum (unlike `BudgetRole`/`InviteStatus`)
/// — same "raw wire constant" pattern as `transaction_type_id`. This wraps
/// the documented values (`notification.proto`) in a real Swift enum.
nonisolated enum AlertType: String, CaseIterable {
    case newTransaction = "new_transaction"
    case spendingThreshold = "spending_threshold"
    case periodCreated = "period_created"
    case reviewPending = "review_pending"

    /// All four types, in display order.
    static let all: [AlertType] = [.newTransaction, .spendingThreshold, .periodCreated, .reviewPending]

    var label: String {
        switch self {
        case .newTransaction: return "New Transaction"
        case .spendingThreshold: return "Spending Threshold"
        case .periodCreated: return "New Budget Period"
        case .reviewPending: return "Review Pending"
        }
    }

    var explanation: String {
        switch self {
        case .newTransaction: return "Another member adds a transaction to this budget."
        case .spendingThreshold: return "Spending crosses a percentage of the plan you set."
        case .periodCreated: return "A new budget period starts."
        case .reviewPending: return "A bank-imported transaction is queued for review."
        }
    }
}
