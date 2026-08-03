import Foundation
import WellSpentAPI

/// Display text for a `PaymentType`.
nonisolated enum PaymentTypeLabel {
    static func text(for type: Wellspent_V1_PaymentType) -> String {
        let locale = AppLanguageStore.currentLocale
        switch type {
        case .unspecified: return String(localized: "Unspecified", locale: locale)
        case .cash: return String(localized: "Cash", locale: locale)
        case .credit: return String(localized: "Credit", locale: locale)
        case .debit: return String(localized: "Debit", locale: locale)
        case .digitalWallet: return String(localized: "Digital Wallet", locale: locale)
        case .bankTransfer: return String(localized: "Bank Transfer", locale: locale)
        case .crypto: return String(localized: "Crypto", locale: locale)
        case .investment: return String(localized: "Investment", locale: locale)
        case .other: return String(localized: "Other", locale: locale)
        case .UNRECOGNIZED: return String(localized: "Unknown", locale: locale)
        }
    }

    /// All selectable types, in display order, for pickers.
    static let selectable: [Wellspent_V1_PaymentType] = [
        .cash, .credit, .debit, .digitalWallet, .bankTransfer, .crypto, .investment, .other,
    ]
}
