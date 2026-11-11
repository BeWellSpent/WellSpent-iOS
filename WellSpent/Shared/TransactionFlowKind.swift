import Foundation
import WellSpentAPI

/// What a transaction is, separate from its category (docs/features/transaction-flow.md).
/// Income and payment never count as spending; spend, refund and transfer do, signed.
nonisolated enum TransactionFlowKind: String, CaseIterable {
    case spend, refund, income, transfer, payment

    /// The server always sends a flow; an older row without one reads by its sign.
    static func of(_ transaction: Wellspent_V1_Transaction) -> TransactionFlowKind {
        TransactionFlowKind(rawValue: transaction.flow)
            ?? (TransactionAmountFormatting.isReceived(units: transaction.amount.units, nanos: transaction.amount.nanos) ? .refund : .spend)
    }

    var countsAsSpending: Bool { self != .income && self != .payment }

    var categoryRequired: Bool { self == .spend || self == .refund }

    /// Whether a row without a category should prompt for one: everything that counts toward a category.
    var categoryExpected: Bool { countsAsSpending }

    /// The "What was it?" chips for a direction. Payment is chosen from the Payments tab instead.
    static func choices(moneyIn: Bool) -> [TransactionFlowKind] {
        moneyIn ? [.refund, .income, .transfer] : [.spend, .transfer]
    }

    /// A fixed expense is always money going out.
    static let fixedChoices: [TransactionFlowKind] = [.spend, .transfer, .payment]

    /// Keeps a flow that still fits the direction; otherwise the direction's first choice.
    static func fitting(_ flow: TransactionFlowKind, moneyIn: Bool) -> TransactionFlowKind {
        if flow == .payment || choices(moneyIn: moneyIn).contains(flow) { return flow }
        return choices(moneyIn: moneyIn)[0]
    }

    var label: String {
        switch self {
        case .spend: String(localized: "Spend", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        case .refund: String(localized: "Refund", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        case .income: String(localized: "Income", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        case .transfer: String(localized: "Transfer", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        case .payment: String(localized: "Payment", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        }
    }

    var hint: String {
        switch self {
        case .spend:
            String(localized: "Counts toward its category.", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        case .refund:
            String(localized: "Money back on a purchase. Lowers its category's spending.", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        case .income:
            String(localized: "A paycheck or other income. Shows as income, never as spending.", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        case .transfer:
            String(localized: "Zelle, Venmo or a bank transfer. Counts toward its category, e.g. a friend paying you back for drinks lowers Eating Out. Moving money between your own accounts? Exclude it.", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        case .payment:
            String(localized: "Paying off a card. Not counted as spending; the purchases already were.", bundle: AppLanguageStore.currentBundle, locale: AppLanguageStore.currentLocale)
        }
    }

    /// The small tag on a list row; plain spending has none.
    var showsTag: Bool { self != .spend }
}
