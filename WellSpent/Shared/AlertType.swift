import Foundation

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
        let locale = AppLanguageStore.currentLocale
        switch self {
        case .newTransaction: return String(localized: "New Transaction", locale: locale)
        case .spendingThreshold: return String(localized: "Spending Threshold", locale: locale)
        case .periodCreated: return String(localized: "New Budget Period", locale: locale)
        case .reviewPending: return String(localized: "Review Pending", locale: locale)
        }
    }

    var explanation: String {
        let locale = AppLanguageStore.currentLocale
        switch self {
        case .newTransaction: return String(localized: "Another member adds a transaction to this budget.", locale: locale)
        case .spendingThreshold: return String(localized: "Spending crosses a percentage of the plan you set.", locale: locale)
        case .periodCreated: return String(localized: "A new budget period starts.", locale: locale)
        case .reviewPending: return String(localized: "A bank-imported transaction is queued for review.", locale: locale)
        }
    }
}
